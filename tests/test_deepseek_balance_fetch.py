import importlib.util
import json
import os
import shutil
import unittest
from pathlib import Path


def load_module():
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location(
        "deepseek_balance_fetch", root / "deepseek_balance_fetch.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DeepSeekBalanceFetchTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[1]
        self.tmp_path = root / ".test_runtime"
        if self.tmp_path.exists():
            shutil.rmtree(self.tmp_path)
        self.tmp_path.mkdir()
        self.old_cache_path = os.environ.get("DEEPSEEK_BALANCE_CACHE_PATH")
        os.environ["DEEPSEEK_BALANCE_CACHE_PATH"] = str(
            self.tmp_path / "last_balance.json"
        )
        self.mod = load_module()

    def tearDown(self):
        if self.old_cache_path is None:
            os.environ.pop("DEEPSEEK_BALANCE_CACHE_PATH", None)
        else:
            os.environ["DEEPSEEK_BALANCE_CACHE_PATH"] = self.old_cache_path
        shutil.rmtree(self.tmp_path, ignore_errors=True)

    def test_build_result_parses_balance(self):
        raw = {
            "is_available": True,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "16.03",
                    "granted_balance": "5.00",
                    "topped_up_balance": "11.03",
                }
            ],
        }
        result = self.mod._build_result(raw)

        self.assertTrue(result["ok"])
        self.assertEqual(result["total_balance"], 16.03)
        self.assertEqual(result["granted_balance"], 5.00)
        self.assertEqual(result["topped_up_balance"], 11.03)
        self.assertEqual(result["currency"], "CNY")
        self.assertTrue(result["is_available"])

    def test_build_result_handles_missing_balance(self):
        raw = {"is_available": False, "balance_infos": []}
        result = self.mod._build_result(raw)

        self.assertTrue(result["ok"])
        self.assertEqual(result["total_balance"], 0.0)
        self.assertEqual(result["granted_balance"], 0.0)
        self.assertEqual(result["topped_up_balance"], 0.0)

    def test_atomic_json_write_round_trips(self):
        target = self.tmp_path / "nested" / "cache.json"
        self.mod._atomic_json_write(target, {"ok": True, "total_balance": 15.5})

        self.assertEqual(
            json.loads(target.read_text(encoding="utf-8")),
            {"ok": True, "total_balance": 15.5},
        )

    def test_error_kind_for_balance_error(self):
        self.assertEqual(
            self.mod._error_kind(self.mod.BalanceError("bad key", "auth")), "auth"
        )


if __name__ == "__main__":
    unittest.main()
