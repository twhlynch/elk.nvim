local M = {}

-- stylua: ignore
M.keywords = {
	-- arithmetic
	"add", "and", "not",
	-- branch
	"br", "brn", "brz", "brp", "brnz", "brzp", "brnp", "brnzp",
	-- jump
	"jmp", "ret", "jsr", "jsrr",
	-- load
	"lea", "ld", "ldi", "ldr",
	-- store
	"st", "sti", "str",
	-- trap
	"trap",
	-- stack extension
	"push", "pop", "call", "rets",
	-- traps
	"getc", "out", "puts", "in", "putsp", "halt",
	-- debug extension
	"putn", "reg",
	-- misc
	-- "rti",
	-- elci
	"chat", "getp", "setp", "getb", "setb", "geth",
	-- directive
	".ORIG", ".FILL", ".BLKW", ".STRINGZ", ".END",
	-- registers
	"r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7",
}

local FILETYPES = { asm = true, lc3 = true }

local function is_elk_ft()
	return FILETYPES[vim.bo.filetype] ~= nil
end

--- get keyword matches for a given prefix
--- @param prefix string
--- @return string[]
function M.get_matches(prefix)
	local out = {}
	local prefix_lower = prefix:lower()

	for _, kw in ipairs(M.keywords) do
		if kw:lower():find("^" .. vim.pesc(prefix_lower)) then
			table.insert(out, kw)
		end
	end

	return out
end

--- reusable completion pattern
--- @param content string
--- @param kind integer
--- @return table[]
function M.complete(content, kind)
	if not is_elk_ft() then
		return {}
	end

	local input = content:match("[%w_.]+$") or ""
	local matches = M.get_matches(input)

	local items = {}
	for _, kw in ipairs(matches) do
		table.insert(items, {
			label = kw,
			kind = kind or vim.lsp.protocol.CompletionItemKind.Keyword,
		})
	end

	return items
end

--- omnifunc for Elk keyword completion
--- @param findstart 0 | 1 whether to locate start (1) or return matches (0)
--- @param base string the current completion prefix
--- @return integer | string[] | table[]
function M.omnifunc(findstart, base)
	if findstart == 1 then -- locate start
		local line = vim.api.nvim_get_current_line()
		local col = vim.fn.col(".") - 1

		-- walk backwards to find start of the current word
		-- includes '.' so directives like are handled correctly
		while col > 0 and line:sub(col, col):match("[%w_.]") do
			col = col - 1
		end

		return col
	else -- return matches
		local items = {}

		for _, kw in ipairs(M.get_matches(base)) do
			table.insert(items, {
				word = kw,
				kind = kw:sub(1, 1) == "." and "d" or "k", -- directive vs keyword
				menu = "[elk]",
			})
		end

		return items
	end
end

--- nvim-cmp source
M.cmp_source = {}
M.cmp_source.new = function()
	return setmetatable({}, { __index = M.cmp_source })
end
function M.cmp_source:complete(params, callback)
	callback({
		items = M.complete(params.context.cursor_before_line, require("cmp").types.lsp.CompletionItemKind),
		isIncomplete = false,
	})
end

--- blink source
M.blink_source = {}
M.blink_source.new = function()
	return setmetatable({}, { __index = M.blink_source })
end
function M.blink_source:get_completions(ctx, callback)
	callback({
		items = M.complete(ctx.line:sub(1, ctx.cursor[2])),
		is_incomplete_forward = false,
		is_incomplete_backward = false,
	})
end

--- coq_nvim source
M.coq_source = {}
M.coq_source.new = function()
	return setmetatable({}, { __index = M.coq_source })
end
function M.coq_source:fn(args, callback)
	callback({
		items = M.complete(args.line:sub(1, args.pos[2])),
		isIncomplete = false,
	})
end

--- blink loads this module directly and calls new
M.new = M.blink_source.new

--- called per buffer
function M.setup_file()
	if not is_elk_ft() then
		return
	end
	-- omnifunc requires setting per buffer
	vim.bo.omnifunc = "v:lua.require'elk.cmp'.omnifunc"
end

--- called once
function M.setup()
	-- nvim-cmp requires registering
	local ok_cmp, cmp = pcall(require, "cmp")
	if ok_cmp then
		cmp.register_source("elk", M.cmp_source.new())
	end

	--- coq requires registering sources in a global table
	local ok_coq, _ = pcall(require, "coq")
	if ok_coq then
		local sources = rawget(_G, "COQsources") or {}
		sources["elk"] = M.coq_source.new()
		rawset(_G, "COQsources", sources)
	end
end

return M
