# PyBridge

[![Hex.pm](https://img.shields.io/hexpm/v/py_bridge.svg)](https://hex.pm/packages/py_bridge)
[![CI](https://github.com/dan1d/py_bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/dan1d/py_bridge/actions/workflows/ci.yml)

Call Python functions from Elixir over stdin/stdout using JSON-RPC 2.0.

Zero native dependencies. Supervisor-friendly. Crash-resilient.

## Why?

| Feature | PyBridge | Erlport | Venomous | Pythonx |
|---|---|---|---|---|
| Protocol | JSON (human-readable) | Erlang ETF | Erlang ETF | In-process |
| Dependencies | Zero | C NIF | Erlport | CPython |
| GIL concern | No (separate process) | No | No | Yes |
| Crash isolation | Full (Port) | Full | Full | No |
| Debug Python | Yes (run standalone) | Hard | Hard | Medium |
| Python package | Yes (PyPI helper) | No | No | No |

## Installation

Add `py_bridge` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:py_bridge, "~> 0.1.0"}
  ]
end
```

Install the Python helper (optional — for the `@worker.register` decorator):

```bash
pip install py-bridge
```

## Quick Start

### Python side

```python
# workers/model.py
from py_bridge import worker

@worker.register
def predict(features: list) -> dict:
    import numpy as np
    model = load_model()
    return {"prediction": float(model.predict(np.array(features)))}

@worker.register
def add(a: int, b: int) -> dict:
    return {"sum": a + b}

if __name__ == "__main__":
    worker.run()
```

### Elixir side

```elixir
# In your supervision tree
children = [
  {PyBridge.Worker, name: :ml_model, python: "python3", script: "workers/model.py"}
]
Supervisor.start_link(children, strategy: :one_for_one)

# Synchronous call (30s default timeout)
{:ok, %{"prediction" => 0.85}} =
  PyBridge.call(:ml_model, "predict", %{features: [1.0, 2.0, 3.0]})

# Custom timeout
{:ok, %{"sum" => 42}} =
  PyBridge.call(:ml_model, "add", %{a: 17, b: 25}, timeout: 5_000)

# Async call — result delivered as a message
ref = PyBridge.async_call(:ml_model, "predict", %{features: [1.0, 2.0, 3.0]})
receive do
  {:py_bridge_result, ^ref, {:ok, result}} -> result
end

# Batch call — send multiple requests, collect all results
results = PyBridge.batch_call(:ml_model, [
  {"add", %{a: 1, b: 2}},
  {"add", %{a: 3, b: 4}}
])
# => [{:ok, %{"sum" => 3}}, {:ok, %{"sum" => 7}}]
```

## Worker Options

```elixir
{PyBridge.Worker,
  name: :my_worker,           # Required. Registered process name.
  python: "python3",          # Python executable (default: "python3")
  script: "path/to/worker.py", # Required. Path to the Python script.
  env: [{"MY_VAR", "value"}], # Optional environment variables
  cd: "/working/dir"          # Optional working directory
}
```

## Worker Pool

For CPU-bound Python workloads, use `PyBridge.Pool` (requires `nimble_pool`):

```elixir
# mix.exs — add nimble_pool
{:nimble_pool, "~> 1.0"}

# Supervision tree
{PyBridge.Pool,
  name: :model_pool,
  size: 4,
  python: "python3",
  script: "workers/model.py"}

# Usage — automatically checks out a worker from the pool
{:ok, result} = PyBridge.Pool.call(:model_pool, "predict", %{x: 1.0})
```

## Error Handling

```elixir
# Python exceptions are returned as errors
{:error, %{"code" => -32000, "message" => "ValueError: ..."}} =
  PyBridge.call(:worker, "bad_function", %{})

# Unknown methods
{:error, %{"code" => -32601, "message" => "Method not found"}} =
  PyBridge.call(:worker, "nonexistent", %{})

# Timeout
{:error, :timeout} =
  PyBridge.call(:worker, "slow_function", %{}, timeout: 100)
```

## Telemetry Events

PyBridge emits telemetry events for observability:

| Event | Measurements | Metadata |
|---|---|---|
| `[:py_bridge, :call, :start]` | `system_time` | `worker`, `method` |
| `[:py_bridge, :call, :stop]` | `duration` | `worker`, `method` |
| `[:py_bridge, :call, :error]` | `system_time` | `worker`, `method`, `reason` |
| `[:py_bridge, :worker, :started]` | `system_time` | `worker` |
| `[:py_bridge, :worker, :crashed]` | `system_time` | `worker`, `exit_status` |

## How It Works

1. `PyBridge.Worker` starts a Python script as an Erlang Port (stdin/stdout pipe)
2. Calls are serialized as JSON-RPC 2.0 requests, one per line
3. Python reads from stdin, dispatches to registered functions, writes JSON responses to stdout
4. The GenServer matches responses to pending requests by their JSON-RPC `id`
5. If Python crashes, the GenServer terminates and the supervisor restarts it

## License

MIT
