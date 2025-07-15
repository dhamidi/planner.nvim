# AGENT.md

This is a Neovim Lua plugin for the "planner" tool that enhances markdown planning with LLM integration.

## Build/Test Commands

- `make test` to test

## Architecture & Structure

### Core Components

- **Main module**: `lua/planner/init.lua` - Single-file architecture with all functionality
- **Entry point**: `M.setup()` - Plugin initialization with default and custom config merging
- **Primary function**: `M.process_selected_text()` - Core functionality for LLM processing
- **External dependency**: `amp` CLI tool - Spawned as subprocess for LLM processing

### Configuration System

- **Default config**: Centralized in `default_config` table
  - `custom_instructions`: String for additional prompts
  - `log_path`: `~/.local/state/nvim/planner.log` (user-specific logging)
  - `response_path`: `~/.local/tmp/planner.txt` (temporary response storage)
- **Config merging**: Deep merge of defaults with user options in `M.setup()`
- **Config validation**: Type checking and path validation with directory creation

### Process Management

- **Active processes tracking**: `active_processes` table keyed by PID
- **Process state**: Start time, handles, pipes, extmarks, timers, temporary files
- **Overlap detection**: `check_for_overlaps()` prevents concurrent processing of same region
- **Buffer locking**: `setup_buffer_lock()` prevents editing during processing
- **Process cleanup**: `cleanup_process()` handles resource deallocation

### Visual Selection Handling

- **Multi-mode support**: Character (`v`), line (`V`), and block (`<C-v>`) visual modes
- **Position tracking**: Uses extmarks for persistent region tracking across buffer changes
- **Coordinate conversion**: Handles 0-indexed/1-indexed position conversions
- **Fallback mechanisms**: Graceful handling of invalid visual marks

### User Interface

- **Virtual text feedback**: Spinner animation with elapsed time display
- **Process status**: Real-time updates via timer-based virtual text
- **Log viewing**: `M.show_process_log()` opens floating terminal with `tail -f`
- **Process abortion**: `M.abort_process()` with graceful cleanup

### File I/O & Logging

- **Per-process files**: Unique temporary files for each process instance
- **Structured logging**: Timestamped entries to main log file
- **Process-specific logs**: Separate log files for stdout/stderr per process
- **Automatic cleanup**: Temporary file removal on process completion

### Key Bindings

- **Visual mode**: `<leader>pp` - Process selected text
- **Normal mode**: `<leader>pa` - Abort process at cursor
- **Normal mode**: `<leader>pl` - Show process log at cursor

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
