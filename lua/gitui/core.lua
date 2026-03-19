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

---@return string Absolute path of plugin root
local function get_plugin_root()
	local source_file = debug.getinfo(1, "S").source:sub(2) -- get current executing file path
	local plugin_root = vim.fs.root(source_file, {'.git'}) -- get plugin root
	return plugin_root or ""
end


---@param bufnr integer buffer number
local function set_terminal_options(bufnr)
	vim.api.nvim_set_option_value('buflisted', false, {buf = bufnr}) -- remove at :ls
	vim.api.nvim_set_option_value('bufhidden', 'hide', {buf = bufnr}) -- wipe from memory when closed
	vim.api.nvim_set_option_value('swapfile', false, {buf = bufnr}) -- don't make swap file
end

--- terminal gitui terminal
local function terminate_term()
	-- remove tab
	if gitui.tabnr and vim.api.nvim_tabpage_is_valid(gitui.tabnr) then
		local ok = pcall(function () vim.cmd('tabclose ' .. vim.api.nvim_tabpage_get_number(gitui.tabnr)) end)
		if not ok then
			vim.notify('Tab ' .. gitui.tabnr .. ' cannot be closed', vim.log.levels.WARN)
		end
	end
	-- remove buffer
	if gitui.bufnr and vim.api.nvim_buf_is_valid(gitui.bufnr) then
		-- wipe out gitui terminal buffer form buffer list (nvim_buf_delete() cannot wipe out)
		local ok pcall(function () vim.cmd('silent! bwipeout! ' .. gitui.bufnr) end)
		if not ok then
			vim.notify('Gitui terminal ' .. gitui.bufnr .. ' cannot be removed', vim.log.levels.WARN)
		end
		-- disable autocmd for editor opener
		ok = pcall(vim.api.nvim_del_augroup_by_name, 'GitUI')
		if not ok then
			vim.notify('GitUI autocmd cannot be removed', vim.log.levels.WARN)
		end
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

--- re-focus specific buffer in tabnr
---@param tabnr integer
---@param bufnr integer
---@return boolean true if terminal is valid
local function focus_buffer(tabnr, bufnr)
	if tabnr and vim.api.nvim_tabpage_is_valid(tabnr) then
		vim.api.nvim_set_current_tabpage(tabnr)
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabnr)) do
			if vim.api.nvim_win_get_buf(win) == bufnr then
				vim.api.nvim_set_current_win(win)
				if bufnr == gitui.bufnr then
					vim.cmd('startinsert')
				end
				break
			end
		end
		return true
	end
	return false
end

--- open gitui
---@param opts gitui.config
function M.open(opts)

	-- if the gitui is opened already, focus it.
	if focus_buffer(gitui.tabnr, gitui.bufnr) then
		return
	end

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

	-- set terminal buffer property
	set_terminal_options(gitui.bufnr)

	-- set editor cmd to connect commit editor to this neovim
	-- --remote <file> : the <file> must be absolute file path. If it is relative one, empty file will be open
	-- 					 open <file> command in a remote neovim.
	-- --server <servername> : set which neovim instance is used to remote opening.
	-- 						   If the server is invalid, open in current terminal
	-- --remote-wait : not implemented yet.
	local server = vim.v.servername
	local editor_cmd = string.format("nvim --server %s --remote", server)

	-- open gitui terminal
	local cmd = {'gitui', '-t', opts.theme_path or get_plugin_root() .. '/data/theme.ron'}
	gitui.jobnr = vim.fn.jobstart(cmd, {
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
