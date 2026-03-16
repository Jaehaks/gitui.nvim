local M = {}

function M.setup(opts)
	require('gitui.config').set(opts)
end

function M.open(opts)
	local config = require('gitui.config').get()
	config = vim.tbl_deep_extend('force', config, opts or {})
    require("gitui.core").open(config)
end

return M
