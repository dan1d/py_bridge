# `PyBridge`
[🔗](https://github.com/dan1d/py_bridge/blob/main/lib/py_bridge.ex#L1)

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

# `async_call`

```elixir
@spec async_call(GenServer.server(), String.t(), map() | list(), keyword()) ::
  reference()
```

Call a Python function asynchronously.

Returns a reference. The result will be sent to the calling process as:

    {:py_bridge_result, ref, {:ok, result} | {:error, reason}}

# `batch_call`

```elixir
@spec batch_call(GenServer.server(), list(), keyword()) :: [ok: any(), error: any()]
```

Send a batch of calls and collect results.

Each call is a tuple `{method, params}` or `{method, params, timeout}`.
Returns a list of `{:ok, result}` or `{:error, reason}` in the same order.

# `call`

```elixir
@spec call(GenServer.server(), String.t(), map() | list(), keyword()) ::
  {:ok, any()} | {:error, any()}
```

Call a Python function synchronously.

## Parameters

  * `worker` - registered name or pid of the `PyBridge.Worker`
  * `method` - Python function name (must be registered with `@worker.register`)
  * `params` - map or list of parameters to pass
  * `opts` - keyword list with optional `:timeout` (default 30000ms)

## Returns

  * `{:ok, result}` on success
  * `{:error, reason}` on failure

---

*Consult [api-reference.md](api-reference.md) for complete listing*
