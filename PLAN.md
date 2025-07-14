# Specification

This is the planner neovim plugin.

It binds `<leader> p p` to running the current selection through an LLM to create a better plan.

While the LLM is working, an auto updating placeholder is inserted in the location of the selected text.

## Improvements

### Using extmarks instead of placeholders - DONE

1. Remove current real text placeholder insertion logic
2. Research neovim's virtual text API (`vim.api.nvim_buf_set_extmark`)
   a. Study `nvim_buf_set_extmark` core function and parameters
      - Buffer ID (0 for current buffer)
      - Namespace ID (from `nvim_create_namespace()`)
      - Line and column positioning (0-based)
      - Options table with `virt_text`, `virt_text_pos`, `id`, `ephemeral`
   b. Understand virtual text configuration options
      - `virt_text`: Array of `[text, highlight]` tuples
      - `virt_text_pos`: "eol", "overlay", "inline", "right_align" positioning
      - `virt_text_hide`: Hide when background text is selected
      - `virt_text_win_col`: Fixed window column positioning
   c. Learn namespace management for plugin isolation
      - Create dedicated namespace: `vim.api.nvim_create_namespace('planner')`
      - Use namespace to organize and clean up extmarks
      - Clear namespace: `vim.api.nvim_buf_clear_namespace()`
   d. Test basic virtual text creation at cursor position
      - Get cursor position: `vim.api.nvim_win_get_cursor()`
      - Create simple placeholder text with highlight
      - Verify text appears without affecting buffer content
   e. Implement animated status indicator patterns
      - Create rotating characters: `{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}`
      - Use timer to update virtual text periodically
      - Handle extmark ID reuse for smooth animation
   f. Study extmark cleanup and lifecycle management
      - Delete specific extmarks: `vim.api.nvim_buf_del_extmark()`
      - Handle buffer changes that might affect extmark positions
      - Ensure proper cleanup when LLM processing completes
3. Create virtual text namespace for the planner plugin
4. Implement virtual text placeholder creation at cursor position
5. Add animated/rotating status indicator in virtual text
6. Handle virtual text cleanup when LLM processing completes
7. Test virtual text behavior with cursor movement and buffer edits
8. Ensure virtual text doesn't interfere with normal editing operations

### Aborting running processes - DONE

1. Set up keymap for `<leader> p a` (abort) in plugin setup
2. Implement process tracking system
   a. Create table to map extmark IDs to process PIDs
   b. Store extmark positions and associated process information
   c. Update tracking when new processes start
3. Implement cursor proximity detection for virtual text
   a. Get current cursor position: `vim.api.nvim_win_get_cursor()`
   b. Query extmarks in current buffer: `vim.api.nvim_buf_get_extmarks()`
   c. Check if cursor is within range of any tracked process extmarks
   d. Return matching process info if cursor is adjacent to virtual text
4. Implement process termination logic
   a. Use `vim.loop.kill(pid, signal)` to send SIGTERM to process
   b. Add fallback SIGKILL if process doesn't respond
   c. Handle process cleanup and remove from tracking table
5. Implement virtual text cleanup after abort
   a. Remove extmark: `vim.api.nvim_buf_del_extmark()`
   b. Clear namespace if no other processes running
   c. Remove process from tracking table
6. Add user feedback for abort action
   a. Show "Process aborted" message using `vim.notify()`
   b. Handle cases where no process found at cursor
   c. Display error if process termination fails
7. Test abort functionality
   a. Start process with `<leader> p p`, then abort with `<leader> p a`
   b. Verify process actually terminates and virtual text disappears
   c. Test cursor positioning edge cases (before/after virtual text)
   d. Ensure abort works with multiple concurrent processes

### Showing process output preview - DONE

1. Set up stdout monitoring for the amp process
   a. Modify `vim.loop.spawn()` call to include stdout pipe setup
   b. Set `stdio = {nil, vim.loop.new_pipe(false), nil}` to capture stdout
   c. Store stdout handle reference in process tracking table
   d. Add error handling for pipe creation failures

2. Implement stdout data reading and buffering
   a. Use `stdout:read_start()` to begin reading output stream
   b. Create buffer to accumulate partial output chunks
   c. Handle line-by-line reading vs continuous stream data
   d. Store last received chunk in process tracking table

3. Extract and format last 20 characters of output
   a. Trim whitespace and newlines from raw output chunk
   b. Take last 20 characters: `string.sub(output, -20)`
   c. Handle multi-byte UTF-8 characters properly to avoid truncation
   d. Escape special characters that might break virtual text display
   e. Add ellipsis "..." if output is longer than 20 characters

4. Implement elapsed time tracking for each process
   a. Store start time when process begins: `vim.loop.hrtime()`
   b. Calculate elapsed time in timer callback: `(vim.loop.hrtime() - start_time) / 1e9`
   c. Format time as seconds: `string.format("%.1fs", elapsed)`
   d. Update time display in virtual text every timer tick

5. Create formatted virtual text display string
   a. Combine spinner, time, and output: `spinner .. " Processing (" .. time .. ") " .. output`
   b. Apply syntax highlighting to different components
   c. Handle edge cases: empty output, very long output, special characters
   d. Ensure total display length doesn't exceed reasonable limits

6. Update virtual text with live output preview
   a. Modify existing timer callback to include output preview
   b. Update extmark text with new formatted string each timer tick
   c. Handle case where no output received yet (show just spinner + time)
   d. Ensure virtual text updates smoothly without flicker

7. Handle process completion and cleanup
   a. Stop stdout reading when process exits
   b. Close stdout pipe handle: `stdout:close()`
   c. Remove stdout reference from process tracking table
   d. Final virtual text should show completion status, not preview

8. Test output preview functionality
   a. Verify output appears within 20 character limit
   b. Test with various output patterns (short, long, special chars)
   c. Ensure timer updates smoothly with spinner + time + output
   d. Test edge cases: no output, binary output, very fast output

### Add configuration settings - DONE

1. Define default configuration structure
   a. Create `default_config` table with all configurable options
   b. Set `custom_instructions = ""` for injectable prompt text
   c. Set `log_path = vim.fn.expand("~/.local/state/nvim/planner.log")` with proper path expansion
   d. Set `response_path = vim.fn.expand("~/.local/tmp/planner.txt")` with proper path expansion
   e. Add validation for required directory creation

2. Implement configuration merging in setup function
   a. Accept `opts` parameter in `M.setup(opts)` function
   b. Use `vim.tbl_deep_extend("force", default_config, opts or {})` to merge configs
   c. Store merged config in module-level variable for global access
   d. Validate configuration options and provide helpful error messages

3. Create directory structure for configurable paths
   a. Extract directory from log_path: `vim.fn.fnamemodify(config.log_path, ":h")`
   b. Create directories if they don't exist: `vim.fn.mkdir(dir, "p")`
   c. Handle permission errors and provide fallback paths
   d. Apply same logic for response_path directory creation

4. Integrate custom instructions into LLM prompt
   a. Modify `process_selected_text()` to include custom instructions
   b. Prepend `config.custom_instructions` to the prompt before plan file content
   c. Add newline separation between custom instructions and plan content
   d. Handle empty custom instructions gracefully (skip if empty)

5. Update file I/O operations to use configurable paths
   a. Replace hardcoded `~/.planner.log` with `config.log_path` in logging functions
   b. Replace hardcoded `~/.planner.response` with `config.response_path` in process output
   c. Update all file operations to use configured paths consistently
   d. Ensure proper path expansion and error handling

6. Add configuration validation and error handling
   a. Validate that custom_instructions is a string
   b. Validate that log_path and response_path are valid file paths
   c. Check write permissions for configured directories
   d. Provide meaningful error messages for invalid configurations

7. Document configuration options
   a. Add configuration examples to plugin documentation
   b. Show how to set custom instructions for different use cases
   c. Explain path configuration and default locations
   d. Provide troubleshooting guidance for common configuration issues

8. Test configuration functionality
   a. Test setup with default configuration (no opts provided)
   b. Test with partial configuration override (only some options)
   c. Test with full configuration override (all options specified)
   d. Verify custom instructions appear in LLM prompts correctly
   e. Test file operations use configured paths properly

### Extract operation: Research

The research operation takes the selected text in the context of the given plan and performs detailed technical research: identifying which files will need to change and summarizing the change that needs to be performed in each file.

It should be available under `<leader> p r`
