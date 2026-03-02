#!/usr/bin/env python3
"""Test echo worker for PyBridge tests.

Registers simple functions that echo back inputs, perform basic math,
or simulate errors — used by ExUnit integration tests.
"""

import sys
import os

# Add the py_bridge Python package to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "python"))

from py_bridge import worker


@worker.register
def echo(message="hello"):
    """Echo back the input."""
    return {"echo": message}


@worker.register
def add(a=0, b=0):
    """Add two numbers."""
    return {"sum": a + b}


@worker.register
def multiply(a=0, b=0):
    """Multiply two numbers."""
    return {"product": a * b}


@worker.register
def slow_operation(seconds=1):
    """Simulate a slow operation."""
    import time
    time.sleep(seconds)
    return {"status": "done", "slept": seconds}


@worker.register
def raise_error(message="test error"):
    """Raise an error for testing error handling."""
    raise ValueError(message)


@worker.register
def get_list(n=5):
    """Return a list of numbers."""
    return {"numbers": list(range(n))}


@worker.register
def nested_data():
    """Return nested data structure."""
    return {
        "users": [
            {"name": "Alice", "score": 95.5},
            {"name": "Bob", "score": 87.3},
        ],
        "metadata": {"version": 1, "complete": True},
    }


@worker.register
def identity(value=None):
    """Return the value as-is (tests various JSON types)."""
    return {"value": value}


@worker.register
def unicode_echo(text=""):
    """Echo unicode text."""
    return {"text": text, "length": len(text)}


@worker.register
def large_response(n=1000):
    """Return a large list."""
    return {"items": list(range(n))}


@worker.register
def no_return_value():
    """Function that returns None."""
    pass


@worker.register
def list_params(*args):
    """Accept positional args (list params in JSON-RPC)."""
    return {"args": list(args), "count": len(args)}


if __name__ == "__main__":
    worker.run()
