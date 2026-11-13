---
trigger: always_on
---

# Cross-Feature Invariants & Hardware Stability Rules

The KOReader X-Ray plugin combines multiple interacting features (**Prefetch Horizon**, **Spoiler Protection**, **Story Arcs / Evolution**, **Anthology Mode**, **Entity Footnote Underlines**, **Unit Converter**, and **Series Context**) and runs on devices with as little as **256MB RAM** (Kindle Paperwhite 1, Gen 5, 2012). Every code change must uphold these 5 invariants.

---

## 1. Horizon & Spoiler Gating Invariant

When `spoiler_setting ~= "full_book"`, entities in `self.book_data` may already contain prefetched states, descriptions, or secret aliases from future chapters (`checkPrefetchHorizon`).

1. **Never Read Raw Entity Fields in UI or Scanners**:
   - In popups (`showBottomPopup`, `showEntityFootnote`), detail cards (`showCharacterDetails`, `showLocationDetails`, `showTermDetails`), and list views, **never** display raw `entity.role`, `entity.status`, `entity.description`, or `entity.definition` directly when `entity.states` is populated.
   - Always resolve through `self:resolveEntityState(entity)` and `self:resolveDescriptionForPage(entity)`.
2. **Gate Entity & Alias Visibility**:
   - Always check `self:isEntityVisibleAtCurrentPosition(entity)` before surfacing an entity in search, inline lookups (`findCharacterByName`, `_findEntityByNameAndCategory`), or page underlines.
   - Always iterate `self:getUnlockedAliases(entity)`—**never** raw `entity.aliases`—when highlighting mentions (`highlightMentionsOnPage`), resolving entity underline boxes (`_resolveEntityHighlightBoxes`), or rendering alias labels.
3. **Preserve Temporal Data During Merges & Deduplication**:
   - Any code that deduplicates or merges two entity entries (`deduplicateByName`, `mergeEntryItems`, or custom merge flows) **must** call `self:mergeEntityTemporalData(target, source)` so `states`, `history`, `visible_from`, and `alias_visible_from` gates are never dropped.

---

## 2. Anthology Story Boundary Invariant

When `self:isAnthologyMode()` is active, a single book contains multiple independent stories with separate casts and settings.

1. **Story Scoping**:
   - Resolve the active story via `local cur_story = self:getCurrentStory(page)`.
   - When `chapter_analyzer:getStoryForTocIndex(self.ui, chapter_idx, custom_depth)` returns a story table, never pass that table into `self:getCurrentStory(...)` (which expects a numeric page number).
2. **No Cross-Story Prefetch or Contamination**:
   - `checkPrefetchHorizon` and `queueSequentialChapterScan` must never prefetch chapters beyond `cur_story.end_page` / `cur_story.end_toc_idx`.
   - Newly extracted characters, locations, and terms must be stamped with `story_id` and `story_title` before deduplication.
   - Inline lookups and entity scanners must prioritize entities belonging to `cur_story` (or marked `isEntityRecurring`).

---

## 3. Async Subprocess & Timer Hygiene

1. **Subprocess Tracking & Cancellation (`makeRequestAsync` / `runInSubProcess`)**:
   - Every background polling loop (`queueSequentialChapterScan`, `runPostFetchDuplicateCheck`, `fetchSeriesContext`, `checkSeriesContext`, `ensureAnthologyDecision`, `triggerBookTypeDetection`, unit/entity scanners) must store its child `pid` and temp `result_file`.
   - On timeout, user cancellation, or `self.destroyed == true`, you **must** call `self.ai_helper:cancelAsyncChild(pid)` (or `ffiutil.terminateSubProcess(pid)`) and `os.remove(result_file)` so orphaned `luajit` processes never cause `"error_busy"` lockups or RAM exhaustion.
2. **Timer Unscheduling (`UIManager:unschedule`)**:
   - `UIManager:scheduleIn(delay, fn)` returns the callback function reference `fn`, **not** a timer object.
   - Always cancel scheduled timers with `UIManager:unschedule(self.timer_handle)`—**never** `self.timer_handle:cancel()`.
3. **Deterministic Async Unit Tests (`advance_time`)**:
   - When testing coroutine/timer loops with a mock `advance_time(seconds)` helper, always advance `mock_time` step-by-step to each scheduled task's `target` timestamp before invoking `task.fn()`, so multi-slice coroutines (`UIManager:scheduleIn(0.02, step)`) complete deterministically regardless of host CPU load.

---

## 4. Low-Memory & Lifecycle Cleanup (Kindle 256MB RAM)

1. **Symmetrical Cleanup in `destroy()` and `onLowMemory()`**:
   - Any cache, highlight box table (`unit_conversion_boxes`, `entity_highlight_boxes`), or native `BlitBuffer` tile cache (`clearTileCaches`) must be explicitly cleared in **both** `XRayPlugin:destroy()` and `XRayPlugin:onLowMemory()`.
   - Ensure lexical scope declarations of module-level caches appear *above* the cleanup functions that free them.
2. **No Main-Thread Full-Book Fallbacks During Page Turns**:
   - In page-turn rendering hooks (`onPageUpdate`, `_resolveEntityHighlightBoxes`, `_resolveHighlightBoxes`), if the 3-page window (`current_page - 1` to `current_page + 1`) has 0 matches, return an empty list `{}`. Never fall back to resolving screen boxes across the entire book's XPointer list on the UI thread.

---

## 5. DRY Shared Utilities

Do not duplicate common helpers across modules. Always use the canonical implementations:
- **Current Page**: `utils:getCurrentPage(self)` (in `xray_utils.lua`)
- **Metadata Sanitization**: `utils:sanitizeMetadata(val)` (in `xray_utils.lua`)
- **Image Header Dimensions (PNG/JPEG/WebP/GIF)**: `utils:getImageDimensions(file_path)` (in `xray_utils.lua`)
- **Book Cache Persistence**: `self:saveCurrentBookCache(data, on_done_cb)` (in `xray_data.lua`)
