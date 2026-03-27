local servername = arg[1]
local wait_file = arg[2]
local open_file = arg[3]

-- check file which is obtained is commit message
local is_commit = open_file:find("COMMIT_EDITMSG$") or open_file:find("MERGE_MSG$")

-- make wait file first
-- It needs to remain remote_nvim.lua process to implement waiting until commit message is quit
-- It is like --remote-wait option
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

-- open file in 'server' neovim instance using rpc to avoid glob operation when we use `nvim --remote <file>`
-- It needs to fnameescape to treat special characters as literal path in command
local escaped_open_file = vim.fs.normalize(vim.fn.fnamemodify(open_file, ':p')) -- get absolute path
if vim.fn.has('win32') == 1 then
	escaped_open_file = escaped_open_file:gsub('/', '\\')
else
	escaped_open_file = escaped_open_file:gsub('\\', '/')
end
escaped_open_file = vim.fn.fnameescape(escaped_open_file) -- treat special characters as literal
local ch = vim.fn.sockconnect('pipe', servername, {rpc = true})
local opener = 'edit '
vim.rpcrequest(ch, 'nvim_command', opener .. escaped_open_file)

-- if the file is commit message, wait this process until dummy file exists
if is_commit then
	-- -- wait until it is removed
    while not vim.uv.fs_stat(wait_file) do
		vim.uv.sleep(10)
    end

	-- wait until it is removed
    while vim.uv.fs_stat(wait_file) do
		vim.uv.sleep(100)
    end
end
