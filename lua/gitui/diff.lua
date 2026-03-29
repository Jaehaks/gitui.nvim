local M = {}

local utils = require('gitui.utils')
local ns_id = vim.api.nvim_create_namespace('gitui_diff')

---@class gitui.hunk_info
---@field filepath string
---@field group string staged / unstaged / untracked group
---@field kind_hl string? highlight for kind (modified / added)
---@field kind_eidx integer? end col of kind string

---@class gitui.diffview
---@field winid_commit integer? commit message window id
---@field winid_diff integer? diffview buffer window id
---@field winid_aux integer? opened buffer in diffview window id
local diffview = {
	winid_commit = nil,
	winid_diff = nil,
	winid_aux = nil,
}

--- clear diffview state
M.clear_diffview_state = function ()
	for k, _ in pairs(diffview) do
		diffview[k] = nil
	end
end

--- get kind information from git diff header
---@param header string[] header string from git diff
---@param filepath string target file path
---@return string kind_hl, string title
local function get_kind(header, filepath)
	local from = nil
	local to = nil
	for _, line in ipairs(header) do
		if line:match("^index") then
			return "GituiFileModified", "modified " .. filepath
		elseif line:match("^new file") then
			return "GituiFileAdded", "added " .. filepath
		elseif line:match("^deleted file") then
			return "GituiFileDeleted", "deleted " .. filepath
		elseif line:match("^rename from") then
			from = line:match("^rename from (.+)")
		elseif line:match("^rename to") then
			to = line:match("^rename to (.+)")
			return "GituiFileRenamed", "renamed " .. from .. '  ' .. to
		end
	end
	return "GituiFileModified", "modified " .. filepath -- default pattern
end
-- test
--- transform raw string result of git diff to string[]
---@param raw string raw stdout of git diff
---@param label string group label staged / unstaged / untracked
---@return string[] sliced stdout data form to show in diff view
---@return gitui.hunk_info[] matching information between line number in diff view and filepath without offset
local function parse_diff(raw, label)
	if not raw or raw == "" then return {}, {} end

	local lines = {} -- final string[] to show in diff view
	---@type gitui.hunk_info[] info list of each file by line
	local file_infos = {}
	---@type gitui.hunk_info info of current hunks
	local cur_info = nil
	local hunk_header = {}
	local hunk_start = false

	--- add title to fold by adding kind to filepath
	local function add_title()
		local kind_hl, title = get_kind(hunk_header, cur_info.filepath)
		table.insert(lines, title)
		cur_info.kind_hl = kind_hl
		local _, kind_eidx = title:find('^%a+')
		if kind_eidx then
			cur_info.kind_eidx = kind_eidx
		end
		file_infos[#lines] = cur_info
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
				group = label,
				kind_hl = nil,
				kind_eidx = nil,
			}

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
	return lines, file_infos
end

local fold_level_1 = { Staged = true, Unstaged = true, Untracked = true, }
local fold_level_2 = { modified = true, added = true, deleted = true, renamed = true }
--- expr function to folding, It must be global function
---@param lnum integer line number
_G._gitui_foldexpr = function(lnum)
	local line = vim.fn.getline(lnum)
	local first_word = line:match('^(%a+)')
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

--- open file and move to cursor where user <CR> in hunk from diff view buffer
local function open_hunk()

	-- get current line info
	local lnum = vim.fn.line('.')
	local line_str = vim.fn.getline(lnum)
	local fw = line_str:match('^(%a+)')

	-- ignore the line is empty or group title
	if line_str == "" or (fw and fold_level_1[fw]) then return end

	---@class open_info
	---@field filepath string? absolute path of the file where cursor is on
	---@field row integer line number to move cursor
	local open_info = {
		filepath = nil,
		row = 1,
	}
	local file_lnum = 1

	-- 1) get filepath which is most closed from current cursor line toward upwards
	-- To get correct filepath which might have white spaces
	local file_infos = vim.b.gitui_diff_file_infos or {}
	for i = lnum, 1, -1 do
		local key = tostring(i)
		if file_infos[key] then
			open_info.filepath = file_infos[key].filepath
			file_lnum = i
			break
		end
	end
	if not open_info.filepath then return end

	-- 2) Search upwards to find the nearest @@ (hunk header)
	-- @@ -15,4 +15,6 @@  =>  -<oldfile start lnum><oldfile lines> +<new file start lnum><new file lines>
	if lnum > file_lnum then
		local hunk_lnum = vim.fn.search('^@@', 'bnW') -- it includes current line number
		local hunk_header = vim.fn.getline(hunk_lnum)
		local hunk_start_lnum = tonumber(hunk_header:match('%+(%d+)')) -- start line in target file
		if hunk_start_lnum then
			local offset = 0
			for i = hunk_lnum+1, lnum - 1 do
				local fc = vim.fn.getline(i):byte(1) -- get first char
				if fc == 32 or fc == 43 then
					offset = offset + 1
				end
			end
			open_info.row = hunk_start_lnum + offset
		end
	end

	-- 3) open the file and move to cursor
	if open_info.filepath then
		if diffview.winid_aux and vim.api.nvim_win_is_valid(diffview.winid_aux) then
			vim.api.nvim_set_current_win(diffview.winid_aux)
		else
			vim.api.nvim_set_current_win(diffview.winid_commit)
			vim.cmd('vsplit')
		end
		vim.cmd('edit ' .. open_info.filepath)
		vim.api.nvim_win_set_cursor(0, {open_info.row, 0})
		vim.cmd('normal! zz')
		diffview.winid_aux = vim.api.nvim_get_current_win()
	end
end

--- create buffer showing git diff
---@return integer buffer id of diff view
M.create_diff = function ()
	diffview.winid_commit = vim.api.nvim_get_current_win() -- set window id of commit message
	local bufnr = vim.api.nvim_create_buf(false, true) -- make unlisted scratch buffer
	vim.api.nvim_set_option_value('filetype', 'diff', { buf = bufnr })
	vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
	vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
	vim.api.nvim_buf_set_name(bufnr, 'gitui://diff_view' .. bufnr)

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
	vim.wo.foldtext = '' -- To retain highlight setting as plugin set
	utils.update_win_option(0, 'fillchars', {fold = ' ', foldopen = 'v', foldclose = '>', foldsep = ' '}) -- remove fill chars of fold
	utils.update_win_option(0, 'winhighlight', {Folded = 'GituiFoldNone'}) -- disable default fold highlight

	-- set keymaps for diff view
	vim.keymap.set('n', '<Tab>', toggle_fold, { buffer = bufnr, silent = true, desc = '[gitui.nvim] Toggle Fold' })
	vim.keymap.set('n', '<CR>', open_hunk, { buffer = bufnr, silent = true, desc = '[gitui.nvim] Go to the line of file' })

	vim.api.nvim_set_current_win(diffview.winid_commit) -- restore focus to commit message
	return bufnr
end

--- write contents to diff buffer
---@param bufnr integer buffer if to reload view state
---@param contents string[] diff contents
---@param new_file_infos gitui.hunk_info[] diff contents
---@param group_hl_infos gitui.hunk_info[] diff contents
local function write_diff(bufnr, contents, new_file_infos, group_hl_infos)
	if not vim.api.nvim_buf_is_valid(bufnr) then return end

	vim.api.nvim_buf_call(bufnr, function() -- use it to manipulate scratch buffer
		-- save view of current window
		local view = vim.fn.winsaveview()
		local opened_folds = {}

		-- get previous folding state
		---@type gitui.hunk_info[]
		local old_file_infos = vim.b[bufnr].gitui_diff_file_infos or {}
		for key, info in pairs(old_file_infos) do
			local lnum = tonumber(key)
			if not lnum then return end
			if vim.fn.foldclosed(lnum) == -1 then
				opened_folds[info.group .. '|' .. info.filepath] = true
			end
		end

		-- write contents to buffer
		vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
		vim.b[bufnr].gitui_diff_file_infos = new_file_infos

		-- set highlight
		-- 1) group title
		vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) -- clear previous highlight
		for lnum, _ in pairs(group_hl_infos) do
			vim.api.nvim_buf_set_extmark(bufnr, ns_id, lnum-1, 0, { -- extmark is 0-index
				line_hl_group = 'GituiGroupTitle',
				hl_eol = true,
			})
		end
		-- 2) file title
		for key, info in pairs(new_file_infos) do
			local lnum = tostring(key)
			vim.api.nvim_buf_set_extmark(bufnr, ns_id, lnum-1, 0, {
				hl_group = info.kind_hl,
				end_col = info.kind_eidx,
			})
		end

		-- update folding tree
		vim.cmd("normal! zx")           -- update fold by foldexpr
		vim.wo.foldlevel = 1            -- default foldlevel

		-- restore folding state, expands if it is expanded before
		if diffview.winid_diff then -- restore it after second update
			for key, info in pairs(new_file_infos) do
				local lnum = tonumber(key)
				if not lnum then return end
				if opened_folds[info.group .. '|' .. info.filepath] then
					vim.fn.cursor(lnum, 1)
					pcall(function() vim.cmd("normal! zO") end)
				end
			end
		end
		diffview.winid_diff = vim.api.nvim_get_current_win()
		vim.fn.winrestview(view)
	end)

	vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
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
	---@type gitui.hunk_info[]
	local gitui_diff_file_infos = {} 	-- combination with all group file_infos
	local group_hl_infos = {} 			-- group title line information for highlight
	local function add_contents(str, label)
		local parsed, file_infos = parse_diff(str, label)
		if #parsed>0 then
			table.insert(contents, label .. ' files ' .. '(' .. vim.tbl_count(file_infos) .. ')') -- add group title
			group_hl_infos[#contents] = label
			local offset = #contents
			vim.list_extend(contents, parsed)
			table.insert(contents, '') -- add new line between groups

			for local_lnum, cur_info in pairs(file_infos) do
				gitui_diff_file_infos[tostring(local_lnum + offset)] = cur_info -- it must has string key to save to vim.b
			end
		end
	end
	add_contents(untracked, 'Untracked')
	add_contents(unstaged, 'Unstaged')
	add_contents(staged, 'Staged')

	-- write diff contents to buffer
	vim.schedule(function()
		write_diff(diff_bufnr, contents, gitui_diff_file_infos, group_hl_infos)
	end)
end


return M

