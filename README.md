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
	"twhlynch/elk.nvim"
	opts = {
		binary = "elk",
		debounce = 400,
		filetypes = { "asm", "lc3" },
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
