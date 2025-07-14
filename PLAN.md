# Specification

This is the planner neovim plugin.

It binds `<leader> p p` to running the current selection through an LLM to create a better plan.

While the LLM is working, an auto updating placeholder is inserted in the location of the selected text.

## Improvements

### Using extmarks instead of placeholders

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
