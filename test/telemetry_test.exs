defmodule PyBridge.TelemetryTest do
  use ExUnit.Case

  @echo_script Path.expand("support/echo_worker.py", __DIR__)

  setup do
    name = :"telemetry_test_#{:erlang.unique_integer([:positive])}"

    # Attach telemetry handlers before starting worker
    test_pid = self()

    :telemetry.attach_many(
      "test-#{name}",
      [
        [:py_bridge, :call, :start],
        [:py_bridge, :call, :stop],
        [:py_bridge, :call, :error],
        [:py_bridge, :worker, :started],
        [:py_bridge, :worker, :crashed]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    {:ok, _pid} =
      PyBridge.Worker.start_link(
        name: name,
        python: "python3",
        script: @echo_script
      )

    Process.sleep(200)

    on_exit(fn -> :telemetry.detach("test-#{name}") end)

    %{worker: name}
  end

  test "emits worker:started on init", %{worker: worker} do
    assert_received {:telemetry_event, [:py_bridge, :worker, :started], %{system_time: _},
                     %{worker: ^worker}}
  end

  test "emits call:start and call:stop on successful call", %{worker: worker} do
    {:ok, _} = PyBridge.call(worker, "echo", %{message: "telemetry"})

    assert_received {:telemetry_event, [:py_bridge, :call, :start], %{system_time: _},
                     %{worker: ^worker, method: "echo"}}

    assert_received {:telemetry_event, [:py_bridge, :call, :stop], %{duration: duration},
                     %{worker: ^worker, method: "echo"}}

    assert is_integer(duration)
    assert duration > 0
  end

  test "emits call:error on Python exception", %{worker: worker} do
    {:error, _} = PyBridge.call(worker, "raise_error", %{message: "boom"})

    assert_received {:telemetry_event, [:py_bridge, :call, :start], _, %{method: "raise_error"}}
    assert_received {:telemetry_event, [:py_bridge, :call, :error], _, %{method: "raise_error", reason: _}}
  end

  test "emits call:error on timeout", %{worker: worker} do
    {:error, :timeout} =
      PyBridge.call(worker, "slow_operation", %{seconds: 10}, timeout: 100)

    assert_received {:telemetry_event, [:py_bridge, :call, :start], _, %{method: "slow_operation"}}
    assert_received {:telemetry_event, [:py_bridge, :call, :error], _, %{method: "slow_operation", reason: :timeout}}
  end

  test "emits call:start for async calls", %{worker: worker} do
    _ref = PyBridge.async_call(worker, "echo", %{message: "async"})

    assert_receive {:telemetry_event, [:py_bridge, :call, :start], _, %{method: "echo"}}, 1_000
  end
end
