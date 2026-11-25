# External Data Format (`xray_cache.json`)

`xray.koplugin` can load book X-Ray data from a standard JSON file written by external connectors (such as `bookorbit.koplugin`, Calibre plugins, or custom scripts) without requiring server-specific code inside X-Ray.

---

## 1. Cache Location

Place the JSON file inside the book's standard KOReader sidecar directory (`.sdr`):

```text
<sidecar_dir>/xray_cache.json
```

In KOReader Lua plugins, resolve this path with:

```lua
local DocSettings = require("docsettings")
local json_path = DocSettings:getSidecarDir(book_path) .. "/xray_cache.json"
```

For example, for `/mnt/us/documents/Dune.epub`, the file path is `/mnt/us/documents/Dune.sdr/xray_cache.json`.

---

## 2. Schema Version & Precedence

### Schema Version
Include `"schema_version": "1.0"` at the top level. X-Ray validates this version before loading so future format changes will not silently break external writers.

### Precedence (`xray_cache.json` vs `xray_cache.lua`)
- X-Ray's native cache is `<sidecar_dir>/xray_cache.lua`. **X-Ray never writes to or modifies `xray_cache.json`.**
- When opening a book:
  - If only `xray_cache.json` exists → X-Ray loads `xray_cache.json`.
  - If only `xray_cache.lua` exists → X-Ray loads `xray_cache.lua`.
  - If **both** exist → X-Ray compares modification timestamps (`mtime`). If `xray_cache.json` is newer than `xray_cache.lua` (e.g. after an external connector syncs an updated guide), X-Ray loads `xray_cache.json`. Otherwise X-Ray loads `xray_cache.lua` (preserving local AI gap-fills or edits made since the last sync).
- If the user explicitly taps **Clear X-Ray Cache** in X-Ray's menu, both `xray_cache.lua` and `xray_cache.json` are removed.

---

## 3. Overwrite Protection & AI Gap-Filling

X-Ray supports two complementary protection controls:

### A. Per-Entry `"source": "external"` (AI Gap-Filling Safe)
- Every entry in `characters`, `locations`, `terms`, `historical_figures`, and `timeline` loaded from `xray_cache.json` is automatically tagged with `"source": "external"` if `source` is omitted (you may also set a custom non-`"ai"` identifier like `"bookorbit"`).
- During AI merges (`deduplicateByName`, `updateEntityDescPreservingPrior`, and sequential chapter deltas), X-Ray **preserves externally sourced entries** and will not overwrite their names, descriptions, roles, or states—while still allowing AI to **fill gaps** (adding new entities not present in the imported guide, or running targeted single-word lookups).

### B. Book-Level Overwrite Controls
- **`"prevent_overwrite": true`** (top-level, or inside `"external_source"`):
  - Disables silent background AI catch-up (`isCatchUpNeeded`) and Horizon prefetching (`checkPrefetchHorizon`) for this book so X-Ray does not spend AI tokens automatically.
  - When `"external_source"` is present as an object, `prevent_overwrite` defaults to `true` unless explicitly set to `false` (set `"prevent_overwrite": false` if you want X-Ray's background AI to fill gaps while keeping imported entries protected via `"source": "external"`).
- **`"read_only": true`** (top-level, or inside `"external_source"`):
  - Strict lock: blocks `CacheManager:saveCache()` / `asyncSaveCache()` from writing `xray_cache.lua` at all, in addition to suppressing background AI fetches.

---

## 4. Top-Level JSON Schema (`schema_version: "1.0"`)

| Field | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `schema_version` | `string` | Yes | Must be `"1.0"`. |
| `book_title` | `string` | No | Book title. |
| `author` | `string` | No | Author name. |
| `book_type` | `string` | No | `"fiction"`, `"non_fiction"`, or `"manga"`. |
| `prevent_overwrite` | `boolean` | No | Top-level shorthand to disable background AI auto-fetch & Horizon prefetch. |
| `read_only` | `boolean` | No | Top-level shorthand to block all local cache writes. |
| `external_source` | `object` | No | Connector metadata: `{ "name": "BookOrbit", "prevent_overwrite": true, "read_only": false, "synced_at": 1732100000, "etag": "\"abc\"" }`. |
| `last_fetch_page` | `number` | No | Highest page covered by the guide. |
| `chapters_fetched` | `object` | No | Map of `"<chapter_title>_<page>": true` marking chapters already covered. |
| `author_info` | `object` | No | `{ "name": "...", "description": "...", "birthDate": "...", "deathDate": "..." }`. |
| `characters` | `array` | No | List of character objects (see below). |
| `locations` | `array` | No | List of location objects. |
| `terms` | `array` | No | List of glossary/term objects. |
| `historical_figures` | `array` | No | List of real-world historical figure objects. |
| `timeline` | `array` | No | List of chapter/event summary objects. |

---

## 5. Position Anchors (Spoiler-Free Mode)

To keep X-Ray's **Spoiler-free mode** working on imported data, attach a position gate object to `visible_from`, `alias_visible_from[alias]`, `links[].visible_from`, and entries in `states[]`:

```json
{
  "chapter_index": 3,
  "chapter_title": "Chapter 3",
  "chapter_pct": 0.45,
  "page_hint": 65
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `chapter_index` | `number` | **1-based index** into KOReader's flattened TOC (`document:getToc()`). Fast and repagination-proof. |
| `chapter_pct` | `number` | Optional `0.0`–`1.0` progress within the chapter. Repagination-proof across font/margin changes. |
| `page_hint` (or `page`) | `number` | Optional 1-based page number hint within the chapter. |
| `ch_start_page` / `ch_end_page` | `number` | Optional chapter page bounds at the time `page_hint` was recorded (used to detect repagination). |
| `chapter_title` | `string` | Optional human-readable chapter label shown in Character Evolution / Story Arcs. |

- Entities without `visible_from` are treated as visible from the beginning of the book.
- When `states[]` is populated, X-Ray resolves the latest unlocked state at or before the reader's current position instead of showing future spoilers.

---

## 6. Entity & Timeline Schemas

### Character (`characters[]`)
| Field | Type | Description |
| :--- | :--- | :--- |
| `name` | `string` | **Required.** Canonical display name. |
| `aliases` | `string[]` | Alternate names, nicknames, or titles. |
| `alias_visible_from` | `object` | Optional map of **lowercased alias** → position gate object (hides spoiler aliases until reached). |
| `role` | `string` | Role in the story (e.g., `"Protagonist"`, `"Antagonist"`, `"Supporting"`). |
| `status` | `string` | Current status (e.g., `"alive"`, `"deceased"`, `"missing"`). |
| `occupation` | `string` | Optional occupation/title. |
| `gender` | `string` | Optional gender. |
| `description` | `string` | Base bio/summary. |
| `links` | `array` | Explicit references to related entities for **Linked Entries**. Each element may be a target name string (`"Paul Atreides"`) or an object (`{ "name": "Paul Atreides", "relation": "Son", "visible_from": { "chapter_index": 2 } }`). |
| `visible_from` | `object` | Position gate for when the character first appears. |
| `states` | `array` | Chronological state snapshots (`chapter_index`, `chapter_title`, `chapter_pct`, `page_hint`/`page`, `role`, `status`, `description`, `change`, `evidence`). |
| `source` | `string` | Defaults to `"external"` on JSON load. Protects the entry from AI overwrite. |
| `story_id` / `story_title` / `is_recurring` | `string` / `boolean` | Optional Anthology scoping fields. |

### Location (`locations[]`)
Same core fields as Character (`name`, `aliases`, `alias_visible_from`, `category`, `description`, `links`, `visible_from`, `states`, `source`, `story_id`, `story_title`).

### Term / Glossary (`terms[]`)
Same core fields (`name`, `aliases`, `category`, `definition`, `description`, `expansion`, `links`, `visible_from`, `states`, `source`, `story_id`, `story_title`).

### Historical Figure (`historical_figures[]`)
`name`, `aliases`, `role`, `era`, `description`, `links`, `source`.

### Timeline Event (`timeline[]`)
| Field | Type | Description |
| :--- | :--- | :--- |
| `chapter` | `string` | Chapter title. |
| `chapter_index` | `number` | 1-based flattened TOC chapter index. |
| `page` | `number` | Starting page of the chapter/event. |
| `event` | `string` | Summary of key plot events in that chapter. |
| `source` | `string` | Defaults to `"external"` on JSON load. |
| `story_id` / `story_title` | `string` | Optional Anthology scoping fields. |

---

## 7. Examples

### Minimal Valid `xray_cache.json`
```json
{
  "schema_version": "1.0",
  "book_title": "Example Novel",
  "author": "Jane Doe",
  "prevent_overwrite": true,
  "characters": [
    {
      "name": "Alice Mercer",
      "role": "Protagonist",
      "description": "An archivist investigating a missing manuscript."
    }
  ]
}
```

### Full Example (Spoiler Gating, Aliases, Links & AI Gap-Filling)
```json
{
  "schema_version": "1.0",
  "book_title": "Dune",
  "author": "Frank Herbert",
  "book_type": "fiction",
  "external_source": {
    "name": "BookOrbit",
    "prevent_overwrite": false,
    "read_only": false,
    "synced_at": 1732100000
  },
  "characters": [
    {
      "name": "Paul Atreides",
      "aliases": ["Usul", "Muad'Dib"],
      "alias_visible_from": {
        "usul": { "chapter_index": 22, "chapter_pct": 0.0 },
        "muad'dib": { "chapter_index": 22, "chapter_pct": 0.5 }
      },
      "role": "Protagonist",
      "status": "alive",
      "description": "Young heir of House Atreides.",
      "links": [
        "Lady Jessica",
        {
          "name": "Arrakis",
          "relation": "New homeworld",
          "visible_from": { "chapter_index": 5 }
        }
      ],
      "visible_from": { "chapter_index": 1, "page_hint": 1 },
      "states": [
        {
          "chapter_index": 1,
          "chapter_title": "Book 1, Chapter 1",
          "chapter_pct": 0.0,
          "role": "Heir of House Atreides",
          "status": "alive",
          "description": "Young heir of House Atreides preparing to leave Caladan."
        },
        {
          "chapter_index": 22,
          "chapter_title": "Book 2, Chapter 1",
          "chapter_pct": 0.5,
          "role": "Fremen Leader",
          "status": "alive",
          "description": "Accepted into Sietch Tabr under the name Muad'Dib."
        }
      ],
      "source": "external"
    },
    {
      "name": "Lady Jessica",
      "role": "Supporting",
      "description": "Bene Gesserit concubine of Duke Leto and mother of Paul.",
      "visible_from": { "chapter_index": 1, "page_hint": 1 },
      "source": "external"
    }
  ],
  "locations": [
    {
      "name": "Arrakis",
      "aliases": ["Dune"],
      "description": "Desert planet and the sole source of the spice melange.",
      "visible_from": { "chapter_index": 1, "page_hint": 2 },
      "source": "external"
    }
  ],
  "timeline": [
    {
      "chapter": "Chapter 1",
      "chapter_index": 1,
      "page": 1,
      "event": "Paul is tested with the gom jabbar by Reverend Mother Gaius Helen Mohiam.",
      "source": "external"
    }
  ]
}
```

---

## 8. Low-Memory E-Ink Guidelines (Kindle 256MB RAM)

X-Ray runs on older e-ink devices with as little as **256MB RAM** (e.g., Kindle Paperwhite 1):
- **File size limit:** X-Ray enforces a **5 MB** maximum size on `xray_cache.json`. Keep descriptions concise and avoid unnecessary whitespace if guides are large.
- **No embedded binary data:** Do not embed base64 images inside `xray_cache.json`.
- **Prefer `chapter_index` + `chapter_pct`:** Integer/float gates evaluate instantly during page turns with zero DOM lookups.
