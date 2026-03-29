local M = {}

--- update current window winhl without changing original value
---@param winid integer? window id
---@param opt_name string win option name
---@param values table value as table
M.update_win_option = function(winid, opt_name, values)
    vim.api.nvim_win_call(winid or 0, function()
        local current = vim.opt_local[opt_name]:get()
        for k, v in pairs(values) do
            current[k] = v
        end
        vim.opt_local[opt_name] = current
    end)
end

return M
