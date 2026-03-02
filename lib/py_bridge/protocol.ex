defmodule PyBridge.Protocol do
  @moduledoc """
  JSON-RPC 2.0 encoding and decoding over newline-delimited JSON.

  Each message is a single JSON object terminated by a newline character.
  Request IDs are monotonically increasing integers managed by the caller.
  """

  @doc """
  Encode a JSON-RPC 2.0 request.

  Returns `{encoded_binary, request_id}`.
  """
  @spec encode_request(String.t(), map() | list(), integer()) :: {binary(), integer()}
  def encode_request(method, params, id) do
    request = %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }

    {Jason.encode!(request) <> "\n", id}
  end

  @doc """
  Decode a JSON-RPC 2.0 response from a line of text.

  Returns `{:ok, id, result}` or `{:error, id, error_info}` or `{:invalid, raw}`.
  """
  @spec decode_response(binary()) ::
          {:ok, integer(), any()}
          | {:error, integer(), map()}
          | {:invalid, binary()}
  def decode_response(line) do
    line = String.trim(line)

    case Jason.decode(line) do
      {:ok, %{"jsonrpc" => "2.0", "id" => id, "result" => result}} ->
        {:ok, id, result}

      {:ok, %{"jsonrpc" => "2.0", "id" => id, "error" => error}} ->
        {:error, id, error}

      {:ok, %{"id" => id, "result" => result}} ->
        {:ok, id, result}

      {:ok, %{"id" => id, "error" => error}} ->
        {:error, id, error}

      _ ->
        {:invalid, line}
    end
  end

  @doc """
  Decode a batch of newline-delimited JSON-RPC responses from a buffer.

  Returns `{decoded_responses, remaining_buffer}` where remaining_buffer
  is any incomplete trailing data.
  """
  @spec decode_buffer(binary()) :: {list(), binary()}
  def decode_buffer(buffer) do
    lines = String.split(buffer, "\n")
    {complete, [remaining]} = Enum.split(lines, -1)

    decoded =
      complete
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&decode_response/1)

    {decoded, remaining}
  end
end
