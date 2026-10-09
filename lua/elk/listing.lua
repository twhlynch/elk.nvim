local M = {}

local utils = require("elk.utils")

--- @class Elk.Listing
--- @field addr string | nil
--- @field hex string | nil
--- @field binary string | nil

--- @type table<integer, table<integer, Elk.Listing[]>>
M.data = {} --- listing data per buffer
--- @type table<integer, { lines: table<integer, string>, blank: string, virtual: table<integer, string> } | nil>
M.cache = {} --- gutter text per buffer
--- @type integer
M.ns = nil --- virtual text namespace
--- @type table<integer, integer>
M.numwidth = {} --- prerendered digits of the buffer line count
--- @type table<integer, string>
M.orig_statuscolumn = {} --- original statuscolumn per window
--- @type table<integer, { number: boolean, relativenumber: boolean }>
M.winopts = {} --- winid -> { number, relativenumber }

--- @param str string
--- @return string|nil
local function field(str)
	str = vim.trim(str)
	return str ~= "" and str or nil
end

--- parse elk .lst listing output
--- @param lines string[]
--- @return table<integer, Elk.Listing[]>
local function parse(lines)
	--- @type table<integer, Elk.Listing[]>
	local map = {}
	local last_lnum = nil

	for _, line in ipairs(lines) do
		local addr, hex, binary, ln = line:match("^(.-)|(.-)|(.-)|(.-)|")
		if addr then
			addr, hex, binary = field(addr), field(hex), field(binary)
			local lnum = tonumber(ln)
			if lnum then
				last_lnum = lnum
			end
			-- a record without an lnum continues the previous source line
			lnum = lnum or last_lnum
			if lnum and (addr or hex or binary) then
				map[lnum] = map[lnum] or {}
				table.insert(map[lnum], { addr = addr, hex = hex, binary = binary })
			end
		end
	end

	return map
end

--- format a listing entry, padding any column the entry is missing
--- @param entry Elk.Listing|nil
--- @return string
local function format(entry)
	local listing = require("elk.options").get().listing
	local parts = {}

	if listing.address then
		table.insert(parts, utils.pad_right(entry and entry.addr, 5))
	end
	if listing.hex then
		table.insert(parts, utils.pad_right(entry and entry.hex, 5))
	end
	if listing.binary then
		local bin = utils.pad_right(entry and entry.binary, 16)
		table.insert(parts, bin:sub(1, 8) .. " " .. bin:sub(9))
	end

	return table.concat(parts, " ")
end

--- address range a line spans when its listing spans several addresses
--- @param entries Elk.Listing[]
--- @return string|nil range, nil for single address lines
local function span_range(entries)
	local addr = entries[1] and entries[1].addr
	local hex = addr and addr:match("^%a(%x+)$")
	if hex == nil or #entries < 2 then
		return nil
	end
	local last = tonumber(hex, 16) + #entries - 1
	return addr .. "..." .. addr:sub(1, #addr - #hex) .. string.format("%0" .. #hex .. "X", last)
end

--- listing text for a line, prerendered in show(). hot path: runs per line
--- per redraw, so it stays a pure table lookup with no vim.* calls. wrapped
--- rows stay blank, the row under a spanned line shows its address range
--- @param bufnr integer
--- @param lnum integer
--- @param virtnum integer v:virtnum, 0 on a real line
--- @return string
function M.listing_only(bufnr, lnum, virtnum)
	if virtnum > 0 then
		return ""
	end
	local cache = M.cache[bufnr]
	if cache == nil then
		return ""
	end
	if virtnum < 0 then
		return cache.virtual[lnum] or ""
	end
	return cache.lines[lnum] or cache.blank
end

--- ascii padding without the vim.fn round trip, for the statuscolumn hot path
--- @param str string digits, ascii only
--- @param width integer
--- @param left boolean pad on the left when true
--- @return string
local function pad_num(str, width, left)
	if #str >= width then
		return str
	end
	local pad = string.rep(" ", width - #str)
	if left then
		return pad .. str
	end
	return str .. pad
end

--- number column text respecting 'number' and 'relativenumber', built from
--- prerendered widths and cached window flags (no vim.* on the hot path).
--- wrapped and virtual rows show nothing, matching the default columns
--- @param winid integer evaluating window
--- @param bufnr integer line's buffer
--- @param lnum integer absolute line number
--- @param relnum integer relative line number
--- @param virtnum integer v:virtnum, 0 on a real line
--- @return string
function M.number_only(winid, bufnr, lnum, relnum, virtnum)
	if virtnum ~= 0 then
		return ""
	end
	local opts = M.winopts[winid]
	if opts == nil then
		return ""
	end
	local width = M.numwidth[bufnr] or 4
	if opts.relativenumber then
		if relnum == 0 then
			-- the current line shows its absolute number when both are set
			return pad_num(opts.number and tostring(lnum) or "0", width, false)
		end
		return pad_num(tostring(relnum), width, true)
	end
	if opts.number then
		return tostring(lnum)
	end
	return ""
end

--- record a window's number options for render time use
--- @param win integer
function M.record_winopts(win)
	M.winopts[win] = { number = vim.wo[win].number, relativenumber = vim.wo[win].relativenumber }
end

--- marker for our statuscolumn format
local marker = "ElkListing.listing_only(bufnr("

--- ensure a window shows the listing gutter, restoring it when the listing
--- is off or its buffer has nothing to show
--- @param win integer
function M.ensure(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local options = require("elk.options").get().listing
	local bufnr = vim.api.nvim_win_get_buf(win)
	if not options.enabled or not utils.has(M.data, bufnr) then
		M.restore(win)
		return
	end

	M.record_winopts(win)
	local cur = vim.wo[win].statuscolumn
	if cur:find(marker, 1, true) then
		return
	end

	M.orig_statuscolumn[win] = cur
	if cur == "" then
		vim.wo[win].statuscolumn = "%C%s%#ElkListing#%{v:lua.ElkListing.listing_only(bufnr(),v:lnum,v:virtnum)}%* %{v:lua.ElkListing.number_only(win_getid(),bufnr(),v:lnum,v:relnum,v:virtnum)} "
	else
		vim.wo[win].statuscolumn = "%#ElkListing#%{v:lua.ElkListing.listing_only(bufnr(),v:lnum,v:virtnum)}%* " .. cur
	end
end

--- restore a windows original statuscolumn
--- @param win integer
function M.restore(win)
	if not vim.api.nvim_win_is_valid(win) then
		M.orig_statuscolumn[win] = nil
		return
	end

	local cur = vim.wo[win].statuscolumn
	if not cur:find(marker, 1, true) then
		return
	end

	vim.wo[win].statuscolumn = M.orig_statuscolumn[win] or ""
	M.orig_statuscolumn[win] = nil
end

--- redraw the statuscolumn of every window showing a buffer
--- @param bufnr integer
local function redraw(bufnr)
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		if not pcall(vim.api.nvim__redraw, { win = win, valid = true, statuscolumn = true }) then
			vim.cmd("redraw!") -- nvim__redraw is experimental
			return
		end
	end
end

--- show the gutter in every window displaying a buffer, then redraw it
--- @param bufnr integer
local function refresh(bufnr)
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		M.ensure(win)
	end

	redraw(bufnr)
end

--- prerender gutter strings and number width from a buffers listing data.
--- @param bufnr integer
--- @param map table<integer, Elk.Listing[]>
local function build_cache(bufnr, map)
	M.numwidth[bufnr] = #tostring(vim.api.nvim_buf_line_count(bufnr))

	if next(map) == nil then
		M.cache[bufnr] = nil
		return
	end

	local rendered, virtual = {}, {}
	for lnum, entries in pairs(map) do
		rendered[lnum] = format(entries[1])
		local range = span_range(entries)
		if range ~= nil then
			virtual[lnum] = range
		end
	end

	M.cache[bufnr] = { lines = rendered, blank = format(nil), virtual = virtual }
end

--- draw the row under each spanned source line, carrying any stats its extra addresses collected
--- @param bufnr integer
function M.render_virtual(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

	local cache = M.cache[bufnr]
	if cache == nil or not require("elk.options").get().listing.enabled then
		return
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local analytics = require("elk.analytics")
	for lnum in pairs(cache.virtual) do
		if lnum <= line_count then
			vim.api.nvim_buf_set_extmark(bufnr, M.ns, lnum - 1, 0, { virt_lines = { analytics.virt_chunks(bufnr, lnum) or {} } })
		end
	end
end

--- flip the listing gutter on and off for every window
function M.toggle()
	local options = require("elk.options")
	options.set({ listing = { enabled = not options.get().listing.enabled } })

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		M.ensure(win)
	end

	for bufnr in pairs(M.data) do
		M.render_virtual(bufnr)
	end
end

--- show listing info left of the line numbers. data is always stored
--- (analytics maps through it); display honors options.listing.enabled
--- @param bufnr integer
--- @param lines string[]
function M.show(bufnr, lines)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local map = parse(lines)
	M.data[bufnr] = map
	build_cache(bufnr, map)
	refresh(bufnr)
	M.render_virtual(bufnr)
end

--- clear listing info for a buffer
--- @param bufnr integer
function M.clear(bufnr)
	M.data[bufnr] = nil
	M.cache[bufnr] = nil
	M.numwidth[bufnr] = nil

	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
	end

	redraw(bufnr)
end

--- setup highlight group and namespace
function M.setup()
	M.ns = vim.api.nvim_create_namespace("elk_listing_virtual")
	vim.api.nvim_set_hl(0, "ElkListing", { link = "LineNr", default = true })
	-- make global since require is too slow
	_G.ElkListing = M

	for bufnr, map in pairs(M.data) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			build_cache(bufnr, map)
			M.render_virtual(bufnr)
		else
			M.data[bufnr] = nil
			M.cache[bufnr] = nil
			M.numwidth[bufnr] = nil
		end
	end
end

return M
