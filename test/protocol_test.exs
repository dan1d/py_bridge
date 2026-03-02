defmodule PyBridge.ProtocolTest do
  use ExUnit.Case, async: true

  alias PyBridge.Protocol

  describe "encode_request/3" do
    test "encodes a valid JSON-RPC 2.0 request" do
      {encoded, id} = Protocol.encode_request("predict", %{x: 1.0}, 1)
      assert id == 1
      assert String.ends_with?(encoded, "\n")

      decoded = Jason.decode!(String.trim(encoded))
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "predict"
      assert decoded["params"] == %{"x" => 1.0}
      assert decoded["id"] == 1
    end

    test "encodes list params" do
      {encoded, _id} = Protocol.encode_request("add", [1, 2], 42)
      decoded = Jason.decode!(String.trim(encoded))
      assert decoded["params"] == [1, 2]
      assert decoded["id"] == 42
    end

    test "encodes empty params" do
      {encoded, _id} = Protocol.encode_request("ping", %{}, 1)
      decoded = Jason.decode!(String.trim(encoded))
      assert decoded["params"] == %{}
    end
  end

  describe "decode_response/1" do
    test "decodes a successful response" do
      json = ~s({"jsonrpc": "2.0", "id": 1, "result": {"prediction": 0.85}})
      assert {:ok, 1, %{"prediction" => 0.85}} = Protocol.decode_response(json)
    end

    test "decodes an error response" do
      json = ~s({"jsonrpc": "2.0", "id": 2, "error": {"code": -32601, "message": "Method not found"}})
      assert {:error, 2, %{"code" => -32601, "message" => "Method not found"}} =
               Protocol.decode_response(json)
    end

    test "handles response without jsonrpc field" do
      json = ~s({"id": 3, "result": "ok"})
      assert {:ok, 3, "ok"} = Protocol.decode_response(json)
    end

    test "returns :invalid for non-JSON" do
      assert {:invalid, "not json"} = Protocol.decode_response("not json")
    end

    test "returns :invalid for JSON without id or result" do
      assert {:invalid, ~s({"foo":"bar"})} = Protocol.decode_response(~s({"foo":"bar"}))
    end

    test "trims whitespace" do
      json = ~s(  {"jsonrpc": "2.0", "id": 1, "result": true}  \n)
      assert {:ok, 1, true} = Protocol.decode_response(json)
    end
  end

  describe "decode_buffer/1" do
    test "decodes multiple responses from a buffer" do
      buffer =
        ~s({"jsonrpc":"2.0","id":1,"result":"a"}\n{"jsonrpc":"2.0","id":2,"result":"b"}\n)

      {responses, remaining} = Protocol.decode_buffer(buffer)
      assert length(responses) == 2
      assert {:ok, 1, "a"} = Enum.at(responses, 0)
      assert {:ok, 2, "b"} = Enum.at(responses, 1)
      assert remaining == ""
    end

    test "handles incomplete trailing data" do
      buffer = ~s({"jsonrpc":"2.0","id":1,"result":"ok"}\n{"partial)

      {responses, remaining} = Protocol.decode_buffer(buffer)
      assert length(responses) == 1
      assert {:ok, 1, "ok"} = Enum.at(responses, 0)
      assert remaining == ~s({"partial)
    end

    test "handles empty buffer" do
      {responses, remaining} = Protocol.decode_buffer("")
      assert responses == []
      assert remaining == ""
    end

    test "handles buffer with only newlines" do
      {responses, remaining} = Protocol.decode_buffer("\n\n\n")
      assert responses == []
      assert remaining == ""
    end
  end
end
