local M = {}

---@class gitui_state
---@field bufnr integer? buffer number of gitui terminal
---@field tabnr integer? tab id where gitui is opened
---@field jobnr integer? job id for gitui process

---@type gitui_state
local gitui = {
	bufnr = nil,
	tabnr = nil,
	jobnr = nil,
}

---@class prevbuf_state previous buffer state to open editor from gitui
---@field tabnr integer?
---@field winr integer?

---@type prevbuf_state
local prevbuf = {
	tabnr = nil,
	winnr = nil,
}

local plugin_root = vim.fs.root(debug.getinfo(1, "S").source:sub(2), {'.git'}) or ""
local wait_process = plugin_root .. '/lua/gitui/wait/remote_nvim.lua'

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

local function attach_editor_handle()
	-- when file is attached to open from gitui
	local augroup = vim.api.nvim_create_augroup("GitUI", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", { -- after completing buffer transition
		group = augroup,
		callback = function(args)
			if not gitui.bufnr or not vim.api.nvim_buf_is_valid(gitui.bufnr) then return end
			-- called nvim from gitui must be opened in gitui.tabnr
			if vim.api.nvim_get_current_tabpage() ~= gitui.tabnr then return end
			-- ignore If the buffer is not editable (picker, others)
			if vim.api.nvim_get_option_value('buftype', {buf = args.buf}) ~= '' then return end

			local filename = vim.fn.fnamemodify(args.file, ":t")

			-- If it is commit message
			if filename == "COMMIT_EDITMSG" or filename == "MERGE_MSG" then
				vim.api.nvim_set_option_value('filetype', 'gitcommit', {buf = args.buf})
				vim.api.nvim_set_option_value('bufhidden', 'wipe', {buf = args.buf}) -- invoke BufDelete event when :wq

				vim.api.nvim_set_current_tabpage(gitui.tabnr)
				-- vim.api.nvim_set_current_buf(gitui.bufnr) -- restore focus to gitui terminal to show with split view together
				-- vim.cmd("split")
				vim.api.nvim_set_current_buf(args.buf) -- open target buffer

				-- if commit message writing is completed and close, go to focus
				vim.api.nvim_create_autocmd("BufDelete", {
					buffer = args.buf,
					once = true,
					callback = function()
						-- if editing commit msg is completed, remove wait_process file and make the wait process terminate
						if vim.fn.filereadable(wait_process) == 1 then
							vim.fn.delete(wait_process)
						end

						vim.schedule(function()
							focus_buffer(gitui.tabnr, gitui.bufnr)
						end)
					end,
				})
			-- If it is normal file opening
			else
				-- -- set args.buf's location to previous tab page
				if prevbuf.tabnr and vim.api.nvim_tabpage_is_valid(prevbuf.tabnr) then
					vim.api.nvim_set_current_tabpage(prevbuf.tabnr)
					if prevbuf.winnr and vim.api.nvim_win_is_valid(prevbuf.winnr) then
						vim.api.nvim_set_current_win(prevbuf.winnr)
					end
				end
				vim.api.nvim_set_current_buf(args.buf)

				-- terminate gitui
				terminate_term()
			end
		end,
	})
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

	-- save current buffer state for editor
	prevbuf.tabnr = vim.api.nvim_get_current_tabpage()
	prevbuf.winnr = vim.api.nvim_get_current_win()

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
	-- local editor_cmd = string.format("nvim --server %s --remote", server)
	local editor_cmd = string.format('nvim -l %s %s', wait_process, server)

	-- open gitui terminal
	local cmd = {'gitui', '-t', opts.theme_path or plugin_root .. '/data/theme.ron'}
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

	-- autocmd to deal editor request from gitui
	attach_editor_handle()

end


return M
