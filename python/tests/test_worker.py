"""Tests for the py_bridge.worker module."""

import json
import io
import sys
import unittest
from unittest.mock import patch

# Add parent to path so we can import py_bridge
sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent.parent))

from py_bridge.worker import WorkerRegistry


class TestWorkerRegistry(unittest.TestCase):
    """Tests for WorkerRegistry registration and dispatch."""

    def setUp(self):
        self.registry = WorkerRegistry()

    def test_register_decorator(self):
        @self.registry.register
        def hello(name="world"):
            return {"greeting": f"hello {name}"}

        assert "hello" in self.registry._methods
        assert self.registry._methods["hello"]("test") == {"greeting": "hello test"}

    def test_register_method_custom_name(self):
        def my_func(x):
            return x * 2

        self.registry.register_method("double", my_func)
        assert "double" in self.registry._methods
        assert self.registry._methods["double"](5) == 10

    def test_register_preserves_function(self):
        @self.registry.register
        def original():
            return "original"

        # Decorator returns the original function
        assert original() == "original"


class TestRequestHandling(unittest.TestCase):
    """Tests for JSON-RPC request parsing and dispatch."""

    def setUp(self):
        self.registry = WorkerRegistry()

        @self.registry.register
        def add(a=0, b=0):
            return {"sum": a + b}

        @self.registry.register
        def echo(message=""):
            return {"echo": message}

        @self.registry.register
        def fail():
            raise ValueError("intentional error")

        @self.registry.register
        def list_add(*args):
            return {"sum": sum(args)}

    def test_successful_dict_params(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "add", "params": {"a": 3, "b": 4}})
        resp = self.registry._handle_request(req)
        assert resp["id"] == 1
        assert resp["result"] == {"sum": 7}
        assert "error" not in resp

    def test_successful_list_params(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "list_add", "params": [1, 2, 3]})
        resp = self.registry._handle_request(req)
        assert resp["result"] == {"sum": 6}

    def test_default_params(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 3, "method": "add", "params": {}})
        resp = self.registry._handle_request(req)
        assert resp["result"] == {"sum": 0}

    def test_missing_params_uses_empty(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 4, "method": "echo"})
        resp = self.registry._handle_request(req)
        assert resp["result"] == {"echo": ""}

    def test_method_not_found(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 5, "method": "nonexistent", "params": {}})
        resp = self.registry._handle_request(req)
        assert resp["error"]["code"] == -32601
        assert "nonexistent" in resp["error"]["data"]

    def test_missing_method_field(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 6, "params": {}})
        resp = self.registry._handle_request(req)
        assert resp["error"]["code"] == -32600

    def test_parse_error(self):
        resp = self.registry._handle_request("not json {{{")
        assert resp["error"]["code"] == -32700
        assert resp["id"] is None

    def test_exception_returns_error(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 7, "method": "fail", "params": {}})
        resp = self.registry._handle_request(req)
        assert resp["error"]["code"] == -32000
        assert "intentional error" in resp["error"]["message"]
        assert "Traceback" in resp["error"]["data"]

    def test_response_has_jsonrpc_field(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 8, "method": "add", "params": {"a": 1, "b": 2}})
        resp = self.registry._handle_request(req)
        assert resp["jsonrpc"] == "2.0"

    def test_id_preserved(self):
        for test_id in [1, 42, 999]:
            req = json.dumps({"jsonrpc": "2.0", "id": test_id, "method": "add", "params": {"a": 0, "b": 0}})
            resp = self.registry._handle_request(req)
            assert resp["id"] == test_id

    def test_unicode_params(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 10, "method": "echo", "params": {"message": "Hello 世界 🌍"}})
        resp = self.registry._handle_request(req)
        assert resp["result"]["echo"] == "Hello 世界 🌍"

    def test_null_param_value(self):
        req = json.dumps({"jsonrpc": "2.0", "id": 11, "method": "echo", "params": {"message": None}})
        resp = self.registry._handle_request(req)
        assert resp["result"]["echo"] is None


class TestRunLoop(unittest.TestCase):
    """Tests for the stdin/stdout run loop."""

    def test_run_processes_multiple_requests(self):
        registry = WorkerRegistry()

        @registry.register
        def add(a=0, b=0):
            return {"sum": a + b}

        requests = (
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "add", "params": {"a": 1, "b": 2}}) + "\n"
            + json.dumps({"jsonrpc": "2.0", "id": 2, "method": "add", "params": {"a": 10, "b": 20}}) + "\n"
        )

        fake_stdin = io.StringIO(requests)
        fake_stdout = io.StringIO()

        with patch.object(sys, "stdin", fake_stdin), patch.object(sys, "stdout", fake_stdout):
            registry.run()

        output = fake_stdout.getvalue()
        lines = [l for l in output.strip().split("\n") if l]
        assert len(lines) == 2

        resp1 = json.loads(lines[0])
        resp2 = json.loads(lines[1])
        assert resp1["result"] == {"sum": 3}
        assert resp2["result"] == {"sum": 30}

    def test_run_skips_blank_lines(self):
        registry = WorkerRegistry()

        @registry.register
        def ping():
            return "pong"

        requests = (
            "\n\n"
            + json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping", "params": {}}) + "\n"
            + "\n"
        )

        fake_stdin = io.StringIO(requests)
        fake_stdout = io.StringIO()

        with patch.object(sys, "stdin", fake_stdin), patch.object(sys, "stdout", fake_stdout):
            registry.run()

        output = fake_stdout.getvalue()
        lines = [l for l in output.strip().split("\n") if l]
        assert len(lines) == 1
        assert json.loads(lines[0])["result"] == "pong"


if __name__ == "__main__":
    unittest.main()
