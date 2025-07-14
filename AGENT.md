# AGENT.md

This is a Neovim Lua plugin for the "planner" tool that enhances markdown planning with LLM integration.

## Build/Test Commands
- No build system (pure Lua plugin)
- No formal test suite - test by loading in Neovim
- Manual testing: Use `<leader>pp` in visual mode on selected text in a markdown buffer

## Architecture & Structure
- **Main module**: `lua/planner/init.lua` - Core plugin functionality
- **Entry point**: `M.setup()` function for plugin configuration
- **Key function**: `M.process_selected_text()` - Processes visual selection through LLM
- **External dependency**: `amp` CLI tool for LLM processing
- **File I/O**: Uses `~/.planner.response` for LLM output and `~/.planner.log` for logging

## Code Style Guidelines
- **Lua conventions**: Use `local M = {}` module pattern, return M at end
- **Naming**: snake_case for functions and variables, descriptive names
- **Error handling**: Log errors to `~/.planner.log`, graceful fallbacks
- **Async patterns**: Use `vim.loop` for process spawning, `vim.schedule` for UI updates
- **Buffer operations**: Use `vim.api.nvim_buf_*` functions for text manipulation
- **Visual mode**: Handle different modes (v, V, ctrl-v) with proper position conversion
- **Logging**: Structured logging with timestamps for debugging
- **Process management**: Track active processes with PID-based placeholders
- **Keymap setup**: Use `vim.keymap.set()` with descriptive options
