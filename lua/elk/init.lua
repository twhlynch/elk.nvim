local M = {}

--- plugin setup
--- @param options Elk.Options.options option overrides
function M.setup(options)
	-- set options
	require("elk.options").set(options)

	-- setup rest of plugin
	require("elk.elk").setup()
end

return M
