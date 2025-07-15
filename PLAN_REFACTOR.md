# Refactoring

1. **Extract process management logic into separate module**
   - Create `lua/planner/process_manager.lua`
   - Move process spawning, tracking, and cleanup logic from `process_selected_text()`
   - Move active_processes table and related functions

2. **Extract visual selection handling into utility module**
   - Create `lua/planner/selection_utils.lua`
   - Move visual mode detection and coordinate conversion logic
   - Simplify the complex selection handling in lines 88-149

3. **Extract LLM prompt generation into separate module**
   - Create `lua/planner/prompt_builder.lua`
   - Move `prepare_llm_prompt()` function and related formatting logic
   - Make prompt templates more configurable

4. **Extract UI feedback system into separate module**
   - Create `lua/planner/ui_feedback.lua` with core UI feedback functionality
   - Move spinner animation system (lines 19-22: spinner_frames, spinner_index)
   - Move namespace creation for virtual text (line 17: namespace creation)
   - Move `generate_preview()` function (lines 53-74: stdout data processing into preview text)
   - Create spinner animation management functions
     - `create_spinner()` - Initialize spinner state
     - `update_spinner()` - Advance spinner frame and return current frame
     - `reset_spinner()` - Reset spinner to first frame
   - Move extmark management functionality
     - `create_progress_indicator()` - Create initial extmark with spinner
     - `update_progress_indicator()` - Update extmark with new spinner/time/preview
     - `remove_progress_indicator()` - Clean up extmark
   - Move virtual text formatting logic (lines 339-362: display text building)
   - Create unified progress display system
     - `format_progress_text()` - Format elapsed time, spinner, and preview into display text
     - `calculate_elapsed_time()` - Convert hrtime to formatted string
     - `format_preview_text()` - Add ellipsis handling for truncated previews
   - Move timer-based UI update system (lines 319-365: timer setup and update logic)
   - Create process visualization utilities
     - `find_extmark_at_cursor()` - Locate extmark at cursor position
     - `cleanup_all_indicators()` - Remove all active progress indicators
   - Expose clean API to main module
     - `start_progress_indicator(bufnr, position, pid)` - Start showing progress
     - `stop_progress_indicator(pid)` - Stop and clean up progress display
     - `update_progress_preview(pid, preview_data)` - Update preview text from stdout
5. **Simplify the main `process_selected_text()` function**
   - Reduce from 278 lines to orchestration logic only
   - Use extracted modules for each major responsibility
   - Improve error handling and edge case management

6. **Extract logging functionality into utility module**
   - Create `lua/planner/logger.lua`
   - Move log function and add structured logging levels
   - Make log formatting more consistent

7. **Improve configuration validation and defaults**
   - Extract config validation into separate function
   - Add more robust path validation
   - Make default paths more predictable

8. **Extract file I/O operations into utility module**
   - Create `lua/planner/file_utils.lua`
   - Move response file reading/writing logic
   - Add better error handling for file operations

9. **Reduce code duplication in process cleanup**
   - Create shared cleanup function used by both completion and abort paths
   - Consolidate timer, pipe, and extmark cleanup logic

10. **Improve error handling and edge cases**
    - Add better error messages for common failure scenarios
    - Improve handling of invalid visual selections
    - Add timeout mechanism for long-running processes
