local M = {}

---@class gitui_state
---@field bufnr integer? buffer number of gitui terminal
---@field tabnr integer? tab id where gitui is opened
local gitui = {
	bufnr = nil,
	tabnr = nil,
	jobnr = nil,
}

local function get_root(bufnr)
	local root = vim.fs.root(bufnr, { '.git' })
	return root
end

local function gitui_state_clear()
	for k, _ in pairs(gitui) do
		gitui[k] = nil
	end
end

--- open gitui
function M.open()
	-- check cwd is git repository
	local root = get_root(vim.api.nvim_get_current_buf())
	if not root then
		vim.notify('[gitui.nvim] current directory is not .git repository', vim.log.levels.ERROR)
		return
	end

	-- open new tab
	vim.cmd("tabnew")
	gitui.tabnr = vim.api.nvim_get_current_tabpage()

	-- set editor cmd to connect commit editor to this neovim
	-- nvim --server <server ip> : If you open internal terminal in neovim and open some file using nvim,
	-- 							   the terminal use already opened neovim instance instead of new instance.
	-- --remote-wait : After opening buffer in remote server neovim, wait the process until the opened buffer is closed.
	-- 				   the terminal is blocked until the opened buffer is closed.
	local server = vim.v.servername
	local editor_cmd = string.format("nvim --server %s --remote-wait", server)

	-- open gitui terminal
	gitui.jobnr = vim.fn.jobstart({'gitui'}, {
		term = true, -- open in terminal buffer
		env = {
			GIT_EDITOR = editor_cmd,
			EDITOR = editor_cmd,
		},
		cwd = root,
		on_exit = function ()
			vim.schedule(function ()
				-- remove buffer
				if gitui.bufnr and vim.api.nvim_buf_is_valid(gitui.bufnr) then
					pcall(vim.api.nvim_buf_delete, gitui.bufnr, {force = true})
				end
				if gitui.tabnr and vim.api.nvim_tabpage_is_valid(gitui.tabnr) then
					pcall(function () vim.cmd('tabclose ' .. gitui.tabnr) end)
				end
				gitui_state_clear()
			end)
		end
	})

	-- set terminal buffer property
	gitui.bufnr = vim.api.nvim_get_chan_info(gitui.jobnr).buffer
	vim.api.nvim_set_option_value('buflisted', false, {buf = gitui.bufnr}) -- remove at :ls
	vim.api.nvim_set_option_value('bufhidden', 'wipe', {buf = gitui.bufnr}) -- wipe from memory when closed
	vim.api.nvim_set_option_value('swapfile', false, {buf = gitui.bufnr}) -- don't make swap file

end


return M
