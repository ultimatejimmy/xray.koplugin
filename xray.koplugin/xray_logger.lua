-- xray_logger.lua — X-Ray Plugin Logger
-- Handles log writing, rotation (max 512KB), and clearing.

local Logger = {
    path = nil,
    max_size = 512 * 1024, -- 512 KB
}

function Logger:init(path)
    self.path = path or "plugins/xray.koplugin"
    
    -- Write a session start marker
    local log_path = self.path .. "/xray.log"
    local f = io.open(log_path, "a")
    if f then
        f:write("\n" .. string.rep("=", 40) .. "\n")
        f:write("--- X-Ray Session Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
        f:close()
    end
end

function Logger:log(message)
    if not self.path then return end
    local log_path = self.path .. "/xray.log"
    
    self.write_count = (self.write_count or 0) + 1
    if self.write_count >= 50 then
        self.write_count = 0
        -- Check size and rotate if necessary
        local f_size = io.open(log_path, "r")
        if f_size then
            local current_size = f_size:seek("end")
            f_size:close()
            if current_size > self.max_size then
                os.remove(log_path .. ".old")
                os.rename(log_path, log_path .. ".old")
            end
        end
    end

    local f = io.open(log_path, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message) .. "\n")
        f:close()
    end
end

function Logger:clear()
    if not self.path then return end
    os.remove(self.path .. "/xray.log")
    os.remove(self.path .. "/xray.log.old")
end

return Logger
