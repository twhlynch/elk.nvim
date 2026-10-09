local M = {}

--- @class Elk.Options.options plugin options
--- @field binary string path to elk binary
--- @field debounce integer debounce milliseconds in between runs
--- @field filetypes string[] filetypes to attach to
--- @field level "info" | "warn" | "err" minimum diagnostic level to report
--- @field permit string | string[] disable diagnostics for this policy set
--- @field trap_aliases string | table<string, integer> | nil override trap aliases to parse
--- @field completion boolean enable keyword completion
--- @field listing Elk.Options.listing listing display options

--- @class Elk.Options.listing
--- @field enabled boolean show listing info left of line numbers
--- @field address boolean show address column
--- @field hex boolean show hex column
--- @field binary boolean show binary column

--- @type Elk.Options.options
M.options = {
	binary = "elk",
	debounce = 50,
	filetypes = { "asm", "lc3" },
	level = "info",
	permit = {},
	trap_aliases = nil,
	completion = true,
	listing = {
		enabled = true,
		address = true,
		hex = true,
		binary = true,
	},
}

--- sets plugin options keeping defaults if unspecified
--- @param opts? Elk.Options.options new options to override defaults
function M.set(opts)
	M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

--- get current options
--- @return Elk.Options.options
function M.get()
	return M.options
end

local function is_string_list(t)
	if type(t) ~= "table" then
		return false
	end
	for _, v in ipairs(t) do
		if type(v) ~= "string" then
			return false
		end
	end
	return true
end

local function is_string_int_table(t)
	if type(t) ~= "table" then
		return false
	end
	for k, v in pairs(t) do
		if type(k) ~= "string" then
			return false
		end
		if type(v) ~= "number" or v % 1 ~= 0 then
			return false
		end
	end
	return true
end

--- validate the config
---@return boolean
function M.validate()
	--- @param message string
	local function error(message)
		vim.notify("[elk] " .. message, vim.log.levels.ERROR)
		return false
	end

	-- validate types
	if type(M.options.binary) ~= "string" then
		return error("option 'binary' must be a string")
	end

	if type(M.options.debounce) ~= "number" then
		return error("option 'debounce' must be a number")
	end

	if type(M.options.filetypes) ~= "table" then
		return error("option 'filetypes' must be a list of strings")
	end
	for _, ft in ipairs(M.options.filetypes) do
		if type(ft) ~= "string" then
			return error("option 'filetypes' must be a list of strings")
		end
	end

	if not vim.tbl_contains({ "info", "warn", "err" }, M.options.level) then
		return error("option 'level' must be one of 'info', 'warn', or 'err'")
	end

	if --
		type(M.options.permit) ~= "string" --
		and not is_string_list(M.options.permit)
	then
		return error("option 'permit' must be a string or a string[]")
	end

	if --
		M.options.trap_aliases ~= nil
		and type(M.options.trap_aliases) ~= "string"
		and not is_string_int_table(M.options.trap_aliases)
	then
		return error("option 'trap_aliases' must be a string or a table<string, int>")
	end

	if type(M.options.completion) ~= "boolean" then
		return error("option 'completion' must be a boolean")
	end

	if type(M.options.listing) ~= "table" then
		return error("option 'listing' must be a table")
	end

	if type(M.options.listing.enabled) ~= "boolean" then
		return error("option 'listing.enabled' must be a boolean")
	end

	if type(M.options.listing.address) ~= "boolean" then
		return error("option 'listing.address' must be a boolean")
	end

	if type(M.options.listing.hex) ~= "boolean" then
		return error("option 'listing.hex' must be a boolean")
	end

	if type(M.options.listing.binary) ~= "boolean" then
		return error("option 'listing.binary' must be a boolean")
	end

	-- validate binary exists
	if vim.fn.executable(M.options.binary) == 0 then
		return error("option 'binary' must be a valid executable")
	end

	return true
end

return M
