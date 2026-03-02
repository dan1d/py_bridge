defmodule PyBridge.Worker do
  @moduledoc """
  GenServer that owns a long-running Python Port process.

  Communicates with Python via JSON-RPC 2.0 over stdin/stdout.
  Supervisor-managed: if the Python process crashes, the GenServer
  terminates and the supervisor restarts it.

  ## Options

    * `:name` - registered name for the GenServer (required)
    * `:python` - path to Python executable (default: `"python3"`)
    * `:script` - path to the Python worker script (required)
    * `:env` - list of `{key, value}` environment variables for the Python process
    * `:cd` - working directory for the Python process
  """

  use GenServer
  require Logger

  alias PyBridge.Protocol

  defstruct [
    :port,
    :python,
    :script,
    :env,
    :cd,
    :name,
    next_id: 1,
    buffer: "",
    pending: %{},
    timers: %{}
  ]

  @type t :: %__MODULE__{
          port: port() | nil,
          python: String.t(),
          script: String.t(),
          env: list({charlist(), charlist()}) | nil,
          cd: charlist() | nil,
          name: atom(),
          next_id: integer(),
          buffer: binary(),
          pending: map(),
          timers: map()
        }

  # --- Child spec ---

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  # --- Public API ---

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    python = Keyword.get(opts, :python, "python3")
    script = Keyword.fetch!(opts, :script)
    env = Keyword.get(opts, :env)
    cd = Keyword.get(opts, :cd)
    name = Keyword.fetch!(opts, :name)

    state = %__MODULE__{
      python: python,
      script: script,
      env: env && Enum.map(env, fn {k, v} -> {to_charlist(k), to_charlist(v)} end),
      cd: cd && to_charlist(cd),
      name: name
    }

    case open_port(state) do
      {:ok, port} ->
        PyBridge.Telemetry.worker_started(name)
        {:ok, %{state | port: port}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:call, method, params, timeout}, from, state) do
    {encoded, id} = Protocol.encode_request(method, params, state.next_id)

    PyBridge.Telemetry.call_start(state.name, method)

    case send_to_port(state.port, encoded) do
      :ok ->
        timer_ref = Process.send_after(self(), {:timeout, id}, timeout)

        pending = Map.put(state.pending, id, {:call, from, method, System.monotonic_time()})
        timers = Map.put(state.timers, id, timer_ref)

        {:noreply, %{state | next_id: state.next_id + 1, pending: pending, timers: timers}}

      {:error, reason} ->
        PyBridge.Telemetry.call_error(state.name, method, reason)
        {:reply, {:error, {:port_send_failed, reason}}, state}
    end
  end

  def handle_call({:batch_call, calls, timeout}, from, state) do
    {encoded_list, ids, state} =
      Enum.reduce(calls, {[], [], state}, fn call, {enc_acc, id_acc, st} ->
        {method, params} = normalize_batch_call(call)
        {encoded, id} = Protocol.encode_request(method, params, st.next_id)
        {[encoded | enc_acc], [id | id_acc], %{st | next_id: st.next_id + 1}}
      end)

    encoded_list = Enum.reverse(encoded_list)
    ids = Enum.reverse(ids)
    batch_data = Enum.join(encoded_list)

    case send_to_port(state.port, batch_data) do
      :ok ->
        timer_ref = Process.send_after(self(), {:batch_timeout, ids}, timeout)

        pending =
          Enum.reduce(ids, state.pending, fn id, acc ->
            Map.put(acc, id, {:batch, from, ids, System.monotonic_time()})
          end)

        timers =
          Enum.reduce(ids, state.timers, fn id, acc ->
            Map.put(acc, id, timer_ref)
          end)

        {:noreply, %{state | pending: pending, timers: timers}}

      {:error, reason} ->
        {:reply, {:error, {:port_send_failed, reason}}, state}
    end
  end

  @impl true
  def handle_cast({:async_call, ref, caller, method, params, timeout}, state) do
    {encoded, id} = Protocol.encode_request(method, params, state.next_id)

    PyBridge.Telemetry.call_start(state.name, method)

    case send_to_port(state.port, encoded) do
      :ok ->
        timer_ref = Process.send_after(self(), {:timeout, id}, timeout)

        pending =
          Map.put(state.pending, id, {:async, caller, ref, method, System.monotonic_time()})

        timers = Map.put(state.timers, id, timer_ref)

        {:noreply, %{state | next_id: state.next_id + 1, pending: pending, timers: timers}}

      {:error, _reason} ->
        send(caller, {:py_bridge_result, ref, {:error, :port_send_failed}})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    buffer = state.buffer <> IO.iodata_to_binary(data)
    {responses, remaining} = Protocol.decode_buffer(buffer)

    state = %{state | buffer: remaining}
    state = Enum.reduce(responses, state, &handle_response/2)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("[PyBridge] Python process #{state.name} exited with status #{status}")
    PyBridge.Telemetry.worker_crashed(state.name, status)

    # Fail all pending requests
    state = fail_all_pending(state, {:python_exited, status})

    {:stop, {:python_exited, status}, %{state | port: nil}}
  end

  def handle_info({:timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {{:call, from, method, _start_time}, pending} ->
        PyBridge.Telemetry.call_error(state.name, method, :timeout)
        GenServer.reply(from, {:error, :timeout})
        timers = Map.delete(state.timers, id)
        {:noreply, %{state | pending: pending, timers: timers}}

      {{:async, caller, ref, method, _start_time}, pending} ->
        PyBridge.Telemetry.call_error(state.name, method, :timeout)
        send(caller, {:py_bridge_result, ref, {:error, :timeout}})
        timers = Map.delete(state.timers, id)
        {:noreply, %{state | pending: pending, timers: timers}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:batch_timeout, ids}, state) do
    # Find the batch's caller (all ids share the same `from`)
    batch_from =
      Enum.find_value(ids, fn id ->
        case Map.get(state.pending, id) do
          {:batch, from, _ids, _start} -> from
          _ -> nil
        end
      end)

    # Clean up all pending entries for this batch
    state =
      Enum.reduce(ids, state, fn id, acc ->
        pending = Map.delete(acc.pending, id)
        # Also clean up any partial batch results
        pending = Map.delete(pending, {:batch_result, id})
        timers = Map.delete(acc.timers, id)
        %{acc | pending: pending, timers: timers}
      end)

    # Reply with timeout error
    if batch_from, do: GenServer.reply(batch_from, {:error, :timeout})

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{port: port} = _state) when not is_nil(port) do
    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  # --- Private ---

  defp open_port(state) do
    # NOTE: Do NOT use {:line, N} here. Line mode wraps data in {:eol, _} /
    # {:noeol, _} tuples that won't match our handle_info pattern. We handle
    # newline-delimited buffering ourselves in Protocol.decode_buffer/1.
    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      args: [state.script]
    ]

    port_opts =
      if state.env, do: [{:env, state.env} | port_opts], else: port_opts

    port_opts =
      if state.cd, do: [{:cd, state.cd} | port_opts], else: port_opts

    try do
      port = Port.open({:spawn_executable, System.find_executable(state.python)}, port_opts)
      {:ok, port}
    rescue
      e -> {:error, e}
    end
  end

  defp send_to_port(port, data) when is_port(port) do
    try do
      Port.command(port, data)
      :ok
    rescue
      ArgumentError -> {:error, :port_closed}
    end
  end

  defp send_to_port(nil, _data), do: {:error, :port_not_open}

  defp handle_response({:ok, id, result}, state) do
    case Map.pop(state.pending, id) do
      {{:call, from, method, start_time}, pending} ->
        cancel_timer(state.timers, id)
        duration = System.monotonic_time() - start_time
        PyBridge.Telemetry.call_stop(state.name, method, duration)
        GenServer.reply(from, {:ok, result})
        %{state | pending: pending, timers: Map.delete(state.timers, id)}

      {{:async, caller, ref, method, start_time}, pending} ->
        cancel_timer(state.timers, id)
        duration = System.monotonic_time() - start_time
        PyBridge.Telemetry.call_stop(state.name, method, duration)
        send(caller, {:py_bridge_result, ref, {:ok, result}})
        %{state | pending: pending, timers: Map.delete(state.timers, id)}

      {{:batch, from, batch_ids, _start_time}, pending} ->
        cancel_timer(state.timers, id)
        pending = Map.put(pending, {:batch_result, id}, {:ok, result})
        state = %{state | pending: pending, timers: Map.delete(state.timers, id)}
        maybe_complete_batch(state, from, batch_ids)

      {nil, _} ->
        state
    end
  end

  defp handle_response({:error, id, error}, state) do
    case Map.pop(state.pending, id) do
      {{:call, from, method, _start_time}, pending} ->
        cancel_timer(state.timers, id)
        PyBridge.Telemetry.call_error(state.name, method, error)
        GenServer.reply(from, {:error, error})
        %{state | pending: pending, timers: Map.delete(state.timers, id)}

      {{:async, caller, ref, method, _start_time}, pending} ->
        cancel_timer(state.timers, id)
        PyBridge.Telemetry.call_error(state.name, method, error)
        send(caller, {:py_bridge_result, ref, {:error, error}})
        %{state | pending: pending, timers: Map.delete(state.timers, id)}

      {{:batch, from, batch_ids, _start_time}, pending} ->
        cancel_timer(state.timers, id)
        pending = Map.put(pending, {:batch_result, id}, {:error, error})
        state = %{state | pending: pending, timers: Map.delete(state.timers, id)}
        maybe_complete_batch(state, from, batch_ids)

      {nil, _} ->
        state
    end
  end

  defp handle_response({:invalid, raw}, state) do
    Logger.warning("[PyBridge] Invalid response from #{state.name}: #{inspect(raw)}")
    state
  end

  defp maybe_complete_batch(state, from, batch_ids) do
    results =
      Enum.map(batch_ids, fn id ->
        Map.get(state.pending, {:batch_result, id})
      end)

    if Enum.all?(results, &(not is_nil(&1))) do
      # All results collected — reply
      pending =
        Enum.reduce(batch_ids, state.pending, fn id, acc ->
          Map.delete(acc, {:batch_result, id})
        end)

      GenServer.reply(from, results)
      %{state | pending: pending}
    else
      state
    end
  end

  defp fail_all_pending(state, reason) do
    Enum.reduce(state.pending, state, fn
      {_id, {:call, from, _method, _start}}, acc ->
        GenServer.reply(from, {:error, reason})
        acc

      {_id, {:async, caller, ref, _method, _start}}, acc ->
        send(caller, {:py_bridge_result, ref, {:error, reason}})
        acc

      _, acc ->
        acc
    end)
    |> Map.put(:pending, %{})
    |> Map.put(:timers, %{})
  end

  defp cancel_timer(timers, id) do
    case Map.get(timers, id) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end
  end

  defp normalize_batch_call({method, params}), do: {method, params}
  defp normalize_batch_call({method, params, _timeout}), do: {method, params}
end
