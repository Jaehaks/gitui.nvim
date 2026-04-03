local M = {}

---@class gitui_state
---@field bufnr integer? Buffer number of gitui terminal
---@field tabnr integer? Tab id where gitui is opened
---@field jobnr integer? Job id for gitui process
---@field root string? Absolute path of git root directory

---@type gitui_state
local gitui = {
	bufnr = nil,
	tabnr = nil,
	winnr = nil,
	jobnr = nil,
	root = nil,
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
local wait_file = vim.fs.normalize(vim.fn.stdpath('data') .. "/gitui/wait")

--- get .git repo root
---@param bufnr integer buffer number
---@return string? Absolute path of root
local function get_repo_root(bufnr)
	local root = vim.fs.root(bufnr, { '.git' })
	return root
end


---@param bufnr integer buffer number
local function set_terminal_options(bufnr, winnr)
	bufnr = bufnr or 0
	winnr = winnr or 0
	-- 'bufhidden' of terminal buffer is ignored. it operates 'wipe' only
	-- 'swapfile' of terminal buffer is false as default
	vim.api.nvim_set_option_value('buflisted', false, {buf = bufnr}) -- don't show in :ls
	-- don't show statuscolumn in terminal buffer
	vim.api.nvim_set_option_value('number', false, {win = winnr}) -- don't show in :ls
	vim.api.nvim_set_option_value('relativenumber', false, {win = winnr}) -- don't show in :ls
	vim.api.nvim_set_option_value('signcolumn', 'no', {win = winnr}) -- don't show in :ls
	vim.api.nvim_set_option_value('statuscolumn', "", {win = winnr}) -- don't show in :ls
end

--- terminal gitui terminal
local function terminate_term()
	-- INFO: When process is quit, [process exit] message is remained at the terminal buffer
	-- INFO: User put any key, then close the terminal buffer and it is wiped out from buflist as default.
	-- INFO: You can remove the [process exit] message immediately by :tabclose or :bwipeout.
	-- INFO: Using :tabclose remains buffer and close window only. So terminal buffer is listed in buflist again.
	-- INFO: Using :bwipeout remove terminal buffer immediately and wipe it form buflist
	-- INFO: So it needs to use :bwipeout only to close terminal

	-- terminate gitui process
	if gitui.jobnr then
		pcall(vim.fn.jobstop, gitui.jobnr)
	end

	-- remove buffer
	if gitui.bufnr and vim.api.nvim_buf_is_valid(gitui.bufnr) then
		-- disable autocmd for editor opener
		local ok2 = pcall(vim.api.nvim_del_augroup_by_name, 'GitUI_OpenEditor')
		if not ok2 then
			vim.notify('GitUI_OpenEditor autocmd cannot be removed', vim.log.levels.WARN)
		end

		-- close tab
		if vim.api.nvim_tabpage_is_valid(gitui.tabnr) then
			local tab_pos = vim.api.nvim_tabpage_get_number(gitui.tabnr)
			pcall(function () vim.cmd('tabclose ' .. tab_pos) end)
		end

		-- wipe out gitui terminal buffer form buffer list (nvim_buf_delete() cannot wipe out)
		-- bwipeout invokes BufEnter. I have no idea why his appends
		local ok = pcall(function () vim.cmd('silent! bwipeout! ' .. gitui.bufnr) end)
		if not ok then
			vim.notify('Gitui terminal ' .. gitui.bufnr .. ' cannot be removed', vim.log.levels.WARN)
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


--- show git diff result to current tab
---@return integer buffer id of diff buffer
local function show_diff()
	local diff = require('gitui.diff')

	-- create empty buffer to show git diff
    local diff_bufnr = diff.create_diff()

	--- update diff buffer contents
	local function update_diff()
		---@class gitui.diffresults git diff results table
		---@field staged string
		---@field unstaged string
		---@field untracked string
		local results = {
			staged = "",
			unstaged = "",
			untracked = "",
		}

		--- write results to diff buffer after all `git diff` executions are done
		local done = 0
		local function on_git_done()
			done = done + 1
			if done < 3 then return end
			diff.load_diff(diff_bufnr, results)
		end

		--- on_exit callback for vim.system
		---@param key string
		local function on_exit(key)
			---@param out vim.SystemCompleted
			return function (out)
				results[key] = out.stdout
				on_git_done()
			end
		end

		-- get diff results asynchronously
		vim.system({ 'git', 'diff', '--cached', '--ignore-cr-at-eol' }, { cwd = gitui.root, text = true }, on_exit('staged'))
		vim.system({ 'git', 'diff', '--ignore-cr-at-eol' }, { cwd = gitui.root, text = true }, on_exit('unstaged'))
		vim.system({ 'git', 'ls-files', '--others', '--exclude-standard' }, { cwd = gitui.root, text = true }, function (out)
			local raw = vim.trim(out.stdout)
			-- If not exists, return
			if raw == "" then
				results.untracked = ""
				on_git_done()
				return
			end

			-- make untracked file list using table
			local files = {}
			for line in raw:gmatch('[^\r\n]+') do
				table.insert(files, line)
			end

			-- get diff contents of untracked files
			local untracked_results = {}
			local remaining = #files
			local null_dev = vim.fn.has('win32') == 1 and 'NUL' or '/dev/null'
			for i, file in ipairs(files) do
				vim.system({ 'git', 'diff', '--no-index', null_dev, file }, { cwd = gitui.root, text = true },
				function(out2)
					untracked_results[i] = out2.stdout
					remaining = remaining - 1
					if remaining == 0 then
						results.untracked = table.concat(untracked_results, "")
						on_git_done()
					end
				end)
			end
		end)
	end
	update_diff()

	-- register autocmd to auto update git diff contents every winenter
	-- the target buffer must have name to use it. autocmd will be removed automatically after diff_bufnr is removed

	-- 1) auto update diff view whenever buffer is changed
	local augroup = vim.api.nvim_create_augroup('GitUI_DiffUpdate', { clear = true })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		callback = function()
			if vim.api.nvim_buf_is_valid(diff_bufnr) then
				update_diff()
			end
		end,
	})

	-- 2) auto update diff view whenever git status is changed
	local watcher = vim.uv.new_fs_event()
	if watcher then
		watcher:start(gitui.root .. '/.git/index', {}, vim.schedule_wrap(function(err, _, _)
			if not err and vim.api.nvim_buf_is_valid(diff_bufnr) then
				update_diff()
			end
		end))

		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = diff_bufnr,
			once = true,
			callback = function()
				watcher:stop()
				pcall(vim.api.nvim_del_augroup_by_id, augroup)
			end,
		})
	end

	return diff_bufnr
end

---@param opts gitui.config
local function attach_editor_handle(opts)
	local commit_running = false

	-- when file is attached to open from gitui
	local augroup = vim.api.nvim_create_augroup("GitUI_OpenEditor", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", { -- after completing buffer transition
		group = augroup,
		callback = function(args)
			if not gitui.bufnr or not vim.api.nvim_buf_is_valid(gitui.bufnr) then return end
			-- ignore If the buffer is not editable (picker, others)
			if vim.api.nvim_get_option_value('buftype', {buf = args.buf}) ~= '' then return end
			-- When writing a commit message, prevent it from falling into the else case.
			if commit_running then return end

			local filename = vim.fn.fnamemodify(args.file, ":t")

			-- If it is commit message
			if filename == "COMMIT_EDITMSG" or filename == "MERGE_MSG" then
				commit_running = true

				-- commit msg will be opened in current tab(gitui) from remote_nvim.lua
				-- so change the focus to gitui buffer to tab page again
				vim.api.nvim_set_current_tabpage(gitui.tabnr)
				vim.api.nvim_set_current_buf(gitui.bufnr)

				-- open commit message in new tab
				vim.cmd('tabnew')
				vim.api.nvim_set_current_buf(args.buf)
				vim.api.nvim_set_option_value('filetype', 'gitcommit', {buf = args.buf})
				vim.api.nvim_set_option_value('bufhidden', 'wipe', {buf = args.buf}) -- invoke BufDelete event when :wq
				local commit_tabnr = vim.api.nvim_get_current_tabpage()

				-- show diff view
				local diff_bufnr = show_diff()

				--- close commit tab and return to gitui
				local function close_commit_tab()
					-- if editing commit msg is completed, remove wait_process file and make the wait process terminate
					if vim.fn.filereadable(wait_file) == 1 then
						vim.fn.delete(wait_file)
					end

					vim.schedule(function()
						focus_buffer(gitui.tabnr, gitui.bufnr)

						-- close tab which was created by commit message
						if vim.api.nvim_tabpage_is_valid(commit_tabnr) then
							local tabpos = vim.api.nvim_tabpage_get_number(commit_tabnr)
							pcall(function () vim.cmd('tabclose ' .. tabpos) end)
						end
						require('gitui.diff').clear_diffview_state()

						commit_running = false
					end)
				end

				-- if commit message/diff view writing is completed and close, go to focus
				for _, buf in ipairs({args.buf, diff_bufnr}) do
					vim.api.nvim_create_autocmd('BufUnload', {
						buffer = buf,
						once = true,
						callback = close_commit_tab
					})
				end

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
	gitui.root = root

	-- save current buffer state for editor
	prevbuf.tabnr = vim.api.nvim_get_current_tabpage()
	prevbuf.winnr = vim.api.nvim_get_current_win()

	-- open new tab
	vim.cmd("tabnew")
	gitui.tabnr = vim.api.nvim_get_current_tabpage()
	gitui.bufnr = vim.api.nvim_get_current_buf()
	gitui.winnr = vim.api.nvim_get_current_win()

	-- set autocmd to enter terminal mode automatically
	if opts.delay_startinsert then
		set_autoinsert(gitui.bufnr, opts.delay_startinsert)
	end

	-- set terminal buffer property
	set_terminal_options()

	-- set editor cmd to connect commit editor to this neovim
	-- --remote <file> : the <file> must be absolute file path. If it is relative one, empty file will be open
	-- 					 open <file> command in a remote neovim.
	-- --server <servername> : set which neovim instance is used to remote opening.
	-- 						   If the server is invalid, open in current terminal
	-- --remote-wait : not implemented yet.
	local server = vim.v.servername
	-- local editor_cmd = string.format("nvim --server %s --remote", server)
	local editor_cmd = string.format('nvim -l %s %s %s', wait_process, server, wait_file)

	-- open gitui terminal
	local cmd = {'gitui', '-t', opts.theme_path or plugin_root .. '/data/theme.ron'}
	gitui.jobnr = vim.fn.jobstart(cmd, {
		term = true, -- open in terminal buffer
		env = {
			GIT_EDITOR = editor_cmd,
			EDITOR = editor_cmd,
		},
		cwd = gitui.root,
		on_exit = function ()
			vim.schedule(function ()
				terminate_term()
			end)
		end
	})

	-- autocmd to deal editor request from gitui
	attach_editor_handle(opts)
end


return M
