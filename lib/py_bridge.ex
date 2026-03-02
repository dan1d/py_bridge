defmodule PyBridge do
  @moduledoc """
  JSON-RPC 2.0 bridge for calling Python functions from Elixir over stdin/stdout Ports.

  ## Quick Start

      # Add a Python worker to your supervision tree
      children = [
        {PyBridge.Worker, name: :ml_model, python: "python3", script: "workers/model.py"}
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

      # Synchronous call with default 30s timeout
      {:ok, %{"prediction" => 0.85}} = PyBridge.call(:ml_model, "predict", %{features: [1, 2, 3]})

      # Call with custom timeout
      {:ok, result} = PyBridge.call(:ml_model, "train", %{epochs: 100}, timeout: 60_000)

      # Async call — result delivered as a message
      ref = PyBridge.async_call(:ml_model, "predict", %{features: [1, 2, 3]})
      receive do
        {:py_bridge_result, ^ref, result} -> result
      end
  """

  @default_timeout 30_000

  @doc """
  Call a Python function synchronously.

  ## Parameters

    * `worker` - registered name or pid of the `PyBridge.Worker`
    * `method` - Python function name (must be registered with `@worker.register`)
    * `params` - map or list of parameters to pass
    * `opts` - keyword list with optional `:timeout` (default #{@default_timeout}ms)

  ## Returns

    * `{:ok, result}` on success
    * `{:error, reason}` on failure
  """
  @spec call(GenServer.server(), String.t(), map() | list(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def call(worker, method, params \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(worker, {:call, method, params, timeout}, timeout + 1_000)
  end

  @doc """
  Call a Python function asynchronously.

  Returns a reference. The result will be sent to the calling process as:

      {:py_bridge_result, ref, {:ok, result} | {:error, reason}}
  """
  @spec async_call(GenServer.server(), String.t(), map() | list(), keyword()) :: reference()
  def async_call(worker, method, params \\ %{}, opts \\ []) do
    ref = make_ref()
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.cast(worker, {:async_call, ref, self(), method, params, timeout})
    ref
  end

  @doc """
  Send a batch of calls and collect results.

  Each call is a tuple `{method, params}` or `{method, params, timeout}`.
  Returns a list of `{:ok, result}` or `{:error, reason}` in the same order.
  """
  @spec batch_call(GenServer.server(), list(), keyword()) :: list({:ok, any()} | {:error, any()})
  def batch_call(worker, calls, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(worker, {:batch_call, calls, timeout}, timeout + 5_000)
  end
end
