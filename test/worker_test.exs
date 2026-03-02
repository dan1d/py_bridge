defmodule PyBridge.WorkerTest do
  use ExUnit.Case

  @echo_script Path.expand("support/echo_worker.py", __DIR__)

  setup do
    name = :"test_worker_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      PyBridge.Worker.start_link(
        name: name,
        python: "python3",
        script: @echo_script
      )

    # Give the Python process a moment to start
    Process.sleep(200)

    %{worker: name, pid: pid}
  end

  # ---------------------------------------------------------------------------
  # Synchronous calls
  # ---------------------------------------------------------------------------

  describe "synchronous calls" do
    test "echo returns the input", %{worker: worker} do
      assert {:ok, %{"echo" => "hello world"}} =
               PyBridge.call(worker, "echo", %{message: "hello world"})
    end

    test "add returns the sum", %{worker: worker} do
      assert {:ok, %{"sum" => 42}} =
               PyBridge.call(worker, "add", %{a: 17, b: 25})
    end

    test "multiply returns the product", %{worker: worker} do
      assert {:ok, %{"product" => 30}} =
               PyBridge.call(worker, "multiply", %{a: 5, b: 6})
    end

    test "call with default params", %{worker: worker} do
      assert {:ok, %{"echo" => "hello"}} = PyBridge.call(worker, "echo", %{})
    end

    test "call with empty params map", %{worker: worker} do
      assert {:ok, %{"echo" => "hello"}} = PyBridge.call(worker, "echo")
    end

    test "nested data structures round-trip", %{worker: worker} do
      assert {:ok, %{"users" => users, "metadata" => meta}} =
               PyBridge.call(worker, "nested_data", %{})

      assert length(users) == 2
      assert meta["version"] == 1
      assert meta["complete"] == true
    end

    test "unknown method returns error", %{worker: worker} do
      assert {:error, %{"code" => -32601}} =
               PyBridge.call(worker, "nonexistent", %{})
    end

    test "Python exception returns error", %{worker: worker} do
      assert {:error, %{"code" => -32000, "message" => "test error"}} =
               PyBridge.call(worker, "raise_error", %{message: "test error"})
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "handles None/null return values", %{worker: worker} do
      assert {:ok, %{"value" => nil}} =
               PyBridge.call(worker, "identity", %{value: nil})
    end

    test "handles boolean values", %{worker: worker} do
      assert {:ok, %{"value" => true}} =
               PyBridge.call(worker, "identity", %{value: true})

      assert {:ok, %{"value" => false}} =
               PyBridge.call(worker, "identity", %{value: false})
    end

    test "handles integer values", %{worker: worker} do
      assert {:ok, %{"value" => 42}} =
               PyBridge.call(worker, "identity", %{value: 42})
    end

    test "handles float values", %{worker: worker} do
      assert {:ok, %{"value" => val}} =
               PyBridge.call(worker, "identity", %{value: 3.14159})

      assert_in_delta val, 3.14159, 0.0001
    end

    test "handles empty string", %{worker: worker} do
      assert {:ok, %{"value" => ""}} =
               PyBridge.call(worker, "identity", %{value: ""})
    end

    test "handles unicode text", %{worker: worker} do
      assert {:ok, %{"text" => "Hello 世界 🌍", "length" => _}} =
               PyBridge.call(worker, "unicode_echo", %{text: "Hello 世界 🌍"})
    end

    test "handles large responses", %{worker: worker} do
      assert {:ok, %{"items" => items}} =
               PyBridge.call(worker, "large_response", %{n: 5000})

      assert length(items) == 5000
      assert List.first(items) == 0
      assert List.last(items) == 4999
    end

    test "handles None return (Python function returns nothing)", %{worker: worker} do
      assert {:ok, nil} = PyBridge.call(worker, "no_return_value", %{})
    end

    test "handles list params", %{worker: worker} do
      assert {:ok, %{"args" => [1, 2, 3], "count" => 3}} =
               PyBridge.call(worker, "list_params", [1, 2, 3])
    end

    test "negative numbers round-trip", %{worker: worker} do
      assert {:ok, %{"sum" => -5}} =
               PyBridge.call(worker, "add", %{a: -10, b: 5})
    end

    test "zero values round-trip", %{worker: worker} do
      assert {:ok, %{"sum" => 0}} =
               PyBridge.call(worker, "add", %{a: 0, b: 0})
    end
  end

  # ---------------------------------------------------------------------------
  # Async calls
  # ---------------------------------------------------------------------------

  describe "async calls" do
    test "async_call delivers result via message", %{worker: worker} do
      ref = PyBridge.async_call(worker, "echo", %{message: "async"})

      assert_receive {:py_bridge_result, ^ref, {:ok, %{"echo" => "async"}}}, 5_000
    end

    test "async_call delivers error via message", %{worker: worker} do
      ref = PyBridge.async_call(worker, "raise_error", %{message: "async error"})

      assert_receive {:py_bridge_result, ^ref, {:error, %{"code" => -32000}}}, 5_000
    end

    test "multiple async calls return to correct refs", %{worker: worker} do
      ref1 = PyBridge.async_call(worker, "add", %{a: 1, b: 2})
      ref2 = PyBridge.async_call(worker, "add", %{a: 10, b: 20})
      ref3 = PyBridge.async_call(worker, "echo", %{message: "third"})

      assert_receive {:py_bridge_result, ^ref1, {:ok, %{"sum" => 3}}}, 5_000
      assert_receive {:py_bridge_result, ^ref2, {:ok, %{"sum" => 30}}}, 5_000
      assert_receive {:py_bridge_result, ^ref3, {:ok, %{"echo" => "third"}}}, 5_000
    end
  end

  # ---------------------------------------------------------------------------
  # Batch calls
  # ---------------------------------------------------------------------------

  describe "batch calls" do
    test "batch_call returns results in order", %{worker: worker} do
      results =
        PyBridge.batch_call(worker, [
          {"add", %{a: 1, b: 2}},
          {"add", %{a: 10, b: 20}},
          {"echo", %{message: "batch"}}
        ])

      assert [{:ok, %{"sum" => 3}}, {:ok, %{"sum" => 30}}, {:ok, %{"echo" => "batch"}}] =
               results
    end

    test "batch_call with single item", %{worker: worker} do
      results = PyBridge.batch_call(worker, [{"add", %{a: 5, b: 5}}])
      assert [{:ok, %{"sum" => 10}}] = results
    end

    test "batch_call with errors mixed in", %{worker: worker} do
      results =
        PyBridge.batch_call(worker, [
          {"add", %{a: 1, b: 1}},
          {"nonexistent", %{}},
          {"multiply", %{a: 3, b: 4}}
        ])

      assert {:ok, %{"sum" => 2}} = Enum.at(results, 0)
      assert {:error, %{"code" => -32601}} = Enum.at(results, 1)
      assert {:ok, %{"product" => 12}} = Enum.at(results, 2)
    end
  end

  # ---------------------------------------------------------------------------
  # Timeout
  # ---------------------------------------------------------------------------

  describe "timeout" do
    test "call times out for slow operations", %{worker: worker} do
      assert {:error, :timeout} =
               PyBridge.call(worker, "slow_operation", %{seconds: 5}, timeout: 500)
    end

    test "worker is still responsive after a timed-out call", %{worker: worker} do
      # Trigger a timeout
      PyBridge.call(worker, "slow_operation", %{seconds: 5}, timeout: 200)

      # Wait for the slow operation to actually complete in Python
      Process.sleep(300)

      # Should still work
      assert {:ok, %{"sum" => 7}} = PyBridge.call(worker, "add", %{a: 3, b: 4})
    end
  end

  # ---------------------------------------------------------------------------
  # Concurrent calls
  # ---------------------------------------------------------------------------

  describe "concurrent calls" do
    test "multiple concurrent calls resolve correctly", %{worker: worker} do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            PyBridge.call(worker, "add", %{a: i, b: i * 10})
          end)
        end

      results = Task.await_many(tasks, 10_000)

      for {result, i} <- Enum.with_index(results, 1) do
        assert {:ok, %{"sum" => sum}} = result
        assert sum == i + i * 10
      end
    end

    test "concurrent sync and async calls don't interfere", %{worker: worker} do
      # Fire off some async calls
      ref1 = PyBridge.async_call(worker, "echo", %{message: "async1"})
      ref2 = PyBridge.async_call(worker, "echo", %{message: "async2"})

      # Do a sync call in between
      assert {:ok, %{"sum" => 100}} = PyBridge.call(worker, "add", %{a: 50, b: 50})

      # Async results should still arrive
      assert_receive {:py_bridge_result, ^ref1, {:ok, %{"echo" => "async1"}}}, 5_000
      assert_receive {:py_bridge_result, ^ref2, {:ok, %{"echo" => "async2"}}}, 5_000
    end
  end

  # ---------------------------------------------------------------------------
  # Child spec and supervisor integration
  # ---------------------------------------------------------------------------

  describe "child_spec" do
    test "generates correct child spec" do
      spec = PyBridge.Worker.child_spec(name: :test_spec, script: "foo.py")

      assert spec.id == {PyBridge.Worker, :test_spec}
      assert spec.restart == :permanent
      assert spec.type == :worker
    end
  end

  describe "crash recovery" do
    test "worker process restarts after Python crash" do
      name = :"crash_test_#{:erlang.unique_integer([:positive])}"

      # Start under a supervisor
      children = [
        {PyBridge.Worker, name: name, python: "python3", script: @echo_script}
      ]

      {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.sleep(200)

      # Verify it works
      assert {:ok, %{"echo" => "before"}} =
               PyBridge.call(name, "echo", %{message: "before"})

      # Kill the GenServer (supervisor will restart it)
      pid = Process.whereis(name)
      Process.exit(pid, :kill)
      Process.sleep(500)

      # Should work again after restart
      assert {:ok, %{"echo" => "after"}} =
               PyBridge.call(name, "echo", %{message: "after"})

      Supervisor.stop(sup)
    end
  end

  # ---------------------------------------------------------------------------
  # Error on bad script path
  # ---------------------------------------------------------------------------

  describe "bad configuration" do
    test "worker dies when Python script doesn't exist" do
      name = :"bad_script_#{:erlang.unique_integer([:positive])}"

      # Trap exits so the linked GenServer crash doesn't kill us
      Process.flag(:trap_exit, true)

      {:ok, pid} =
        PyBridge.Worker.start_link(
          name: name,
          python: "python3",
          script: "/nonexistent/path/to/script.py"
        )

      # Python will start, fail to find the script, and exit.
      # The GenServer receives {:exit_status, N} and stops.
      assert_receive {:EXIT, ^pid, {:python_exited, _status}}, 3_000
      refute Process.alive?(pid)
    end
  end
end
