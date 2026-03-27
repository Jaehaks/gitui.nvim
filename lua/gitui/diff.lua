local M = {}

--- transform raw string result of git diff to string[]
local function parse_diff(raw, label)
	if not raw or raw == "" then return {} end


	local lines = {}
	local hunk_start = false
	for line in raw:gmatch('[^\r\n]+') do
		local fc = line:byte(1) -- get first character ascii code

		-- 1) put hunks if it is started with ' '(32), '+'(43), '-'(45)
		if hunk_start and (fc == 32 or fc == 43 or fc == 45) then
			table.insert(lines, line)

		-- 2) put header which has filename, it will be title of folding
		elseif line:sub(1,4) == 'diff' then
			local filepath = line:match('^diff %-%-git a/.- b/(.+)$')
			table.insert(lines, ' [' .. label .. ']' .. filepath)
			hunk_start = false

		-- 3) check start hunk
		elseif line:sub(1,2) == '@@' then
			table.insert(lines, line)
			hunk_start = true
		end
	end
	return lines
end

--- create buffer showing git diff
---@return integer buffer id of diff view
M.create_diff = function ()

	local bufnr = vim.api.nvim_create_buf(false, true) -- make unlisted scratch buffer
	vim.api.nvim_set_option_value('filetype', 'diff', { buf = bufnr })
	vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
	vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })

	vim.cmd("topleft split")
	vim.api.nvim_set_current_buf(bufnr) -- show empty buffer in split view

	-- set fold properties
	-- vim.wo.foldmethod = 'expr'
	-- vim.wo.foldexpr = 'v:lua._gitui_foldexpr(v:lnum)'
	-- vim.wo.foldtext = 'getline(v:foldstart)'

	-- set keymaps for diff view
	vim.keymap.set('n', '<Tab>', 'za', { buffer = bufnr, silent = true, desc = '[gitui.nvim] Toggle Fold' })
	vim.keymap.set('n', '<CR>', function()
		-- local fname, file_line = parser.resolve_diff_target(bufnr)
		-- if fname then
		-- 	on_open(fname, file_line)
		-- end
	end, { buffer = bufnr, silent = true, desc = '[gitui.nvim] Go to the line of file' })

	vim.cmd("wincmd j") -- move focus
	return bufnr
end

--- write diff_result to diff_bufnr
---@param diff_bufnr integer buffer id of diff buffer
---@param diff_result gitui.diffresults
M.load_diff = function (diff_bufnr, diff_result)

	-- string with \n
	local untracked = diff_result.untracked
	local unstaged = diff_result.unstaged
	local staged = diff_result.staged

	-- parse and modify git results to use in nvim_buf_set_lines() and fold
	local contents = {}
	local function add_contents(str, label)
		local parsed = parse_diff(str, label)
		if #parsed>0 then table.insert(parsed, "") end -- add empty line
		vim.list_extend(contents, parsed)
	end
	add_contents(untracked, 'Untracked')
	add_contents(unstaged, 'Unstaged')
	add_contents(staged, 'Staged')

	-- write diff contents to buffer
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(diff_bufnr) then return end
		vim.api.nvim_set_option_value('modifiable', true, { buf = diff_bufnr }) -- unlocked

		vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, contents) -- set contents
		-- vim.api.nvim_buf_call(diff_bufnr, function() vim.cmd("normal! zM") end) -- close all fold in diff_bufnr

		vim.api.nvim_set_option_value('modifiable', false, { buf = diff_bufnr }) -- locked
	end)
end


return M

