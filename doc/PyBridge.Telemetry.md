# `PyBridge.Telemetry`
[🔗](https://github.com/dan1d/py_bridge/blob/main/lib/py_bridge/telemetry.ex#L1)

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

---

*Consult [api-reference.md](api-reference.md) for complete listing*
