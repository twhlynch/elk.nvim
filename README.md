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
		binary = "elk", -- path to elk binary
		debounce = 50, -- debounce milliseconds in between runs
		filetypes = { "asm", "lc3" }, -- filetypes to attach to
		level = "info", -- minimum diagnostic level to report
		permit = "", -- disable diagnostics for this policy set
	},
}
```

You may also want to set `lc3` to be used for `.asm` and `.lc3` files somewhere in your config.

```lua
vim.filetype.add({
	extension = {
		asm = "lc3",
		lc3 = "lc3",
	},
})
```
