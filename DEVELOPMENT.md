# X-Ray development on macOS

This checkout contains the plugin source and a native KOReader development
environment for Apple Silicon. Dependencies, builds, books, tests, and reader
settings live in the Git-ignored `.dev/` directory.

## Quick start

From this checkout:

```sh
tools/dev.sh setup
tools/dev.sh check
tools/dev.sh run
```

`setup` installs missing Homebrew prerequisites, creates a Python virtual
environment and local Lua 5.1 rocks tree, and builds KOReader. The first build
downloads and compiles native dependencies and takes several minutes. Rerunning
it reuses dependencies and build output, preserving the reader profile. Set
`XRAY_BUILD_JOBS=8` to change the default of four concurrent build jobs.

The runtime is pinned to KOReader `v2026.07.1` (commit
`9192014d8bd82a91dc1012473be0f238dedfdb54`), following its
[macOS build instructions](https://github.com/koreader/koreader/blob/v2026.07.1/doc/Building.md).
The plugin starts at `03f338c31dac812a33997c4a58804e08a4a830f0` on
`main/local-dev`, with the original repository configured as `origin`.
Homebrew build tools are shared with your Mac; Python and Lua packages are local
to this checkout. Shell configuration files are not modified.

## Edit, check, restart

1. Edit files under `xray.koplugin/` and add relevant tests under `spec/`.
2. Run `tools/dev.sh check`, or `tools/dev.sh check spec/xray_units_spec.lua`
   while working on one spec. Both commands also check syntax and translations.
3. Quit the development KOReader window and rerun `tools/dev.sh run`.
   Each launch copies your current plugin source into the development profile.
   Lua modules reload on restart; this is not hot reload.

With no argument, `run` opens a generated sample EPUB with fictional characters.
To use your own book:

```sh
tools/dev.sh run '/absolute/path/to/book.epub'
```

Book sidecars may be written beside the book, so use a copy under `.dev/books/`
when experimenting with a personal book. The emulator opens at 600×800 pixels.
Tap near the top of a page to open KOReader's menu and find X-Ray under the tools
tab. Initial X-Ray welcome/setup dialogs can be dismissed without entering keys.
Keyboard shortcuts: Escape dismisses dialogs and F1 opens the reader menus.
The launcher also creates `.dev/X-Ray Reader.app` to give the emulator its own
macOS app identity; keep using `tools/dev.sh run` for the edit/restart workflow.

`tools/dev.sh sync` copies files without launching the reader. Sync preserves the
runtime `xray_config.lua` and generated data. It removes only stale files listed
in the previous source-sync manifest. The next launch restores source files if
the plugin's updater replaced them. Quit the reader before syncing changes.

## Tests and logs

`check` runs the existing Python syntax checker recursively across Lua source
directories, the translation checker, the development tooling's sync tests, and
Busted with LuaJIT. Each spec runs in
its own process to isolate mocks. Both spellings of the shared spec helper use
the same mock environment, and a real `dkjson` is required.

Each run stages a disposable copy in `.dev/test-runs/run-*`. Fixed `/tmp/` paths
in the staged specs are relocated inside that run. Source files and original
fixtures are not modified. These directories are retained for inspection and
can be deleted when no tests are running. Failures or spec-loading errors return
a nonzero exit status; no tests are silently skipped.

Runtime debug messages appear in the terminal. To keep a session log:

```sh
tools/dev.sh run > .dev/reader.log 2>&1
```

X-Ray's log is in `.dev/profile/plugins/xray.koplugin/xray.log`. Persistent
settings and data are under `.dev/profile/settings/xray/`, and KOReader's own
settings are in `.dev/profile/settings.reader.lua`.

## Configuration and feature entry points

No API key is required for mocked tests or opening the sample book. Configure
credentials through X-Ray's API Keys UI in the development reader, or edit
`.dev/profile/plugins/xray.koplugin/xray_config.lua`. Persistent configuration
backups also stay inside `.dev/profile/`. Never put credentials into the tracked
configuration files at the repository root or in the source plugin directory.
Live AI requests use your chosen provider and account.

| Area | Starting points inside `xray.koplugin/` |
| --- | --- |
| Lifecycle, menu registration | `main.lua` |
| Provider requests and settings | `xray_aihelper.lua`, `prompts/` |
| Fetching and chapter analysis | `xray_fetch.lua`, `xray_chapteranalyzer.lua` |
| Reader UI and entity lists | `xray_ui.lua`, `xray_entity_list.lua`, `xray_theme.lua` |
| Lookups, mentions, unit conversion | `xray_lookupmanager.lua`, `xray_mentions.lua`, `xray_units.lua` |
| Data and series caching | `xray_data.lua`, `xray_cachemanager.lua`, `xray_seriesmanager.lua` |
| Translations | `languages/en.po`, `localization_xray.lua` |

Specs generally follow the same module names. When translation keys change,
run `.dev/venv/bin/python tools/sync_translations.py` and review the resulting
translation changes before running the full check again.

Cloudflare Worker development and physical-device installation are separate
from this setup. A desktop emulator exercises the plugin UI but final
device-specific behavior should also be checked on your target reader.

## Verified baseline (2026-09-08)

- Native ARM64 runtime built and opened the generated EPUB with X-Ray loaded.
- All 419 plugin tests across 20 spec files passed; syntax and translation
  checks passed. Translation checks report existing untranslated-value warnings.
- Four sync regression tests passed, covering preserved configuration/data,
  stale source removal, and symlink protection.
- An intentionally failing temporary spec produced both an assertion failure
  and a missing-module error, and `check` returned exit status 1.
- A temporary plugin headline edit appeared in the running reader after sync
  and restart. The original source was then restored and synced back.
- Repeated setup completed successfully. No plugin or upstream fixture changes
  are needed for this environment.

The runtime logs existing warnings for the deprecated plugin `_meta.lua` name
and missing `menu_unit_scan` / `menu_unit_toggle` translations. They do not
prevent loading or testing the plugin.
