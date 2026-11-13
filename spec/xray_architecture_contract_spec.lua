-- spec/xray_architecture_contract_spec.lua
-- Architecture Contract Tests: Snapshot & enforce module exports, mixin surface, and plugin lifecycle
require("spec/spec_helper")

describe("X-Ray Architecture Contract Spec", function()
    local main_plugin
    local xray_ui
    local xray_fetch
    local xray_data
    local xray_mentions
    local xray_unitscanner
    local xray_entityscanner
    local xray_aihelper
    local xray_utils
    local xray_anthology, xray_booktype, xray_style_cards, xray_menu_builder
    local xray_duplicates, xray_onboarding, xray_horizon, xray_images_ui
    local xray_bottom_popup, xray_log_viewer, xray_series_ui

    setup(function()
        main_plugin = dofile("xray.koplugin/main.lua")
        xray_ui = require("xray_ui")
        xray_fetch = require("xray_fetch")
        xray_data = require("xray_data")
        xray_mentions = require("xray_mentions")
        xray_unitscanner = require("xray_unitscanner")
        xray_entityscanner = require("xray_entityscanner")
        xray_anthology = require("xray_anthology")
        xray_booktype = require("xray_booktype")
        xray_style_cards = require("xray_style_cards")
        xray_menu_builder = require("xray_menu_builder")
        xray_duplicates = require("xray_duplicates")
        xray_onboarding = require("xray_onboarding")
        xray_horizon = require("xray_horizon")
        xray_images_ui = require("xray_images_ui")
        xray_bottom_popup = require("xray_bottom_popup")
        xray_log_viewer = require("xray_log_viewer")
        xray_series_ui = require("xray_series_ui")
        xray_aihelper = require("xray_aihelper")
        xray_utils = require("xray_utils")
    end)

    describe("Module Export Contracts", function()
        it("xray_ui exports all required methods", function()
            local expected_ui_methods = {
                "showCharacterDetails", "showLocationDetails", "showTermDetails",
                "showTimelineEventDetails", "showHistoricalFigureDetails",
                "showCharacters", "showLocations", "showTerms", "showTimeline", "showHistoricalFigures",
                "showWelcomeCard", "handleWelcomeAction", "showConfigFileGuide",
                "getAPIKeysMenu", "getProviderKeySubMenu", "getAIModelSelectionMenu",
                "findRelatedEntities", "showRelatedEntities",
                "closeAllMenus", "hasXRayData", "_promptNoDataFetch",
                "startFullBookPreGeneration", "confirmAndRebuildXRay",
                "showImages", "showImageActions", "openImageViewer", "jumpToImagePage",
                "showManageSeriesDialog", "showSeriesContextPrompt", "checkSeriesContext",
                "getCurrentDocPage", "getCurrentChapterIndex", "getChapterPageBounds",
                "isPositionGateUnlocked", "getUnlockedAliases", "getUnlockedStateCount",
                "isEntityVisibleAtCurrentPosition", "resolveEntityState", "resolveDescriptionForPage",
                "showPastEvolution", "hasEntityEvolution",
                "viewLog"
            }
            for _, m in ipairs(expected_ui_methods) do
                assert.is_not_nil(xray_ui[m], "Missing method on xray_ui: " .. m)
                assert.are.equal("function", type(xray_ui[m]), "Expected function for xray_ui." .. m)
            end
        end)

        it("xray_fetch exports all required methods", function()
            local expected_fetch_methods = {
                "fetchFromAI", "updateFromAI",
                "fetchSingleWord", "_processSingleWordResult",
                "continueWithFetch", "finalizeXRayData", "populateBatchTemporalGates",
                "runPostFetchDuplicateCheck", "fetchMoreEntities",
                "fetchMoreCharacters", "fetchMoreTerms", "fetchAuthorInfo",
                "mergeSeriesContext", "fetchSeriesContext",
                "mergeSequentialChapterDelta", "checkpointHorizonScan",
                "queueSequentialChapterScan", "cancelSequentialChapterScan",
                "updateEntityDescPreservingPrior", "markSeriesSyncDirty", "flushSeriesSync",
                "isRequestTimedOut", "cancelActiveAIRequest"
            }
            for _, m in ipairs(expected_fetch_methods) do
                assert.is_not_nil(xray_fetch[m], "Missing method on xray_fetch: " .. m)
                assert.are.equal("function", type(xray_fetch[m]), "Expected function for xray_fetch." .. m)
            end
        end)

        it("xray_data exports all required methods", function()
            local expected_data_methods = {
                "normalizeChapterName", "isNonNarrativeChapter",
                "isMoreCompleteName", "promoteName", "deduplicateByName",
                "assignTimelinePages", "filterOrphanTimelineEvents",
                "sortTimelineByTOC", "sortDataByFrequency",
                "mergeEntryItems", "mergeEntries", "linkEntriesAcrossStories",
                "mergeEntityTemporalData", "saveCurrentBookCache"
            }
            for _, m in ipairs(expected_data_methods) do
                assert.is_not_nil(xray_data[m], "Missing method on xray_data: " .. m)
                assert.are.equal("function", type(xray_data[m]), "Expected function for xray_data." .. m)
            end
        end)

        it("xray_mentions exports all required methods", function()
            local expected_mentions_methods = {
                "showMentionsForEntity", "buildMentionsMenuItems",
                "updateMentionsMenuInPlace", "showMentionsMenu",
                "highlightMentionsOnPage", "clearHighlightOverlay",
                "showReturnBanner", "saveMentionsToCache"
            }
            for _, m in ipairs(expected_mentions_methods) do
                assert.is_not_nil(xray_mentions[m], "Missing method on xray_mentions: " .. m)
                assert.are.equal("function", type(xray_mentions[m]), "Expected function for xray_mentions." .. m)
            end
        end)

        it("xray_unitscanner and xray_entityscanner export all required methods", function()
            local expected_unit_methods = {
                "scanBookForUnits", "saveUnitCache", "loadUnitCache",
                "clearUnitUnderlines", "clearTileCaches", "findUnitBoxAtPoint",
                "showUnitTooltip", "mountTapHandler", "_handleUnitTap",
                "_startUnitScanSubprocess", "_cancelUnitScanChild"
            }
            for _, m in ipairs(expected_unit_methods) do
                assert.is_not_nil(xray_unitscanner[m], "Missing method on xray_unitscanner: " .. m)
                assert.are.equal("function", type(xray_unitscanner[m]), "Expected function for xray_unitscanner." .. m)
            end

            local expected_entity_methods = {
                "scanBookForEntities", "saveEntityCache", "loadEntityCache",
                "clearEntityUnderlines", "addEntityToUnderlines",
                "_startEntityScanSubprocess", "_cancelEntityScanChild",
                "_resolveEntityHighlightBoxes", "_isEntityAllowedByVisibility",
                "mountEntityTapHandler", "_handleEntityTap",
                "_rebuildEntityPageBuckets", "_deduplicateEntityHits"
            }
            for _, m in ipairs(expected_entity_methods) do
                assert.is_not_nil(xray_entityscanner[m], "Missing method on xray_entityscanner: " .. m)
                assert.are.equal("function", type(xray_entityscanner[m]), "Expected function for xray_entityscanner." .. m)
            end

            local expected_anthology_methods = {
                "detectAnthologyFromMetadata", "isAnthologyMode", "markStoryPresence", "getStoryPresence",
                "migrateStoryPresence", "isEntityRecurring", "getEntityStoryRole", "isStoryAfterCurrent",
                "ensureStoryPresenceScanned", "getCurrentStory", "resolveEntityStory", "isEntityInCurrentStory",
                "collectAnthologySignals", "persistBookData", "retagEntitiesByStory", "ensureAnthologyDecision"
            }
            for _, m in ipairs(expected_anthology_methods) do
                assert.is_not_nil(xray_anthology[m], "Missing method on xray_anthology: " .. m)
                assert.are.equal("function", type(xray_anthology[m]), "Expected function for xray_anthology." .. m)
            end

            local expected_booktype_methods = {
                "detectBookTypeHeuristic", "getEffectiveBookType", "triggerBookTypeDetection",
                "handleBookTypeOverride", "showBookTypeOverrideCard", "getBookTypeFilterMenu"
            }
            for _, m in ipairs(expected_booktype_methods) do
                assert.is_not_nil(xray_booktype[m], "Missing method on xray_booktype: " .. m)
                assert.are.equal("function", type(xray_booktype[m]), "Expected function for xray_booktype." .. m)
            end

            local expected_style_methods = {
                "showUnitStyleCard", "showUnitAutoScanCard", "showUnitScanWrittenNumbersCard",
                "showPopupFontSizeCard", "openReaderMenuToPath", "showUnitConverterNewFeatureCard",
                "showEntityPopupStyleCard", "showEntityMentionModeCard", "showEntityStyleCard",
                "showEntityFootnotesNewFeatureCard"
            }
            for _, m in ipairs(expected_style_methods) do
                assert.is_not_nil(xray_style_cards[m], "Missing method on xray_style_cards: " .. m)
                assert.are.equal("function", type(xray_style_cards[m]), "Expected function for xray_style_cards." .. m)
            end

            local expected_menu_methods = {
                "getMenuCounts", "getSubMenuItems", "addToMainMenu"
            }
            for _, m in ipairs(expected_menu_methods) do
                assert.is_not_nil(xray_menu_builder[m], "Missing method on xray_menu_builder: " .. m)
                assert.are.equal("function", type(xray_menu_builder[m]), "Expected function for xray_menu_builder." .. m)
            end

            local expected_dupe_methods = {
                "buildDuplicateCandidates", "resolveDuplicatePair", "makeRejectKey",
                "isPairRejected", "filterValidDuplicatePairs", "walkDuplicatePairs",
                "showAIFindDuplicatesFlow", "showMergeFlow"
            }
            for _, m in ipairs(expected_dupe_methods) do
                assert.is_not_nil(xray_duplicates[m], "Missing method on xray_duplicates: " .. m)
                assert.are.equal("function", type(xray_duplicates[m]), "Expected function for xray_duplicates." .. m)
            end

            local expected_onboarding_methods = {
                "showWelcomeCard", "refreshAPIKeysMenu", "handleWelcomeAction",
                "showEnterKeyProviderDialog", "promptProviderKeyEntry", "showConfigFileGuide",
                "getAPIKeysMenu", "getProviderKeySubMenu", "testSingleProviderConnection",
                "showValidateAllKeysDialog", "getAIModelSelectionMenu"
            }
            for _, m in ipairs(expected_onboarding_methods) do
                assert.is_not_nil(xray_onboarding[m], "Missing method on xray_onboarding: " .. m)
                assert.are.equal("function", type(xray_onboarding[m]), "Expected function for xray_onboarding." .. m)
            end

            local expected_horizon_methods = {
                "getCurrentDocPage", "getCurrentChapterIndex", "hasEntityEvolution",
                "getChapterPageBounds", "isPositionGateUnlocked", "getUnlockedAliases",
                "getUnlockedStateCount", "isEntityVisibleAtCurrentPosition",
                "resolveEntityState", "resolveDescriptionForPage", "showPastEvolution"
            }
            for _, m in ipairs(expected_horizon_methods) do
                assert.is_not_nil(xray_horizon[m], "Missing method on xray_horizon: " .. m)
                assert.are.equal("function", type(xray_horizon[m]), "Expected function for xray_horizon." .. m)
            end

            local expected_images_ui_methods = {
                "showImages", "renameImageDialog", "showImageActions", "openImageViewer",
                "_launchImageViewer", "resumeMinimizedImage", "resumeImagesFeature", "jumpToImagePage"
            }
            for _, m in ipairs(expected_images_ui_methods) do
                assert.is_not_nil(xray_images_ui[m], "Missing method on xray_images_ui: " .. m)
                assert.are.equal("function", type(xray_images_ui[m]), "Expected function for xray_images_ui." .. m)
            end

            local expected_bottom_popup_methods = {
                "calculatePopupFontMetrics", "showBottomPopup", "shouldUseBottomPopup"
            }
            for _, m in ipairs(expected_bottom_popup_methods) do
                assert.is_not_nil(xray_bottom_popup[m], "Missing method on xray_bottom_popup: " .. m)
                assert.are.equal("function", type(xray_bottom_popup[m]), "Expected function for xray_bottom_popup." .. m)
            end

            local expected_log_viewer_methods = {
                "clearLogs", "viewLog"
            }
            for _, m in ipairs(expected_log_viewer_methods) do
                assert.is_not_nil(xray_log_viewer[m], "Missing method on xray_log_viewer: " .. m)
                assert.are.equal("function", type(xray_log_viewer[m]), "Expected function for xray_log_viewer." .. m)
            end

            local expected_series_ui_methods = {
                "toggleSeriesContextEnabled", "manualFetchSeriesContext", "getExpectedPriorIndices",
                "showSeriesContextPrompt", "checkSeriesContext", "getCurrentSeriesInfo", "showManageSeriesDialog"
            }
            for _, m in ipairs(expected_series_ui_methods) do
                assert.is_not_nil(xray_series_ui[m], "Missing method on xray_series_ui: " .. m)
                assert.are.equal("function", type(xray_series_ui[m]), "Expected function for xray_series_ui." .. m)
            end
        end)

        it("XRayPlugin class includes all mixin functions", function()
            local core_methods = {
                "init", "destroy", "onCloseDocument", "onReaderClose", "onExit", "onSuspend",
                "onReaderReady", "onPageUpdate", "onDispatcherRegisterActions",
                "addToMainMenu", "getSubMenuItems", "getMenuCounts",
                "isAnthologyMode", "getCurrentStory", "resolveEntityStory", "ensureAnthologyDecision",
                "detectBookTypeHeuristic", "getEffectiveBookType", "triggerBookTypeDetection",
                "showUnitStyleCard", "showEntityStyleCard", "checkPrefetchHorizon"
            }
            for _, m in ipairs(core_methods) do
                assert.is_not_nil(main_plugin[m], "Missing method on XRayPlugin: " .. m)
                assert.are.equal("function", type(main_plugin[m]), "Expected function for XRayPlugin." .. m)
            end
        end)
    end)

    describe("Plugin Lifecycle Contract", function()
        it("instantiates cleanly, initializes submodules, and destroys with zero leaks", function()
            local inst = createMockPlugin()
            for k, v in pairs(main_plugin) do inst[k] = v end
            inst.path = "xray.koplugin/"
            if inst.init then inst:init() end

            assert.is_not_nil(inst)
            assert.is_not_nil(inst.ai_helper)
            assert.is_not_nil(inst.chapter_analyzer)
            assert.is_not_nil(inst.lookup_manager)
            assert.is_not_nil(inst.series_manager)
            assert.is_not_nil(inst.image_manager)

            -- onLowMemory must execute cleanly without error
            local mem_ok, mem_err = pcall(function() inst:onLowMemory() end)
            assert.is_true(mem_ok, "onLowMemory threw error: " .. tostring(mem_err))

            -- destroy must execute cleanly
            local des_ok, des_err = pcall(function() inst:destroy() end)
            assert.is_true(des_ok, "destroy threw error: " .. tostring(des_err))
            assert.is_true(inst.destroyed)
        end)
    end)
end)
