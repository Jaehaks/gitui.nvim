local servername = arg[1]
local file = arg[2]

-- open file in 'server' neovim instance
local escaped_file = vim.fs.normalize(vim.fn.fnamemodify(file, ':p')) -- get absolute path
escaped_file = vim.fn.fnameescape(escaped_file)
local is_commit = file:find("COMMIT_EDITMSG$") or file:find("MERGE_MSG$")

local filename = vim.fs.basename(escaped_file) .. '.wait'
local wait_file = vim.fs.normalize(vim.fn.stdpath('data') .. "/gitui/" .. filename)

if is_commit then
	local parent_dir = vim.fs.dirname(wait_file)

	-- make parent dir if it doesn't exist
	if not vim.uv.fs_stat(parent_dir) then
		vim.uv.fs_mkdir(parent_dir, 493) -- 0755
	end

	-- make dummy file to wait this lua process
    local fd = vim.uv.fs_open(wait_file, 'w', 438) -- 0666
    if fd then vim.uv.fs_close(fd) end
end

local ch = vim.fn.sockconnect('pipe', servername, {rpc = true})
vim.rpcrequest(ch, 'nvim_command', 'e ' .. escaped_file)

-- if the file is commit message, wait this process until dummy file exists
if is_commit then
	-- wait until it is removed
    while not vim.uv.fs_stat(wait_file) do
		vim.uv.sleep(10)
    end

	-- wait until it is removed
    while vim.uv.fs_stat(wait_file) do
		vim.uv.sleep(100)
    end
end
