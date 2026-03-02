defmodule PyBridge.Telemetry do
  @moduledoc """
  Telemetry events emitted by PyBridge.

  ## Events

    * `[:py_bridge, :call, :start]` — emitted when a call is initiated
      - Measurements: `%{system_time: integer}`
      - Metadata: `%{worker: atom, method: String.t}`

    * `[:py_bridge, :call, :stop]` — emitted when a call completes successfully
      - Measurements: `%{duration: integer}` (native time units)
      - Metadata: `%{worker: atom, method: String.t}`

    * `[:py_bridge, :call, :error]` — emitted when a call fails
      - Measurements: `%{system_time: integer}`
      - Metadata: `%{worker: atom, method: String.t, reason: any}`

    * `[:py_bridge, :worker, :started]` — Python worker process started
      - Measurements: `%{system_time: integer}`
      - Metadata: `%{worker: atom}`

    * `[:py_bridge, :worker, :crashed]` — Python worker process crashed
      - Measurements: `%{system_time: integer}`
      - Metadata: `%{worker: atom, exit_status: integer}`
  """

  @doc false
  def call_start(worker, method) do
    :telemetry.execute(
      [:py_bridge, :call, :start],
      %{system_time: System.system_time()},
      %{worker: worker, method: method}
    )
  end

  @doc false
  def call_stop(worker, method, duration) do
    :telemetry.execute(
      [:py_bridge, :call, :stop],
      %{duration: duration},
      %{worker: worker, method: method}
    )
  end

  @doc false
  def call_error(worker, method, reason) do
    :telemetry.execute(
      [:py_bridge, :call, :error],
      %{system_time: System.system_time()},
      %{worker: worker, method: method, reason: reason}
    )
  end

  @doc false
  def worker_started(worker) do
    :telemetry.execute(
      [:py_bridge, :worker, :started],
      %{system_time: System.system_time()},
      %{worker: worker}
    )
  end

  @doc false
  def worker_crashed(worker, exit_status) do
    :telemetry.execute(
      [:py_bridge, :worker, :crashed],
      %{system_time: System.system_time()},
      %{worker: worker, exit_status: exit_status}
    )
  end
end
