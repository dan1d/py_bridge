# py-bridge

JSON-RPC 2.0 worker helper for [PyBridge](https://github.com/dan1d/py_bridge) Elixir Ports.

## Installation

```bash
pip install py-bridge
```

## Usage

```python
from py_bridge import worker

@worker.register
def predict(features: list[float]) -> dict:
    return {"prediction": sum(features) / len(features)}

@worker.register
def add(a: int, b: int) -> dict:
    return {"sum": a + b}

if __name__ == "__main__":
    worker.run()
```

This creates a Python script that communicates with an Elixir `PyBridge.Worker` GenServer over stdin/stdout using JSON-RPC 2.0.

## How It Works

- `@worker.register` exposes a function as a callable JSON-RPC method
- `worker.run()` starts the stdin/stdout event loop
- Requests and responses are newline-delimited JSON
- Exceptions are caught and returned as JSON-RPC error objects with tracebacks

## Elixir Side

```elixir
# Add py_bridge to your mix.exs deps, then:
{:ok, _} = PyBridge.Worker.start_link(
  name: :my_worker,
  python: "python3",
  script: "path/to/worker.py"
)

{:ok, %{"prediction" => 0.5}} =
  PyBridge.call(:my_worker, "predict", %{features: [1.0, 2.0, 3.0]})
```

See the [full documentation](https://github.com/dan1d/py_bridge) for more details.

## License

MIT
