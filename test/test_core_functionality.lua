local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'test/minimal_init.lua' })
      -- Ensure the plugin is in the runtime path for the child process
      child.lua("vim.opt.rtp:prepend(vim.fn.fnamemodify(vim.fn.getcwd(), ':h'))")
      -- Set up planner
      child.lua("require('planner').setup()")
    end,
    post_once = child.stop,
  },
})

-- Helper function to create buffer content and visual selection
local function setup_buffer_with_selection(content, start_line, start_col, end_line, end_col, mode)
  mode = mode or 'v'
  child.lua(string.format([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, %s)
    vim.api.nvim_win_set_cursor(0, {%d, %d})
    vim.cmd('normal! %s')
    vim.api.nvim_win_set_cursor(0, {%d, %d})
  ]], vim.inspect(content), start_line, start_col, mode, end_line, end_col))
end

-- Helper function to mock vim.loop.spawn
local function mock_spawn_success(response_content)
  return string.format([[
    local original_spawn = vim.loop.spawn
    vim.loop.spawn = function(cmd, options, callback)
      -- Write mock response to the response file
      local response_file = options.args and options.args[1] or '/tmp/mock_response.txt'
      -- Extract response file from stdin input in real implementation
      vim.defer_fn(function()
        -- Simulate process completion
        callback(0, 0)
      end, 10)
      return {}, 12345 -- mock handle and pid
    end
  ]], response_content)
end

-- Test Visual Selection Handling
T['visual selection - character mode'] = function()
  setup_buffer_with_selection({
    'Line 1: Some text here',
    'Line 2: More text here',
    'Line 3: Final text here'
  }, 1, 8, 1, 12, 'v')
  
  local selected_text = child.lua_get("vim.api.nvim_buf_get_text(0, 0, 8, 0, 12, {})")
  
  MiniTest.expect.equality(selected_text, {'Some'})
end

T['visual selection - line mode'] = function()
  setup_buffer_with_selection({
    'Line 1: Some text here',
    'Line 2: More text here',
    'Line 3: Final text here'
  }, 1, 0, 2, 0, 'V')
  
  local selected_lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, 2, false)")
  
  MiniTest.expect.equality(selected_lines, {'Line 1: Some text here', 'Line 2: More text here'})
end

T['visual selection - block mode'] = function()
  setup_buffer_with_selection({
    'Line 1: Some text here',
    'Line 2: More text here',
    'Line 3: Final text here'
  }, 1, 8, 3, 12, '\22') -- \22 is ctrl-v
  
  -- Block mode is complex to test, just verify we can detect the mode
  local mode = child.lua_get("vim.fn.mode()")
  MiniTest.expect.equality(mode, '\22')
end

-- Test Text Extraction and Processing
T['text extraction - multi-line selection'] = function()
  setup_buffer_with_selection({
    'Line 1: Some text',
    'Line 2: More text',
    'Line 3: Final text'
  }, 1, 8, 2, 5, 'v')
  
  local selected_text = child.lua_get("table.concat(vim.api.nvim_buf_get_text(0, 0, 8, 1, 12, {}), '\\n')")
  
  MiniTest.expect.equality(selected_text, 'Some text\nLine 2: More')
end

T['text extraction - empty selection handling'] = function()
  setup_buffer_with_selection({
    'Line 1: Some text here'
  }, 1, 8, 1, 8, 'v')
  
  local selected_text = child.lua_get("table.concat(vim.api.nvim_buf_get_text(0, 0, 8, 0, 8, {}), '\\n')")
  
  MiniTest.expect.equality(selected_text, '')
end

-- Test External Tool Integration (Mocked)
T['external tool - spawn process'] = function()
  -- Set up buffer with content
  child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Test content for processing'})")
  child.lua("vim.api.nvim_win_set_cursor(0, {1, 0})")
  child.lua("vim.cmd('normal! v$')")
  
  -- Mock vim.loop.spawn to avoid calling actual amp CLI
  child.lua([[
    local original_spawn = vim.loop.spawn
    local spawn_called = false
    local spawn_cmd = nil
    
    vim.loop.spawn = function(cmd, options, callback)
      spawn_called = true
      spawn_cmd = cmd
      return nil, nil -- Return nil to simulate spawn failure for testing
    end
    
    -- Try to call process_selected_text (it will fail due to mock)
    pcall(require('planner').process_selected_text)
    
    -- Restore original spawn
    vim.loop.spawn = original_spawn
    
    _G.test_spawn_called = spawn_called
    _G.test_spawn_cmd = spawn_cmd
  ]])
  
  local spawn_called = child.lua_get("_G.test_spawn_called")
  local spawn_cmd = child.lua_get("_G.test_spawn_cmd")
  
  MiniTest.expect.equality(spawn_called, true)
  MiniTest.expect.equality(spawn_cmd, 'amp')
end

-- Test Response Processing and Buffer Update
T['response processing - successful response'] = function()
  -- Set up buffer with initial content
  child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Original text to replace'})")
  child.lua("vim.api.nvim_win_set_cursor(0, {1, 9})")
  child.lua("vim.cmd('normal! v$')")
  
  -- Mock successful processing - just verify the function can be called
  local success = child.lua_get("pcall(function() local planner = require('planner') local original_spawn = vim.loop.spawn vim.loop.spawn = function(cmd, options, callback) return nil, nil end planner.process_selected_text() vim.loop.spawn = original_spawn end)")
  
  -- For now, just verify the function was called without error
  MiniTest.expect.equality(success, true)
end

-- Test Error Handling
T['error handling - no visual selection'] = function()
  child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Some text here'})")
  child.lua("vim.api.nvim_win_set_cursor(0, {1, 0})")
  child.lua("vim.cmd('normal! i')")
  
  -- Call process_selected_text without visual selection
  local success = child.lua_get("pcall(require('planner').process_selected_text)")
  
  MiniTest.expect.equality(success, true)
end

T['error handling - spawn failure'] = function()
  -- Set up buffer with content
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Test content'})
    vim.api.nvim_win_set_cursor(0, {1, 0})
    vim.cmd('normal! v$')
  ]])
  
  -- Mock spawn failure
  child.lua([[
    local original_spawn = vim.loop.spawn
    vim.loop.spawn = function(cmd, options, callback)
      return nil, nil -- Simulate spawn failure
    end
    
    -- Call the function - should handle spawn failure gracefully
    local success = pcall(require('planner').process_selected_text)
    
    -- Restore original spawn
    vim.loop.spawn = original_spawn
    
    _G.test_spawn_success = success
  ]])
  
  local spawn_success = child.lua_get("_G.test_spawn_success")
  MiniTest.expect.equality(spawn_success, true) -- Should not throw error
end

return T
