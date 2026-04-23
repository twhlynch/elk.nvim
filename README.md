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
		-- e.g., "+laser,extension.stack_instructions"
		-- see https://codeberg.org/dxrcy/elk/src/branch/master/lib/policies.zig
		permit = "",
	},
}
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
