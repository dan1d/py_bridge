# `PyBridge.Worker`
[🔗](https://github.com/dan1d/py_bridge/blob/main/lib/py_bridge/worker.ex#L1)

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

# `t`

```elixir
@type t() :: %PyBridge.Worker{
  buffer: binary(),
  cd: charlist() | nil,
  env: [{charlist(), charlist()}] | nil,
  name: atom(),
  next_id: integer(),
  pending: map(),
  port: port() | nil,
  python: String.t(),
  script: String.t(),
  timers: map()
}
```

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
