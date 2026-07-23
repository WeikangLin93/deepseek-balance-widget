# Changelog

## 0.1.1

- Add privacy-friendly anonymous launch counting via Hits.
- Document the opt-out environment variable for launch counting.

## 0.1.0

- Initial release: desktop floating widget for DeepSeek API balance.
- Displays total, granted, and topped-up balance in CNY.
- Auto-refreshes every 60 seconds in background.
- Adaptive light/dark theme following Windows system setting.
- Opacity adjustment (60%-100%), layer mode (always-on-top / normal).
- Game mode with auto full-screen detection and manual override.
- Network fallback to local cache on API failure.
- Reads API key from `~/.deepseek/config.toml` automatically.
- Stores runtime config and cache under `%LOCALAPPDATA%\DeepSeekBalanceWidget`.
