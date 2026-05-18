#!/usr/bin/env python3
"""Fetch DeepSeek API balance and output JSON for the desktop widget."""
import argparse
import json
import os
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BALANCE_URL = os.environ.get(
    "DEEPSEEK_BALANCE_URL",
    "https://api.deepseek.com/user/balance",
)
CONFIG_PATHS = [
    Path.home() / ".deepseek" / "config.toml",
]


def _app_data_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA")
    if base:
        root = Path(base)
    else:
        root = Path.home() / ".deepseek-balance-widget"
    path = root / "DeepSeekBalanceWidget"
    path.mkdir(parents=True, exist_ok=True)
    return path


_cache_override = os.environ.get("DEEPSEEK_BALANCE_CACHE_PATH")
CACHE_PATH = Path(_cache_override) if _cache_override else (_app_data_dir() / "last_balance.json")


class BalanceError(RuntimeError):
    def __init__(self, message: str, kind: str = "unknown"):
        super().__init__(message)
        self.kind = kind


def _load_api_key() -> str:
    """Read API key from DeepSeek TUI config or environment variable."""
    env_key = os.environ.get("DEEPSEEK_API_KEY")
    if env_key:
        return env_key

    for config_path in CONFIG_PATHS:
        if not config_path.exists():
            continue
        try:
            text = config_path.read_text(encoding="utf-8")
            in_deepseek_section = False
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith("#"):
                    continue
                if stripped == "[providers.deepseek]":
                    in_deepseek_section = True
                    continue
                if stripped.startswith("[") and stripped.endswith("]"):
                    in_deepseek_section = False
                    continue
                if in_deepseek_section and "=" in stripped:
                    key, _, val = stripped.partition("=")
                    if key.strip() == "api_key":
                        val = val.strip().strip('"').strip("'")
                        if val:
                            return val
        except Exception:
            pass

    # Fallback: top-level api_key
    for config_path in CONFIG_PATHS:
        if not config_path.exists():
            continue
        try:
            text = config_path.read_text(encoding="utf-8")
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith("api_key"):
                    _, _, val = stripped.partition("=")
                    val = val.strip().strip('"').strip("'")
                    if val:
                        return val
        except Exception:
            pass

    raise BalanceError(
        "未找到 DeepSeek API key。请在环境变量 DEEPSEEK_API_KEY 中设置，"
        "或确保 ~/.deepseek/config.toml 中存在 api_key。",
        "auth",
    )


def _atomic_json_write(path: Path, data: dict):
    import tempfile

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def _fetch_balance(api_key: str) -> dict:
    req = Request(
        BALANCE_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
        },
    )
    with urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def _build_result(raw: dict) -> dict:
    """Transform raw balance API response into widget-friendly format."""
    infos = raw.get("balance_infos", [])
    is_available = bool(raw.get("is_available", False))

    cny = {}
    for info in infos:
        if isinstance(info, dict) and info.get("currency") == "CNY":
            cny = info
            break

    total = float(cny.get("total_balance", 0) or 0)
    granted = float(cny.get("granted_balance", 0) or 0)
    topped_up = float(cny.get("topped_up_balance", 0) or 0)

    return {
        "ok": True,
        "from_cache": False,
        "error_kind": "",
        "ts": int(time.time()),
        "is_available": is_available,
        "total_balance": total,
        "granted_balance": granted,
        "topped_up_balance": topped_up,
        "currency": "CNY",
        "balance_infos": infos,
    }


def _load_cache():
    if CACHE_PATH.exists():
        try:
            return json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        except Exception:
            return None
    return None


def _save_cache(result: dict):
    _atomic_json_write(CACHE_PATH, result)


def _error_kind(error: Exception) -> str:
    if isinstance(error, BalanceError):
        return error.kind
    if isinstance(error, HTTPError):
        return "auth" if getattr(error, "code", None) in (401, 403) else "api"
    if isinstance(error, (URLError, TimeoutError)):
        return "network"
    if isinstance(error, json.JSONDecodeError):
        return "parse"
    if isinstance(error, OSError):
        return "filesystem"
    return "unknown"


def fetch_balance_result():
    api_key = _load_api_key()
    raw = _fetch_balance(api_key)
    result = _build_result(raw)
    _save_cache(result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description="Fetch DeepSeek balance and print JSON.")
    args = parser.parse_args(argv)

    try:
        result = fetch_balance_result()
        print(json.dumps(result, ensure_ascii=False))
    except (HTTPError, URLError, TimeoutError, BalanceError, OSError, json.JSONDecodeError) as e:
        kind = _error_kind(e)
        cache = _load_cache()
        if cache:
            cache["ok"] = False
            cache["error"] = str(e)
            cache["error_kind"] = kind
            cache["from_cache"] = True
            print(json.dumps(cache, ensure_ascii=False))
            return 0
        print(
            json.dumps(
                {"ok": False, "error": str(e), "error_kind": kind, "from_cache": False},
                ensure_ascii=False,
            )
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
