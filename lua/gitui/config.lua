local M = {}

---@class gitui.config
---@field commit_style string
---@field delay_startinsert integer? [ms] delay from opening terminal to setting controllable state, set nil to disable
---@field theme_path string? theme.ron path for gitui
local default_config = {
    commit_style = "fullscreen",
	delay_startinsert = 50,
	theme_path = nil,
}

local config = vim.deepcopy(default_config)

-- get configuration
M.get = function ()
	return config
end

-- set configuration
M.set = function (opts)
	config = vim.tbl_deep_extend('force', default_config, opts or {})
end

return M
