"""JSON-RPC 2.0 stdin/stdout worker for Elixir PyBridge.

Provides the @register decorator and run() loop that PyBridge.Worker
communicates with over newline-delimited JSON.
"""

from __future__ import annotations

import json
import signal
import sys
import traceback
from typing import Any, Callable


class WorkerRegistry:
    """Registry for Python functions callable from Elixir via JSON-RPC."""

    def __init__(self) -> None:
        self._methods: dict[str, Callable[..., Any]] = {}

    def register(self, fn: Callable[..., Any]) -> Callable[..., Any]:
        """Decorator to register a function as a JSON-RPC method.

        Usage::

            from py_bridge import worker

            @worker.register
            def predict(features: list) -> dict:
                return {"prediction": 0.85}
        """
        self._methods[fn.__name__] = fn
        return fn

    def register_method(self, name: str, fn: Callable[..., Any]) -> None:
        """Register a function under a custom method name."""
        self._methods[name] = fn

    def run(self) -> None:
        """Start the JSON-RPC stdin/stdout event loop.

        Reads newline-delimited JSON-RPC 2.0 requests from stdin and
        writes responses to stdout. Runs until stdin is closed (i.e.
        the Elixir Port closes the pipe).
        """
        # Ignore SIGPIPE so we don't crash with BrokenPipeError when
        # the Elixir side closes the Port before we finish writing.
        if hasattr(signal, "SIGPIPE"):
            signal.signal(signal.SIGPIPE, signal.SIG_DFL)

        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            response = self._handle_request(line)
            if response is not None:
                try:
                    sys.stdout.write(json.dumps(response) + "\n")
                    sys.stdout.flush()
                except BrokenPipeError:
                    break

    def _handle_request(self, line: str) -> dict[str, Any] | None:
        """Parse and dispatch a single JSON-RPC request."""
        try:
            request = json.loads(line)
        except json.JSONDecodeError as e:
            return {
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32700,
                    "message": "Parse error",
                    "data": str(e),
                },
            }

        req_id = request.get("id")
        method = request.get("method")
        params = request.get("params", {})

        # Validate request
        if not method:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32600,
                    "message": "Invalid Request",
                    "data": "Missing 'method' field",
                },
            }

        # Look up method
        fn = self._methods.get(method)
        if fn is None:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32601,
                    "message": "Method not found",
                    "data": f"No method named '{method}' is registered",
                },
            }

        # Execute
        try:
            if isinstance(params, dict):
                result = fn(**params)
            elif isinstance(params, list):
                result = fn(*params)
            else:
                result = fn(params)

            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": result,
            }
        except Exception as e:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32000,
                    "message": str(e),
                    "data": traceback.format_exc(),
                },
            }
