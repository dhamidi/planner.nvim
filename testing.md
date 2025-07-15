## Testing Plan Based on publish.md Analysis

### Research Results

The publish.md file contains a comprehensive specification for preparing a Neovim plugin for publishing, including detailed mini.test framework implementation with concrete test files, GitHub Actions workflow, and quality assurance guidelines.

### Critical Test Cases (5 Essential Tests)

1. **Plugin Setup and Initialization Test**

   **1.1 Test Environment Setup**
   - Create `test/minimal_init.lua` with mini.test dependency loading
   - Set up isolated test environment with custom XDG directories
   - Configure mini.test framework with proper test runner setup

   **1.2 Core Setup Function Test**
   - Test `require('planner').setup()` executes without errors
   - Verify setup() function returns expected values or nil
   - Test multiple calls to setup() don't cause conflicts
   - Create test in `test/test_init.lua` using `MiniTest.new_child_neovim()`

   **1.3 Keymap Registration Test**
   - Verify `<leader>pp` keymap is registered in visual mode only
   - Test keymap exists using `vim.fn.mapcheck('<leader>pp', 'v') ~= ''`
   - Verify keymap is not registered in normal/insert modes
   - Test keymap calls correct function: `process_selected_text()`

   **1.4 Plugin Loading Test**
   - Test plugin loads without errors in minimal Neovim environment
   - Use `child.restart({ '-u', 'test/minimal_init.lua' })` for isolation
   - Verify no error messages in `v:errmsg` after plugin load
   - Test plugin module structure is accessible via `require('planner')`

   **1.5 Module Structure Validation**
   - Test all expected functions exist in planner module
   - Verify `process_selected_text()` function is available
   - Test `log_message()` utility function exists and works
   - Validate module returns proper table structure

   **1.6 Test Implementation in test/test_init.lua**

   ```lua
   local MiniTest = require('mini.test')
   local child = MiniTest.new_child_neovim()
   
   local T = MiniTest.new_set({
     hooks = {
       pre_case = function()
         child.restart({ '-u', 'test/minimal_init.lua' })
       end,
       post_once = child.stop,
     },
   })
   
   T['setup() - loads without errors'] = function()
     local success = child.lua_get([[
       local ok, planner = pcall(require, 'planner')
       if not ok then return false end
       local setup_ok = pcall(planner.setup)
       return setup_ok
     ]])
     MiniTest.expect.equality(success, true)
   end
   
   T['setup() - registers keymap'] = function()
     child.lua([[require('planner').setup()]])
     local keymap_exists = child.lua_get([[vim.fn.mapcheck('<leader>pp', 'v') ~= '']])
     MiniTest.expect.equality(keymap_exists, true)
   end
   
   T['setup() - module structure'] = function()
     child.lua([[require('planner').setup()]])
     local has_process_function = child.lua_get([[
       local planner = require('planner')
       return type(planner.process_selected_text) == 'function'
     ]])
     MiniTest.expect.equality(has_process_function, true)
   end
   ```

2. **Core Functionality Test - Text Processing**
   - Test `process_selected_text()` with visual selection
   - Mock amp CLI response and verify buffer content replacement
   - Verify selected text is properly passed to external amp tool

3. **File I/O Operations Test**
   - Test logging functionality to `~/.planner.log`
   - Verify response file handling at `~/.planner.response`
   - Test error handling when files can't be written/read

4. **External Dependency Integration Test**
   - Test amp CLI tool availability and execution
   - Verify proper error handling when amp CLI is missing
   - Test process spawning with `vim.loop` and async operations

5. **Plugin Manager Compatibility Test**
   - Test installation with lazy.nvim structure
   - Verify plugin loads correctly in different plugin managers
   - Test that required directories (lua/planner/, plugin/) exist and work

### Additional Quality Assurance Tests

6. **Buffer State Management Test**
   - Test visual mode selection handling (v, V, ctrl-v)
   - Verify cursor position preservation after processing
   - Test undo/redo functionality after text replacement

7. **Error Handling and Edge Cases**
   - Test behavior with empty selection
   - Test network/CLI timeout scenarios
   - Test malformed response handling
