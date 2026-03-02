# `PyBridge.Protocol`
[🔗](https://github.com/dan1d/py_bridge/blob/main/lib/py_bridge/protocol.ex#L1)

JSON-RPC 2.0 encoding and decoding over newline-delimited JSON.

Each message is a single JSON object terminated by a newline character.
Request IDs are monotonically increasing integers managed by the caller.

# `decode_buffer`

```elixir
@spec decode_buffer(binary()) :: {list(), binary()}
```

Decode a batch of newline-delimited JSON-RPC responses from a buffer.

Returns `{decoded_responses, remaining_buffer}` where remaining_buffer
is any incomplete trailing data.

# `decode_response`

```elixir
@spec decode_response(binary()) ::
  {:ok, integer(), any()} | {:error, integer(), map()} | {:invalid, binary()}
```

Decode a JSON-RPC 2.0 response from a line of text.

Returns `{:ok, id, result}` or `{:error, id, error_info}` or `{:invalid, raw}`.

# `encode_request`

```elixir
@spec encode_request(String.t(), map() | list(), integer()) :: {binary(), integer()}
```

Encode a JSON-RPC 2.0 request.

Returns `{encoded_binary, request_id}`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
