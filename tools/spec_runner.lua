local squashfs_root = os.getenv("SQUASHFS_ROOT") or "/home/jimmy/squashfs-root"
package.path = package.path .. ";" .. squashfs_root .. "/usr/lib/koreader/common/?.lua;" .. squashfs_root .. "/usr/lib/koreader/?.lua;xray.koplugin/?.lua;?.lua"

local stats = { passed = 0, failed = 0, errors = {} }
local before_each_stack = {}
local after_each_stack = {}
local current_describe = {}

local function push_context()
    table.insert(before_each_stack, {})
    table.insert(after_each_stack, {})
end

local function pop_context()
    table.remove(before_each_stack)
    table.remove(after_each_stack)
end

_G.before_each = function(fn)
    local current = before_each_stack[#before_each_stack]
    if current then table.insert(current, fn) end
end

_G.after_each = function(fn)
    local current = after_each_stack[#after_each_stack]
    if current then table.insert(current, fn) end
end

_G.describe = function(name, fn)
    table.insert(current_describe, name)
    push_context()
    local ok, err = pcall(fn)
    if not ok then
        print("Error in describe " .. table.concat(current_describe, " -> ") .. ": " .. tostring(err))
    end
    pop_context()
    table.remove(current_describe)
end

_G.it = function(name, fn)
    local full_name = table.concat(current_describe, " -> ") .. " -> " .. name
    
    -- Run all before_each
    for _, level in ipairs(before_each_stack) do
        for _, before_fn in ipairs(level) do
            pcall(before_fn)
        end
    end
    
    -- Run test
    local ok, err = pcall(fn)
    
    -- Run all after_each
    for _, level in ipairs(after_each_stack) do
        for _, after_fn in ipairs(level) do
            pcall(after_fn)
        end
    end
    
    if ok then
        stats.passed = stats.passed + 1
    else
        stats.failed = stats.failed + 1
        table.insert(stats.errors, { name = full_name, err = err })
        print("[FAIL] " .. full_name)
        print("       " .. tostring(err))
    end
end

_G.setup = function(fn) pcall(fn) end
_G.teardown = function(fn) pcall(fn) end

local function deep_compare(t1, t2)
    if type(t1) ~= type(t2) then return false end
    if type(t1) ~= "table" then return t1 == t2 end
    for k, v in pairs(t1) do
        if not deep_compare(v, t2[k]) then return false end
    end
    for k, v in pairs(t2) do
        if not deep_compare(v, t1[k]) then return false end
    end
    return true
end

_G.assert = {
    is_true = function(val)
        if not val then error("Expected true, got " .. tostring(val), 2) end
    end,
    is_false = function(val)
        if val then error("Expected false, got " .. tostring(val), 2) end
    end,
    is_nil = function(val)
        if val ~= nil then error("Expected nil, got " .. tostring(val), 2) end
    end,
    is_not_nil = function(val)
        if val == nil then error("Expected not nil", 2) end
    end,
    is_table = function(val)
        if type(val) ~= "table" then error("Expected table, got " .. type(val), 2) end
    end,
    is_string = function(val)
        if type(val) ~= "string" then error("Expected string, got " .. type(val), 2) end
    end,
    is_number = function(val)
        if type(val) ~= "number" then error("Expected number, got " .. type(val), 2) end
    end,
    is_boolean = function(val)
        if type(val) ~= "boolean" then error("Expected boolean, got " .. type(val), 2) end
    end,
    truthy = function(val)
        if not val then error("Expected truthy, got " .. tostring(val), 2) end
    end,
    falsy = function(val)
        if val then error("Expected falsy, got " .. tostring(val), 2) end
    end,
    are = {
        equal = function(expected, actual)
            if expected ~= actual then
                error("Expected " .. tostring(expected) .. ", got " .. tostring(actual), 3)
            end
        end,
        same = function(expected, actual)
            if not deep_compare(expected, actual) then
                error("Expected identical values/tables", 3)
            end
        end
    },
    are_not = {
        equal = function(expected, actual)
            if expected == actual then
                error("Expected not equal to " .. tostring(expected), 3)
            end
        end
    }
}
_G.assert.equals = _G.assert.are.equal
_G.assert.same = _G.assert.are.same
_G.assert.is_falsy = _G.assert.falsy
_G.assert.is_truthy = _G.assert.truthy

-- List of spec files to execute
local specs = {
    "spec/xray_utils_spec.lua",
    "spec/xray_cachemanager_spec.lua",
    "spec/xray_chapteranalyzer_spec.lua",
    "spec/xray_data_spec.lua",
    "spec/xray_fetch_spec.lua",
    "spec/xray_lookupmanager_spec.lua",
    "spec/xray_mentions_spec.lua",
    "spec/xray_registration_spec.lua",
    "spec/xray_ui_spec.lua",
    "spec/json_constraint_spec.lua",
    "spec/reasoning_logic_spec.lua",
    "spec/xray_aihelper_spec.lua",
    "spec/xray_terms_spec.lua",
    "spec/xray_seriesmanager_spec.lua",
    "spec/xray_units_spec.lua",
    "spec/xray_crypto_spec.lua",
    "spec/xray_websetup_spec.lua",
    "spec/xray_imagemanager_spec.lua",
    "spec/xray_imageviewer_spec.lua",
    "spec/xray_nontouch_spec.lua",
    "spec/xray_background_fetch_spec.lua"
}

if arg and arg[1] then
    specs = { arg[1] }
end

print("=== Running KOReader X-Ray Unit Tests ===")
for _, spec_path in ipairs(specs) do
    print("Loading " .. spec_path .. "...")
    local fn, err = loadfile(spec_path)
    if fn then
        fn()
    else
        print("Error loading spec file: " .. tostring(err))
    end
end

print("\n=== Test Results ===")
print("Passed: " .. stats.passed)
print("Failed: " .. stats.failed)

if stats.failed > 0 then
    print("\nFailures:")
    for _, item in ipairs(stats.errors) do
        print("  - " .. item.name .. "\n    " .. tostring(item.err))
    end
    os.exit(1)
else
    print("\nAll tests passed successfully!")
    os.exit(0)
end
