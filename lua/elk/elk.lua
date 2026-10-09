local M = {}

local analytics = require("elk.analytics")
local listing = require("elk.listing")
local utils = require("elk.utils")

--- @type table<integer, boolean>
M.attached = {} --- attached buffers

--- emulation timeout in milliseconds
local ANALYTICS_TIMEOUT = 5000

--- parse elk --quiet output
--- @param output string
--- @return vim.Diagnostic.Set[]
function M.parse(output)
	--- @type vim.Diagnostic.Set[]
	local diagnostics = {}

	local severity_map = {
		Error = vim.diagnostic.severity.ERROR,
		Warning = vim.diagnostic.severity.WARN,
		Info = vim.diagnostic.severity.INFO,
	}

	-- parse output
	local clean = utils.strip_ansi(output)
	local lines = utils.split_lines(clean)

	for _, line in ipairs(lines) do
		-- extract parts
		-- Error: Some error message (/path/to/file.asm:1:2-3:4)
		-- for now, ignore the file. TODO: actually use the file path
		local sev, msg, file, ls, cs, le, ce = line:match("^(%a+):%s+(.-)%s+%(([^:]+):(%d+):(%d+)-(%d+):(%d+)%)$")
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
function M.serialize_permit(permit)
	if type(permit) == "string" then
		return permit
	end
	return table.concat(permit, ",")
end

--- @param permit string
function M.deserialize_permit(permit)
	return vim.split(permit, ",", { plain = true })
end

--- @param aliases string | table<string, integer>
--- @return string
function M.serialize_trap_aliases(aliases)
	if type(aliases) == "string" then
		return aliases
	end
	local items = {}
	for alias, vect in pairs(aliases) do
		table.insert(items, string.format("%s=x%02x", alias, vect))
	end
	return table.concat(items, ",")
end

--- @param str string
--- @return table<string, integer>
function M.deserialize_trap_aliases(str)
	local aliases = {}
	for pair in str:gmatch("[^,]+") do
		local alias, vect = pair:match("([^=]+)=x(%x+)")
		if alias and vect then
			aliases[alias] = tonumber(vect)
		end
	end
	return aliases
end

--- write a buffer to a temp source file
--- @param bufnr integer
--- @return string | nil path, nil when the write fails
local function temp_source(bufnr)
	local ext = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e")
	local path = vim.fn.tempname() .. (ext ~= "" and ("." .. ext) or ".asm")
	if not utils.write_file(path, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) then
		return nil
	end
	return path
end

--- flags shared by every elk assemble invocation
--- @param cmd string path to elk
--- @param path string source file
--- @param options Elk.Options.options
--- @param extra string[] flags added after the common ones
--- @return string[]
local function assemble_args(cmd, path, options, extra)
	-- stylua: ignore
	local args = {
		cmd,
		"--assemble", path,
		"--quiet",
		"--permit", M.serialize_permit(options.permit),
	}
	for _, arg in ipairs(extra) do
		args[#args + 1] = arg
	end
	if options.level == "err" then
		args[#args + 1] = "--relaxed"
	end
	return args
end

--- elk runner
--- @param bufnr integer
--- @param cmd string path to elk
function M.run(bufnr, cmd)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local path = temp_source(bufnr)
	if not path then
		return
	end

	local options = require("elk.options").get()
	local extra = { "--export-listing" }
	if options.trap_aliases ~= nil then
		extra[#extra + 1] = "--trap-aliases"
		extra[#extra + 1] = M.serialize_trap_aliases(options.trap_aliases)
	end

	local args = assemble_args(cmd, path, options, extra)

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

			-- remove obj if generated
			local obj_path = vim.fn.fnamemodify(path, ":r") .. ".obj"
			if vim.fn.filereadable(obj_path) == 1 then
				os.remove(obj_path)
			end

			-- parse diagnostics
			local output = (result.stderr or "") .. (result.stdout or "")
			local diagnostics = M.parse(output)
			vim.diagnostic.set(M.ns, bufnr, diagnostics)

			-- remove and parse listing
			local listing_path = vim.fn.fnamemodify(path, ":r") .. ".lst"
			if vim.fn.filereadable(listing_path) == 1 then
				local lst_lines = vim.fn.readfile(listing_path)
				os.remove(listing_path)
				listing.show(bufnr, lst_lines)
			else
				listing.clear(bufnr)
			end
		end)
	)
end

--- emulate a buffer once and show per line execution info
--- @param bufnr integer
--- @param cmd string path to elk
--- @param options Elk.Options.options
--- @param stdin string input fed to the program's stdin
local function emulate(bufnr, cmd, options, stdin)
	local path = temp_source(bufnr)
	if not path then
		return
	end
	local base = vim.fn.fnamemodify(path, ":r")
	local analytics_path = vim.fn.tempname() .. ".json"

	-- stdin content, redirected into the emulation below
	local stdin_path = vim.fn.tempname() .. ".in"
	local stdin_file = io.open(stdin_path, "w")
	if not stdin_file then
		os.remove(path)
		return
	end
	stdin_file:write(stdin)
	stdin_file:close()

	-- elk rejects piped stdin (TermiosFailed), so emulate through sh with a
	-- file redirect: stdin never comes from nvim (GETC would steal
	-- keystrokes) and the timeout still kills elk itself
	local emu_opts = { text = true, timeout = ANALYTICS_TIMEOUT }

	--- flags shared by every emulation, elk only reads policies at runtime
	--- @param input string[] leading args, a source file or --emulate <obj>
	--- @return string[]
	local function emulate_args(input)
		local args = vim.list_slice(input, 1, #input)
		args[#args + 1] = "--quiet"
		args[#args + 1] = "--permit"
		args[#args + 1] = M.serialize_permit(options.permit)
		args[#args + 1] = "--analytics"
		args[#args + 1] = analytics_path
		if options.level == "err" then
			args[#args + 1] = "--relaxed"
		end
		return args
	end

	--- run elk with stdin coming from the temp file
	--- @param args string[] elk arguments without the binary
	--- @return string[]
	local function with_stdin(args)
		local parts = { "exec", vim.fn.shellescape(cmd) }
		for _, arg in ipairs(args) do
			parts[#parts + 1] = vim.fn.shellescape(arg)
		end
		return { "sh", "-c", table.concat(parts, " ") .. " < " .. vim.fn.shellescape(stdin_path) }
	end

	--- remove the run's temp files
	local function cleanup()
		os.remove(path)
		os.remove(stdin_path)
		os.remove(base .. ".obj")
		os.remove(base .. ".sym")
		os.remove(base .. ".lst")
	end

	--- abandon a failed run and tell the user why
	--- @param result vim.SystemCompleted|nil
	local function fail(result)
		cleanup()
		os.remove(analytics_path)
		analytics.clear(bufnr)
		local detail = ""
		if result then
			detail = vim.trim(utils.strip_ansi((result.stderr or "") .. (result.stdout or "")))
			detail = vim.split(detail, "\n")[1] or ""
		end
		if detail ~= "" then
			vim.notify("[elk] analytics failed: " .. detail, vim.log.levels.WARN)
		else
			vim.notify("[elk] analytics run failed or timed out", vim.log.levels.WARN)
		end
	end

	--- handle a finished emulation
	--- @param result vim.SystemCompleted
	local function finish(result)
		if not vim.api.nvim_buf_is_valid(bufnr) then
			cleanup()
			os.remove(analytics_path)
			return
		end
		if result.code ~= 0 or vim.fn.filereadable(analytics_path) == 0 then
			fail(result)
			return
		end
		local contents = table.concat(vim.fn.readfile(analytics_path))
		os.remove(analytics_path)
		cleanup()

		local ok, json = pcall(vim.json.decode, contents)
		if ok then
			analytics.show(bufnr, json)
		else
			analytics.clear(bufnr)
		end
	end

	if options.trap_aliases == nil then
		-- assemble and emulate in one step
		vim.system(with_stdin(emulate_args({ path })), emu_opts, vim.schedule_wrap(finish))
		return
	end

	-- elk rejects trap aliases on emulate, so assemble with them first
	-- (matching M.run) then emulate the .obj
	vim.system(
		assemble_args(cmd, path, options, { "--trap-aliases", M.serialize_trap_aliases(options.trap_aliases) }),
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 or vim.fn.filereadable(base .. ".obj") == 0 then
				fail(result)
				return
			end
			vim.system(with_stdin(emulate_args({ "--emulate", base .. ".obj" })), emu_opts, vim.schedule_wrap(finish))
		end)
	)
end

--- emulate a buffer once and show per line execution info, prompting for the
--- input to feed the program's stdin
--- @param bufnr integer
--- @param cmd string path to elk
function M.analytics(bufnr, cmd)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.ui.input({ prompt = "elk stdin: " }, function(input)
		if input == nil then
			return
		end
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		-- an empty prompt means the program reads no input at all
		emulate(bufnr, cmd, require("elk.options").get(), input ~= "" and (input .. "\n") or "")
	end)
end

--- setup a buffer
--- @param args vim.api.keyset.create_autocmd.callback_args
function M.attach(args)
	local bufnr = args.buf
	local options = require("elk.options").get()

	M.attached[bufnr] = true

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

	-- clear listing and restore gutter
	M.attached[bufnr] = nil
	listing.clear(bufnr)
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		listing.restore(win)
	end

	-- clear analytics
	analytics.clear(bufnr)

	-- clear autocmds for buffer
	vim.api.nvim_clear_autocmds({ group = M.group, buffer = bufnr })
end

--- :Elk command handler
--- @param args vim.api.keyset.create_user_command.command_args
function M.command(args)
	local bufnr = vim.api.nvim_get_current_buf()

	if args.args == "start" then
		-- attach to buffer
		if vim.api.nvim_buf_is_loaded(bufnr) and utils.is_elk_ft(bufnr) then
			M.attach({ buf = bufnr })
		end
	elseif args.args == "stop" then
		-- detach from buffer
		if vim.api.nvim_buf_is_loaded(bufnr) then
			M.detach({ buf = bufnr })
		end
	elseif args.args == "analytics" then
		-- emulate once and show execution info
		if vim.api.nvim_buf_is_loaded(bufnr) and M.attached[bufnr] then
			M.analytics(bufnr, require("elk.options").get().binary)
		else
			vim.notify("[elk] buffer is not attached, run :Elk start first", vim.log.levels.WARN)
		end
	elseif args.args == "listing" then
		-- flip the listing gutter on and off
		listing.toggle()
	else
		vim.notify("[elk] Invalid argument: " .. args.args, vim.log.levels.ERROR)
	end
end

--- setup plugin
function M.setup()
	local options = require("elk.options").get()

	-- group and namespace
	M.group = vim.api.nvim_create_augroup("ElkDiagnostics", { clear = true })
	M.ns = vim.api.nvim_create_namespace("elk")

	listing.setup()
	analytics.setup()

	-- attach to files matching the specified types
	vim.api.nvim_create_autocmd("FileType", {
		group = M.group,
		pattern = options.filetypes,
		callback = M.attach,
	})

	vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
		group = M.group,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			listing.record_winopts(win)
			listing.ensure(win)
		end,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		group = M.group,
		pattern = { "number", "relativenumber" },
		callback = function()
			listing.record_winopts(vim.api.nvim_get_current_win())
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = M.group,
		callback = function(args)
			local win = tonumber(args.match)
			if win then
				listing.orig_statuscolumn[win] = nil
				listing.winopts[win] = nil
			end
		end,
	})

	-- setup completion
	require("elk.cmp").setup()

	-- setup :Elk start|stop|analytics|listing command
	vim.api.nvim_create_user_command("Elk", M.command, {
		nargs = 1,
		complete = function(arg_lead)
			return vim.tbl_filter(function(cmd)
				return cmd:find("^" .. vim.pesc(arg_lead))
			end, { "start", "stop", "analytics", "listing" })
		end,
	})
end

return M
