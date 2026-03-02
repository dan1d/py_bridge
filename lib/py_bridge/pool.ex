defmodule PyBridge.Pool do
  @moduledoc """
  Optional pool of PyBridge workers using NimblePool.

  Requires `{:nimble_pool, "~> 1.0"}` as a dependency.

  ## Usage

      children = [
        {PyBridge.Pool,
         name: :quant_pool,
         size: 4,
         python: "python3",
         script: "workers/quant.py"}
      ]

      {:ok, result} = PyBridge.Pool.call(:quant_pool, "predict", %{x: 1.0})
  """

  @behaviour NimblePool

  require Logger

  # --- Public API ---

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :supervisor
    }
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    size = Keyword.get(opts, :size, 4)
    worker_opts = Keyword.take(opts, [:python, :script, :env, :cd])

    NimblePool.start_link(
      worker: {__MODULE__, worker_opts},
      pool_size: size,
      name: name
    )
  end

  @doc """
  Call a Python function using a worker from the pool.
  """
  def call(pool, method, params \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    NimblePool.checkout!(pool, :checkout, fn _from, worker_pid ->
      result = PyBridge.call(worker_pid, method, params, timeout: timeout)
      {result, worker_pid}
    end, timeout + 1_000)
  end

  # --- NimblePool callbacks ---

  @impl NimblePool
  def init_worker(opts) do
    python = Keyword.get(opts, :python, "python3")
    script = Keyword.fetch!(opts, :script)
    name = :"py_bridge_pool_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      PyBridge.Worker.start_link(
        name: name,
        python: python,
        script: script,
        env: Keyword.get(opts, :env),
        cd: Keyword.get(opts, :cd)
      )

    {:ok, pid, opts}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, worker_pid, pool_state) do
    {:ok, worker_pid, worker_pid, pool_state}
  end

  @impl NimblePool
  def handle_checkin(worker_pid, _from, _old_worker_pid, pool_state) do
    {:ok, worker_pid, pool_state}
  end

  @impl NimblePool
  def terminate_worker(_reason, worker_pid, pool_state) do
    if Process.alive?(worker_pid) do
      GenServer.stop(worker_pid, :normal)
    end

    {:ok, pool_state}
  end
end
