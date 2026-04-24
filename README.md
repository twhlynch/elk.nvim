# elk.nvim

Diagnostics provider for LC-3 Assembly bridging the Elk LC-3 toolchain.

## Features

- Error and warning diagnostics for LC-3 Assembly files, powered by Elk.
- Automatic diagnostics updates on buffer changes.

## Requirements

Requires [Elk](https://codeberg.org/dxrcy/elk) preinstalled.

## Usage

Example usage for `lazy.nvim`.

```lua
return {
	"twhlynch/elk.nvim",
	opts = {
		-- command or path to elk binary
		binary = "elk",
		-- debounce milliseconds in between runs
		debounce = 50,
		-- filetypes to attach to
		filetypes = { "asm", "lc3" },
		-- minimum diagnostic level to report
		-- "err" to ignore warnings and info, "warn" to ignore info
		level = "info",
		-- disable diagnostics for this policy set
		-- can be a table like { "+laser", "extension.stack_instructions", ... }
		-- or a string like "+laser,extension.stack_instructions"
		-- see https://codeberg.org/dxrcy/elk/src/branch/master/DOCS.md#policies
		permit = {},
		-- override trap aliases to parse
		-- can prevent warnings when using non-standard traps such as for ELCI integration
		-- requires specifying all traps not just new ones
		-- can be a table like { putn = 0x26, reg = 0x27, ... }
		-- or a string like "putn=0x26,reg=0x27,..."
		trap_aliases = nil,
		-- keyword autocomplete for blink, nvim-cmp, coq_nvim, and omnifunc
		-- set to false to disable
		-- for blink, you will need to add "elk" to sources.default and add `elk = { module = "elk.cmp" }` in sources.providers
		completion = true,
	},
}
```

Or `vim.pack`:

```lua
vim.pack.add({
	{
		src = "https://github.com/twhlynch/elk.nvim",
	},
})

require("elk").setup({
	binary = "elk",
	debounce = 50,
	filetypes = { "asm", "lc3" },
	level = "info",
	permit = {},
	trap_aliases = nil,
})
```

You will also need to set `lc3` to be used for `.asm` and `.lc3` files somewhere in your config.

```lua
vim.filetype.add({
	extension = {
		asm = "lc3",
		lc3 = "lc3",
	},
})
```

### ELCI integration (Minecraft)

If you are working with ELCI, set the following `trap_aliases`:

```lua
trap_aliases = {
	-- base LC-3
	getc   = 0x20,
	out    = 0x21,
	puts   = 0x22,
	["in"] = 0x23,
	putsp  = 0x24,
	halt   = 0x25,
	-- debug extensions
	putn   = 0x26,
	reg    = 0x27,
	-- ELCI integration
	chat   = 0x28,
	getp   = 0x29,
	setp   = 0x2a,
	getb   = 0x2b,
	setb   = 0x2c,
	geth   = 0x2d,
}
```
