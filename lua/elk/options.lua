local M = {}

--- @class Elk.Options.options plugin options
--- @field binary string path to elk binary
--- @field debounce integer debounce milliseconds in between runs
--- @field filetypes string[] filetypes to attach to
--- @field level "info" | "warn" | "err" minimum diagnostic level to report
--- @field permit string disable diagnostics for this policy set

--- @type Elk.Options.options
M.options = {
	binary = "elk",
	debounce = 50,
	filetypes = { "asm", "lc3" },
	level = "info",
	permit = "",
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

return M
