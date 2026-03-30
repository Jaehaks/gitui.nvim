local M = {}

---@class gitui.config
---@field theme_path string? theme.ron path for gitui
---@field delay_startinsert integer? [ms] delay from opening terminal to setting controllable state, set nil to disable
local default_config = {
	theme_path = nil,
	delay_startinsert = 50,
}

local config = vim.deepcopy(default_config)

-- get configuration
M.get = function ()
	return config
end

-- set configuration
M.set = function (opts)
	config = vim.tbl_deep_extend('force', default_config, opts or {})

	vim.api.nvim_set_hl(0, 'GituiGroupTitle',   { fg = '#0d1117', bg = '#00ff87', bold = true })
	vim.api.nvim_set_hl(0, 'GituiFileAdded',    { fg = '#ffdd00', italic = true })
	vim.api.nvim_set_hl(0, 'GituiFileModified', { fg = '#ff2f55', italic = true })
	vim.api.nvim_set_hl(0, 'GituiFileDeleted',  { fg = '#8b8b8b', italic = true })
	vim.api.nvim_set_hl(0, 'GituiFileRenamed',  { fg = '#00aaff', italic = true })
	vim.api.nvim_set_hl(0, 'GituiFoldNone',  	{ fg = 'None', bg = 'None' })
end

return M
