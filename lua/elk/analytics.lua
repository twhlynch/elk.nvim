local M = {}

--- @alias Elk.Address string hex formatted address

--- @class Elk.Analytics
--- @field time Elk.Analytics.Time
--- @field size integer words the program image spans
--- @field symbols table<string, integer> symbol name to value
--- @field instructions Elk.Analytics.Instructions
--- @field registers Elk.Analytics.Registers
--- @field memory Elk.Analytics.Memory
--- @field io Elk.Analytics.Io

--- @class Elk.Analytics.Time
--- @field total_ns integer
--- @field user_ns integer
--- @field supervisor_ns integer
--- @field io_ns integer

--- @class Elk.Analytics.Instructions
--- @field regular Elk.Analytics.Instructions.Regular
--- @field br Elk.Analytics.Instructions.Br
--- @field trap table<string, integer> trap vector to execution count

--- @class Elk.Analytics.Instructions.Regular
--- @field add integer
--- @field and integer
--- @field not integer
--- @field jmp_ret integer
--- @field jsr_jsrr integer
--- @field lea integer
--- @field ld integer
--- @field ldi integer
--- @field ldr integer
--- @field st integer
--- @field sti integer
--- @field str integer
--- @field rti integer
--- @field reserved integer
--- @field noop integer

--- @class Elk.Analytics.Instructions.Br
--- @field n integer
--- @field z integer
--- @field p integer
--- @field nz integer
--- @field zp integer
--- @field np integer
--- @field nzp integer

--- @class Elk.Analytics.Registers
--- @field read Elk.Analytics.Registers.Registers
--- @field write Elk.Analytics.Registers.Registers

--- @class Elk.Analytics.Registers.Registers
--- @field r0 integer
--- @field r1 integer
--- @field r2 integer
--- @field r3 integer
--- @field r4 integer
--- @field r5 integer
--- @field r6 integer
--- @field r7 integer

--- @class Elk.Analytics.Memory
--- @field read table<Elk.Address, integer>
--- @field write table<Elk.Address, integer>
--- @field execute table<Elk.Address, integer> executed address to execution count

--- @class Elk.Analytics.Io
--- @field read integer
--- @field write integer

--- @class Elk.Analytics.Line
--- @field exec integer
--- @field read integer
--- @field write integer

--- bufnr -> { lines, extra, col }
--- @type table<integer, { lines: table<integer, Elk.Analytics.Line>, extra: table<integer, Elk.Analytics.Line>, col: integer | nil }>
M.data = {}

--- @type integer namespace holding the gutter marks
M.ns = nil
local icon_execute = "×"
local icon_read = ""
local icon_write = ""

--- map analytics addresses to source lines using the latest listing,
--- summing counts when several addresses share one line. a line spanning
--- several addresses maps every address in its span
--- @param bufnr integer
--- @param analytics Elk.Analytics
--- @return table<integer, Elk.Analytics.Line> lines per source line
--- @return table<integer, Elk.Analytics.Line> extra addresses after the line's first
local function to_lines(bufnr, analytics)
	--- @type table<Elk.Address, { lnum: integer, first: boolean }>
	local addr_to_line = {}

	for lnum, entries in pairs(require("elk.listing").data[bufnr] or {}) do
		local addr = entries[1] and entries[1].addr
		local hex = addr and addr:match("^%a(%x+)$")

		if hex ~= nil then
			local base, prefix, width = tonumber(hex, 16), addr:sub(1, #addr - #hex), #hex

			for i = 0, #entries - 1 do
				-- listing addresses are uppercase (x300A), analytics lowercase (x300a)
				local key = (prefix .. string.format("%0" .. width .. "X", base + i)):lower()
				addr_to_line[key] = { lnum = lnum, first = i == 0 }
			end
		end
	end

	--- @type table<integer, Elk.Analytics.Line>
	local lines, extra = {}, {}

	--- @param map table<Elk.Address, integer> | nil
	--- @param key "exec" | "read" | "write"
	local function add(map, key)
		for addr, count in pairs(map or {}) do
			local target = addr_to_line[addr:lower()]

			if target and count > 0 then
				local bucket = target.first and lines or extra
				local stats = bucket[target.lnum]

				if stats == nil then
					stats = { exec = 0, read = 0, write = 0 }
					bucket[target.lnum] = stats
				end

				stats[key] = stats[key] + count
			end
		end
	end

	add(analytics.memory and analytics.memory.execute, "exec")
	add(analytics.memory and analytics.memory.read, "read")
	add(analytics.memory and analytics.memory.write, "write")

	return lines, extra
end

--- gutter marks for a line, as highlight chunks plus their concatenated text
--- @param stats Elk.Analytics.Line
--- @return table chunks
--- @return string text
local function marks(stats)
	local chunks, text = {}, ""
	--- @param str string
	--- @param hl string
	local function add(str, hl)
		text = text .. str
		chunks[#chunks + 1] = { str, hl }
	end

	if stats.exec > 0 then
		add(" " .. icon_execute .. stats.exec, "ElkExecCount")
	end
	if stats.read > 0 then
		add(" " .. icon_read .. stats.read, "ElkExecRead")
	end
	if stats.write > 0 then
		add(" " .. icon_write .. stats.write, "ElkExecWrite")
	end

	return chunks, text
end

--- redraw gutter annotations, then the rows under spanned lines.
--- marks sit at end of line, or at a fixed column past the longest annotated line when they fit on screen
--- @param bufnr integer
local function refresh(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

	local stored = M.data[bufnr]
	if stored == nil then
		return
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	--- @type table<integer, { lnum: integer, chunks: table }>
	local rows = {}
	local width, widest = 0, 0
	for lnum, stats in pairs(stored.lines) do
		if lnum >= 1 and lnum <= line_count then
			local chunks, mark = marks(stats)
			if #chunks > 0 then
				local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
				width = math.max(width, vim.fn.strdisplaywidth(line))
				widest = math.max(widest, vim.fn.strdisplaywidth(mark))
			end
			rows[#rows + 1] = { lnum = lnum, chunks = chunks }
		end
	end

	-- stats on virtual rows sit at the same column, so they count towards the fit
	for lnum, stats in pairs(stored.extra) do
		if lnum >= 1 and lnum <= line_count then
			local _, mark = marks(stats)
			widest = math.max(widest, vim.fn.strdisplaywidth(mark))
		end
	end

	local col
	if widest > 0 then
		local narrowest
		for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
			local win_width = vim.api.nvim_win_get_width(win)
			narrowest = math.min(narrowest or win_width, win_width)
		end
		if narrowest and width + 1 + widest <= narrowest then
			col = width + 1
		end
	end
	stored.col = col

	for _, row in ipairs(rows) do
		if #row.chunks > 0 then
			local opts = { virt_text = row.chunks, virt_text_pos = "eol" }
			if col then
				opts.virt_text_win_col = col
			end
			vim.api.nvim_buf_set_extmark(bufnr, M.ns, row.lnum - 1, 0, opts)
		end
	end

	require("elk.listing").render_virtual(bufnr)
end

--- store per line execution, read and write counts and redraw the gutter.
--- @param bufnr integer
--- @param analytics Elk.Analytics
function M.show(bufnr, analytics)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local lines, extra = to_lines(bufnr, analytics)
	if next(lines) == nil and next(extra) == nil then
		M.clear(bufnr)
		return
	end

	M.data[bufnr] = { lines = lines, extra = extra, col = nil }
	refresh(bufnr)

	local total, count = 0, 0
	for _, stats in pairs(lines) do
		total = total + stats.exec
		count = count + 1
	end
end

--- stats chunks for the row under a spanned line, padded to the column its end of line marks are aligned to
--- @param bufnr integer
--- @param lnum integer
--- @return table|nil chunks
function M.virt_chunks(bufnr, lnum)
	local stored = M.data[bufnr]
	local stats = stored and stored.extra[lnum]

	if stats == nil then
		return nil
	end

	local chunks = marks(stats)
	if #chunks == 0 then
		return nil
	end
	if stored.col then
		chunks[1] = { string.rep(" ", stored.col) .. chunks[1][1], chunks[1][2] }
	end

	return chunks
end

--- clear analytics info for a buffer
--- @param bufnr integer
function M.clear(bufnr)
	M.data[bufnr] = nil

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
	require("elk.listing").render_virtual(bufnr)
end

--- setup highlight groups and namespace
function M.setup()
	M.ns = vim.api.nvim_create_namespace("elk_analytics")

	vim.api.nvim_set_hl(0, "ElkExecCount", { link = "Number", default = true })
	vim.api.nvim_set_hl(0, "ElkExecRead", { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "ElkExecWrite", { link = "DiagnosticHint", default = true })
end

return M
