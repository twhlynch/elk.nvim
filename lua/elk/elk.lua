local M = {}

local utils = require("elk.utils")

--- parse elk --quiet output
--- @param output string
--- @return vim.Diagnostic.Set[]
function M.parse(output)
	--- @type vim.Diagnostic.Set[]
	local diagnostics = {}

	local severity_map = {
		Error = vim.diagnostic.severity.ERROR,
		Warning = vim.diagnostic.severity.WARN,
	}

	-- parse output
	local clean = utils.strip_ansi(output)
	local lines = utils.split_lines(clean)

	for _, line in ipairs(lines) do
		-- extract parts
		local sev, msg, ls, cs, le, ce = line:match("^(%a+):%s+(.-)%s+%(Line (%d+):(%d+)-(%d+):(%d+)%)")
		local severity = sev and severity_map[sev]

		-- insert diagnostic
		if severity and ls and cs and le and ce then
			table.insert(diagnostics, {
				lnum = tonumber(ls) - 1,
				col = tonumber(cs) - 1,
				end_lnum = tonumber(le) - 1,
				end_col = tonumber(ce) - 1,
				severity = severity,
				message = msg,
				source = "elk",
			})
		end
	end

	return diagnostics
end

--- @param permit string | string[]
--- @return string
local function serialize_permit(permit)
	if type(permit) == "string" then
		return permit
	end
	return table.concat(permit, ",")
end

--- @param aliases string | table<string, integer>
--- @return string
local function serialize_trap_aliases(aliases)
	if type(aliases) == "string" then
		return aliases
	end
	local items = {}
	for alias, vect in pairs(aliases) do
		table.insert(items, string.format("%s=0x%02x", alias, vect))
	end
	return table.concat(items, ",")
end

--- elk runner
--- @param bufnr integer
--- @param cmd string path to elk
function M.run(bufnr, cmd)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- create temp file
	local ext = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e")
	local path = vim.fn.tempname() .. (ext ~= "" and ("." .. ext) or ".asm")

	-- write buffer content to file
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local success = utils.write_file(path, lines)
	if not success then
		return
	end

	local options = require("elk.options").get()

	local args = {
		cmd,
		"--check", path,
		"--quiet",
		"--permit", serialize_permit(options.permit),
	}
	if options.level == "err" then
		args[#args + 1] = "--relaxed"
	end
	if options.trap_aliases ~= nil then
		args[#args + 1] = "--trap-aliases"
		args[#args + 1] = serialize_trap_aliases(options.trap_aliases)
	end

	-- run elk on file
	vim.system(
		args,
		{ text = true },
		vim.schedule_wrap(function(result)
			-- remove the temp file
			os.remove(path)
			-- then check buffer
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			-- parse diagnostics
			local output = (result.stderr or "") .. (result.stdout or "")
			vim.diagnostic.set(M.ns, bufnr, M.parse(output))
		end)
	)
end

--- setup a buffer
--- @param args vim.api.keyset.create_autocmd.callback_args
function M.attach(args)
	local bufnr = args.buf
	local options = require("elk.options").get()

	-- setup completion
	require("elk.cmp").setup_file()

	-- always run on changing text out of insert mode
	vim.api.nvim_create_autocmd({ "TextChanged" }, {
		group = M.group,
		buffer = bufnr,
		callback = function()
			utils.start_debounce(bufnr, M.run, bufnr, options.binary)
		end,
	})

	-- check changedtick when entering then exiting insert
	local tick = vim.b[bufnr].changedtick or 0
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = M.group,
		buffer = bufnr,
		callback = function()
			tick = vim.b[bufnr].changedtick or tick
		end,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = M.group,
		buffer = bufnr,
		callback = function()
			local new_tick = vim.b[bufnr].changedtick or tick
			if new_tick ~= tick then
				utils.start_debounce(bufnr, M.run, bufnr, options.binary)
			end
		end,
	})

	-- always run on entering a buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = M.group,
		buffer = bufnr,
		callback = function()
			utils.start_debounce(bufnr, M.run, bufnr, options.binary)
		end,
	})

	-- cleanup on delete
	vim.api.nvim_create_autocmd("BufDelete", {
		group = M.group,
		buffer = bufnr,
		callback = M.detach,
	})

	-- initial run
	M.run(bufnr, options.binary)
end

--- detach from and cleanup a buffer
--- @param args vim.api.keyset.create_autocmd.callback_args
function M.detach(args)
	local bufnr = args.buf

	-- clear diagnostics and debounce timer
	utils.stop_debounce(bufnr)
	vim.diagnostic.reset(M.ns, bufnr)

	-- clear autocmds for buffer
	vim.api.nvim_clear_autocmds({ group = M.group, buffer = bufnr })
end

--- setup plugin
function M.setup()
	local options = require("elk.options").get()

	-- group and namespace
	M.group = vim.api.nvim_create_augroup("ElkDiagnostics", { clear = true })
	M.ns = vim.api.nvim_create_namespace("elk")

	-- attach to files matching the specified types
	vim.api.nvim_create_autocmd("FileType", {
		group = M.group,
		pattern = options.filetypes,
		callback = M.attach,
	})

	-- setup completion
	require("elk.cmp").setup()
end

return M
