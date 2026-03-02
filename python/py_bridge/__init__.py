"""PyBridge: JSON-RPC 2.0 worker helper for Elixir Ports.

Usage:
    from py_bridge import worker

    @worker.register
    def predict(features: list) -> dict:
        return {"prediction": 0.85}

    if __name__ == "__main__":
        worker.run()
"""

from py_bridge.worker import WorkerRegistry

worker = WorkerRegistry()

__version__ = "0.1.0"
__all__ = ["worker"]
