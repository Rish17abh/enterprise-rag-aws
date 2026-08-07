"""Local unit tests for Phase 2 chunking helpers (no AWS required)."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "src" / "lambda_ingestion" / "pii_redactor.py"


def load_module():
    spec = importlib.util.spec_from_file_location("pii_redactor", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    # boto3 is imported at module level; provide a soft skip if missing
    try:
        spec.loader.exec_module(module)
    except ModuleNotFoundError as exc:
        raise unittest.SkipTest(f"Missing dependency: {exc}") from exc
    return module


class ChunkingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_overlap_chunks(self):
        tokens = [f"w{i}" for i in range(20)]
        text = " ".join(tokens)
        chunks = self.mod._chunk_text(text, chunk_size=10, overlap=2)
        self.assertEqual(chunks[0]["token_count"], 10)
        self.assertEqual(chunks[0]["text_chunk"].split()[0], "w0")
        self.assertEqual(chunks[1]["text_chunk"].split()[0], "w8")
        self.assertGreaterEqual(len(chunks), 2)

    def test_empty_text(self):
        self.assertEqual(self.mod._chunk_text("   ", 500, 50), [])

    def test_processed_key(self):
        key = self.mod._processed_key("uploads/hr/policy.pdf")
        self.assertTrue(key.startswith("processed/"))
        self.assertTrue(key.endswith("/chunks.json"))
        self.assertNotIn(".pdf", key)


if __name__ == "__main__":
    unittest.main()
