# `PyBridge.Pool`
[🔗](https://github.com/dan1d/py_bridge/blob/main/lib/py_bridge/pool.ex#L1)

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

# `call`

Call a Python function using a worker from the pool.

# `child_spec`

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
