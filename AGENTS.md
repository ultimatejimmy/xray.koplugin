# Local development

This checkout runs on Apple Silicon macOS. The user has authorized a native
development environment. Use `tools/dev.sh check` for full verification in place
of the Windows/WSL commands in `.agents/rules/GEMINI.md`. Use `tools/dev.sh run`
to sync and launch the isolated KOReader profile. See `DEVELOPMENT.md`.

Keep runtime data, credentials, dependencies, and generated artifacts in `.dev/`.
Do not configure API keys in tracked `xray_config.lua` files. Do not change plugin
behavior just to accommodate an existing failing test; report baseline failures.

Follow existing Lua style, add meaningful regression tests for feature changes,
and synchronize translations when translation keys change.
