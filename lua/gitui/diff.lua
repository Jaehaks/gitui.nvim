local M = {}

---@class gitui.hunk_info
---@field filepath string
---@field group string staged / unstaged / untracked group
---@field kind string modified / added / deleted / renamed

--- get kind information from git diff header
---@param header string[] header string from git diff
---@param filepath string target file path
---@return string kind, string title
local function get_kind(header, filepath)
	local from = nil
	local to = nil
	for _, line in ipairs(header) do
		if line:match("^index") then
			return "modified", "modified " .. filepath
		elseif line:match("^new file") then
			return "added", "added " .. filepath
		elseif line:match("^deleted file") then
			return "deleted", "deleted " .. filepath
		elseif line:match("^rename from") then
			from = line:match("^rename from (.+)")
		elseif line:match("^rename to") then
			to = line:match("^rename to (.+)")
			return "renamed", "renamed " .. from .. '  ' .. to
		end
	end
	return "modified", "modified " .. filepath -- default pattern
end

--- transform raw string result of git diff to string[]
local function parse_diff(raw, label)
	if not raw or raw == "" then return {} end


	local lines = {} -- final string[] to show in diff view
	---@type gitui.hunk_info[]
	local hunk_infos = {} -- info list of hunks
	---@type gitui.hunk_info
	local cur_info = nil -- info of current hunks
	local hunk_header = {}
	local hunk_start = false

	local function add_title()
		local kind, title = get_kind(hunk_header, cur_info.filepath)
		cur_info.kind = kind -- update kind
		table.insert(lines, title)
	end

	for line in raw:gmatch('[^\r\n]+') do
		local fc = line:byte(1) -- get first character ascii code

		-- 1) put hunks if it is started with ' '(32), '+'(43), '-'(45) '\'(92)
		if hunk_start and (fc == 32 or fc == 43 or fc == 45 or fc == 92) then
			table.insert(lines, line)

		-- 2) put header which has filename, it will be title of folding
		elseif line:sub(1,4) == 'diff' then
			-- insert filepath to diffview if there is no @@ pattern such as rename
			-- add cur_info to avoid adding title at first call
			if cur_info and not hunk_start then add_title() end

			-- add hunk information
			local filepath = line:match('^diff %-%-git a/.- b/(.+)$')
			hunk_start = false -- end inserting diff contents
			hunk_header = {} -- initialize header
			cur_info = {
				filepath = filepath,
				group = label, -- staged / unstaged / untracked
				kind = nil, -- modified / added
			}
			table.insert(hunk_infos, cur_info)

		-- 3) check start hunk. Getting header is finished
		elseif line:sub(1,2) == '@@' then
			if not hunk_start then
				add_title()
				hunk_start = true -- start inserting diff contents
			end
			table.insert(lines, line)

		-- 4) get header info
		else
			table.insert(hunk_header, line)
		end
	end

	-- If last file doesn't have any hunk such as renamed file, add filepath title
	if not hunk_start then add_title() end
	return lines
end

local fold_level_1 = { Staged = true, Unstaged = true, Untracked = true, }
local fold_level_2 = { modified = true, added = true, delete = true, renamed = true }
--- expr function to folding, It must be global function
---@param lnum integer line number
_G._gitui_foldexpr = function(lnum)
	local line = vim.fn.getline(lnum)
	local first_word = line:match('^[^%a]*(%a+)')
	if first_word then
		if fold_level_1[first_word] then return ">1" end -- group fold
		if fold_level_2[first_word] then return ">2" end -- file fold
	end

	if line:match("^%s*@@") then return ">3" end -- hunk fold
	if line == "" then return "0" end
	return "3"
end

--- [keymap] toggle fold
local function toggle_fold()
	local lnum = vim.fn.line('.')
	local fold_level = vim.fn.foldlevel(lnum)
	local fold_closed = vim.fn.foldclosed(lnum)

	if fold_closed ~= -1 then
		if fold_level == 2 then
			vim.cmd("normal! zO") -- expand all under level 2
		else
			vim.cmd("normal! zo") -- If level 1 or 3, expand only 1 level
		end
	else
		vim.cmd("normal! zc") -- If fold is opened, close the specific fold level
	end
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

	-- default properties
	vim.wo.number = true
	vim.wo.relativenumber = true
	vim.wo.signcolumn = 'yes'
	vim.wo.foldcolumn = '0'
	vim.wo.statuscolumn = ''

	-- set fold properties
	vim.wo.foldmethod = 'expr'
	vim.wo.foldexpr = 'v:lua._gitui_foldexpr(v:lnum)'
	vim.wo.foldtext = 'getline(v:foldstart)'
	vim.opt_local.fillchars:append({
		fold = ' ',
		foldopen = 'v',
		foldclose = '>',
		foldsep = ' ',
	})

	-- set keymaps for diff view
	vim.keymap.set('n', '<Tab>', toggle_fold, { buffer = bufnr, silent = true, desc = '[gitui.nvim] Toggle Fold' })
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
		if #parsed>0 then
			vim.list_extend(contents, { label .. ' files' }) -- add group title
			table.insert(parsed, "") 						 -- add new line between groups
			vim.list_extend(contents, parsed)
		end
	end
	add_contents(untracked, 'Untracked')
	add_contents(unstaged, 'Unstaged')
	add_contents(staged, 'Staged')

	-- write diff contents to buffer
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(diff_bufnr) then return end
		vim.api.nvim_set_option_value('modifiable', true, { buf = diff_bufnr }) -- unlocked

		vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, contents) -- set contents
		vim.api.nvim_buf_call(diff_bufnr, function()
			vim.cmd("normal! zx")           -- update fold by foldexpr
			vim.wo.foldlevel = 1            -- default foldlevel
		end) -- set default fold level

		vim.api.nvim_set_option_value('modifiable', false, { buf = diff_bufnr }) -- locked
	end)
end


return M

