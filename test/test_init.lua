local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'test/minimal_init.lua' })
      -- Ensure the plugin is in the runtime path for the child process
      child.lua("vim.opt.rtp:prepend(vim.fn.fnamemodify(vim.fn.getcwd(), ':h'))")
    end,
    post_once = child.stop,
  },
})

T['setup() - loads without errors'] = function()
  local success = child.lua_get("pcall(function() local planner = require('planner') planner.setup() return true end)")
  MiniTest.expect.equality(success, true)
end

T['setup() - registers keymap'] = function()
  child.lua("require('planner').setup()")
  local keymap_exists = child.lua_get("vim.fn.mapcheck('<leader>pp', 'v') ~= ''")
  MiniTest.expect.equality(keymap_exists, true)
end

T['setup() - module structure'] = function()
  child.lua("require('planner').setup()")
  local has_process_function = child.lua_get("type(require('planner').process_selected_text) == 'function'")
  MiniTest.expect.equality(has_process_function, true)
end

T['setup() - multiple calls safe'] = function()
  local success = child.lua_get("pcall(function() local planner = require('planner') planner.setup() planner.setup() planner.setup() return true end)")
  MiniTest.expect.equality(success, true)
end

T['setup() - keymap not in normal mode'] = function()
  child.lua("require('planner').setup()")
  local keymap_normal = child.lua_get("vim.fn.mapcheck('<leader>pp', 'n') ~= ''")
  local keymap_insert = child.lua_get("vim.fn.mapcheck('<leader>pp', 'i') ~= ''")
  MiniTest.expect.equality(keymap_normal, false)
  MiniTest.expect.equality(keymap_insert, false)
end

T['plugin loads without errors'] = function()
  local no_errors = child.lua_get("pcall(function() vim.v.errmsg = '' local planner = require('planner') return vim.v.errmsg == '' end)")
  MiniTest.expect.equality(no_errors, true)
end

return T
