local M = {}

---@class gitui_state
---@field bufnr integer? buffer number of gitui terminal
---@field tabnr integer? tab id where gitui is opened
local gitui = {
	bufnr = nil,
	tabnr = nil,
	jobnr = nil,
}

--- get .git repo root
---@param bufnr integer buffer number
---@return string? Absolute path of root
local function get_repo_root(bufnr)
	local root = vim.fs.root(bufnr, { '.git' })
	return root
end

---@param bufnr integer buffer number
local function set_terminal_options(bufnr)
	vim.api.nvim_set_option_value('buflisted', false, {buf = bufnr}) -- remove at :ls
	vim.api.nvim_set_option_value('bufhidden', 'wipe', {buf = bufnr}) -- wipe from memory when closed
	vim.api.nvim_set_option_value('swapfile', false, {buf = bufnr}) -- don't make swap file
end

--- terminal gitui terminal
local function terminate_term()
	-- remove buffer
	if gitui.bufnr and vim.api.nvim_buf_is_valid(gitui.bufnr) then
		pcall(vim.api.nvim_buf_delete, gitui.bufnr, {force = true})
	end
	-- remove tab
	if gitui.tabnr and vim.api.nvim_tabpage_is_valid(gitui.tabnr) then
		pcall(function () vim.cmd('tabclose ' .. gitui.tabnr) end)
	end
	-- reset state
	for k, _ in pairs(gitui) do
		gitui[k] = nil
	end
end

--- start insert to control gitui immediately when buffer is changed to terminal
---@param bufnr integer buffer number to set autoinsert autocmd
---@param delay integer [ms] delay after terminal buffer opened to start insert mode
local function set_autoinsert(bufnr, delay)
	vim.api.nvim_create_autocmd('TermOpen', {
		buffer = bufnr,
		once = true,
		callback = function ()
			vim.defer_fn(function () -- check focus is moved while startinsert delay
				if vim.api.nvim_get_current_buf() == bufnr then
					vim.cmd('startinsert')
				else
					terminate_term()
				end
			end, delay)
		end
	})
end

--- open gitui
---@param opts gitui.config
function M.open(opts)
	-- check cwd is git repository
	local root = get_repo_root(vim.api.nvim_get_current_buf())
	if not root then
		vim.notify('[gitui.nvim] current directory is not .git repository', vim.log.levels.ERROR)
		return
	end

	-- open new tab
	vim.cmd("tabnew")
	gitui.tabnr = vim.api.nvim_get_current_tabpage()
	gitui.bufnr = vim.api.nvim_get_current_buf()

	-- set autocmd to enter terminal mode automatically
	if opts.delay_startinsert then
		set_autoinsert(gitui.bufnr, opts.delay_startinsert)
	end

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
				terminate_term()
			end)
		end
	})
end


return M
