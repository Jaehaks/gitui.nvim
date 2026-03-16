local M = {}

function M.setup(opts)
	require('gitui.config').set(opts)
end

function M.open()
    require("gitui.core").open()
end

return M
