---
trigger: always_on
---

# KOReader X-Ray Plugin: Modular Architecture & File Ownership Rules

To keep the plugin maintainable and fast on low-memory e-ink devices (Kindle Paperwhite 1, 256MB RAM), **never append new feature subsystems directly into `main.lua` or `xray_ui.lua`**. Every feature belongs in its designated domain module.

---

## 1. Module Ownership & Routing Table

Before adding or modifying functions, route changes to the owning module:

| Module (`xray.koplugin/`) | Responsibility & Scope | What Does NOT Belong Here |
| :--- | :--- | :--- |
| `main.lua` | Plugin lifecycle hooks (`init`, `destroy`, `onReaderReady`, `onPageUpdate`, `onCloseDocument`, `onLowMemory`), event dispatchers, Horizon prefetch scheduler (`checkPrefetchHorizon`), and `safeRequireMixin` wiring. | Menu trees, style cards, anthology heuristics, book-type detection, or UI dialogs. |
| `xray_menu_builder.lua` | Top-level menu construction (`addToMainMenu`, `getSubMenuItems`, `getMenuCounts`). | Dialog implementations or data mutation logic. |
| `xray_style_cards.lua` | Visual customization cards (`showUnitStyleCard`, `showEntityStyleCard`, `showPopupFontSizeCard`), live preview widgets, and feature announcement cards. | Core entity detail views or scanner regex engines. |
| `xray_anthology.lua` | Anthology detection, story boundary resolution (`getCurrentStory`, `resolveEntityStory`), story presence tracking, and entity story tagging. | General chapter TOC parsing (belongs in `xray_chapteranalyzer.lua`). |
| `xray_booktype.lua` | Fiction/Non-Fiction/Manga heuristics (`detectBookTypeHeuristic`), AI book-type detection, and book-type override UI cards. | Entity extraction prompts or unit conversion rules. |
| `xray_ui.lua` | Core entity detail dialogs (`showCharacterDetails`, `showLocationDetails`, `showTermDetails`, `showTimelineEventDetails`, `showHistoricalFigureDetails`), settings pickers, and submodule aggregation via `safeRequireSubModule`. | Bottom footnote popup widget, onboarding/API key wizards, duplicate merge flows, series manager UI, image gallery/viewer UI, or log viewer. |
| `xray_bottom_popup.lua` | `XRayBottomPopup` footnote-style widget, `showBottomPopup`, `shouldUseBottomPopup`, and `calculatePopupFontMetrics`. | Fullscreen `ButtonDialog` detail cards. |
| `xray_horizon.lua` | Spoiler gating & progressive state resolution (`resolveEntityState`, `resolveDescriptionForPage`, `isPositionGateUnlocked`, `getUnlockedAliases`, `isEntityVisibleAtCurrentPosition`, `showPastEvolution`). | AI prompt generation or network fetching. |
| `xray_duplicates.lua` | Duplicate candidate detection (`buildDuplicateCandidates`), pair rejection persistence, and interactive merge dialogs (`showAIFindDuplicatesFlow`, `showMergeFlow`). | Low-level entity field merging (belongs in `xray_data.lua`). |
| `xray_onboarding.lua` | Welcome wizard (`showWelcomeCard`), API key entry/validation dialogs (`getAPIKeysMenu`), config guide, and AI model selection menus. | Cryptographic key storage (belongs in `xray_crypto.lua`) or QR relay servers (`xray_websetup.lua`). |
| `xray_series_ui.lua` | Series detection prompts (`checkSeriesContext`, `showSeriesContextPrompt`) and Manage Series dialog (`showManageSeriesDialog`). | Series cache persistence and sidecar metadata I/O (`xray_seriesmanager.lua`). |
| `xray_images_ui.lua` | Image launcher actions (`showImages`, `showImageActions`, `openImageViewer`, `jumpToImagePage`, `renameImageDialog`). | Gallery grid widget (`xray_image_gallery.lua`), viewer pan/zoom widget (`xray_image_viewer.lua`), or EPUB image extraction (`xray_imagemanager.lua`). |
| `xray_log_viewer.lua` | `XRayLogViewer` widget, `viewLog`, and `clearLogs`. | Logger buffering and file writing (`xray_logger.lua`). |
| `xray_entity_list.lua` | Paginated browsing overlays (`EntityListOverlay`) for Characters, Locations, Terms, Historical Figures, Timeline, and Story Arcs. | AI fetching or cache serialization. |
| `xray_fetch.lua` | AI fetch orchestration (`fetchFromAI`, `updateFromAI`, `fetchSingleWord`, `finalizeXRayData`, `mergeSequentialChapterDelta`, `queueSequentialChapterScan`). | HTTP/provider transport formatting (`xray_aihelper.lua`) or UI styling. |
| `xray_data.lua` | Pure data transformations: deduplication (`deduplicateByName`), merging (`mergeEntryItems`, `mergeEntityTemporalData`), sorting, timeline page assignment, and `saveCurrentBookCache`. | UI widgets or network requests. |
| `xray_entityscanner.lua` | Async/in-process book scanning for entity underlines, 3-page box resolution, and `EntityTooltip`. | Mention search list dialogs (`xray_mentions.lua`). |
| `xray_unitscanner.lua` | Async/in-process book scanning for measurement underlines, SVG wavy/circle tile caches, and `UnitTooltip`. | Pure unit conversion math and regex tables (`xray_units.lua`). |
| `xray_utils.lua` | Shared cross-cutting helpers (`getCurrentPage`, `sanitizeMetadata`, `getImageDimensions`, `utf8Lower`, `trimPunctuation`, `isLowMemory`, `isSilentNetworkAvailable`). | Feature-specific state. |

---

## 2. File Size & Decomposition Guardrails

1. **No Monolith Growth**:
   - Do not allow `main.lua` to exceed **2,000 lines** or `xray_ui.lua` to exceed **3,500 lines**.
   - Any new feature or dialog flow exceeding **~300 lines** must be created in its own `xray_<domain>.lua` module and mixed into `main.lua` (`safeRequireMixin`) or `xray_ui.lua` (`safeRequireSubModule`).
2. **Contract Test Registration**:
   - Whenever you add, move, or rename a public or mixin function on `XRayPlugin`, `xray_ui`, or any domain module, you **must** add it to `spec/xray_architecture_contract_spec.lua`.

---

## 3. KOReader Module & Require Conventions

1. **Dynamic `plugin_path` Resolution**:
   - Always resolve sibling modules at the top of every file in `xray.koplugin/` using:
     ```lua
     local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
     ```
   - Never use `debug.getinfo(1).source` to construct `require()` module names, as headless unit test runners load modules from varying working directories.
2. **Lazy UI Widget Requires**:
   - Optional KOReader widgets that are not preloaded in `spec/spec_helper.lua` (e.g., `ui/widget/inputdialog`, `ui/widget/multiinputdialog`, `ui/widget/pathchooser`) must be `require`d **locally inside the function** that instantiates them, not unconditionally at the top of a module.
3. **Static Scope Cleanliness (`Luacheck`)**:
   - Every file in `xray.koplugin/*.lua` must pass `luacheck xray.koplugin/*.lua --only 113` with **0 warnings and 0 errors** (no undeclared globals).
