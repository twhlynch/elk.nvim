local M = {}

--- strips ANSI escape codes from a string
--- @param str string
--- @return string
function M.strip_ansi(str)
	return (string.gsub(str, "\27%[[0-9;]*[a-zA-Z]", ""))
end

--- split string into lines
--- @param str string
--- @return string[]
function M.split_lines(str)
	return vim.split(str, "\n", { plain = true })
end

--- write lines to file
--- @param path string
--- @param lines string[]
--- @return boolean
function M.write_file(path, lines)
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(table.concat(lines, "\n"))
	f:close()
	return true
end

-- debounce timers
local timers = {}

--- per buffer debounce utility
--- @param bufnr integer
--- @param func function
--- @param ... any
function M.start_debounce(bufnr, func, ...)
	local args = { ... }
	local options = require("elk.options").get()

	if timers[bufnr] then
		timers[bufnr]:stop()
	end

	timers[bufnr] = vim.defer_fn(function()
		timers[bufnr] = nil
		func(unpack(args))
	end, options.debounce)
end

--- clear debounce timer for buffer
--- @param bufnr integer
function M.stop_debounce(bufnr)
	if timers[bufnr] then
		timers[bufnr]:stop()
		timers[bufnr] = nil
	end
end

return M
