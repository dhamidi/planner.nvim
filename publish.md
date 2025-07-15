# Specification: prepare plugin for publishing

Research findings for neovim plugin publishing:

## Essential Plugin Structure

- **`lua/planner/`**: Main plugin code directory
  - `init.lua`: Core plugin functionality with setup() function
- **`plugin/`**: Auto-loaded Neovim files
  - `planner.lua`: Global commands and keymaps
- **`README.md`**: Installation and usage instructions
- **`LICENSE`**: Distribution terms (MIT recommended)
- **`.gitignore`**: Exclude unnecessary files

## Installation Methods Research

- **Plugin Manager Support**: Must support lazy.nvim, packer.nvim, vim-plug
- **LuaRocks Publishing**: Optional but recommended using luarocks-tag-release
- **GitHub Releases**: Tag-based versioning (v1.0.0, v1.0.1, etc.)

## README Requirements

- Clear plugin description and features
- Installation instructions for multiple plugin managers:

  ```lua
  -- lazy.nvim
  { "dhamidi/planner.nvim" }
  
  -- packer.nvim
  use "dhamidi/planner.nvim"
  ```

- Setup and configuration examples
- Usage examples with keymaps
- Requirements (amp CLI dependency)

## Publishing Steps

1. **Structure validation**: Ensure standard lua/plugin directories exist
2. **Documentation**: Write comprehensive README with examples
3. **Testing**: Manual testing with `<leader>pp` keymap
4. **Versioning**: Create git tags for releases (v1.0.0)
5. **Distribution**: Submit to awesome-neovim list for discoverability
6. **LuaRocks**: Optional publishing via luarocks-tag-release tool

## Quality Assurance

- Add `.luacheckrc` for static analysis
- Include `stylua.toml` for code formatting
- Document external dependencies (amp CLI tool)
- Provide clear error handling and logging

## Unit Testing for Neovim Plugins

### Testing Framework Options

Rewrite these to work with mini.test conretely - step-by-step mentioning concrete files

#### Mini.test Framework Implementation (Recommended)

**Step 1: Install mini.test dependency**

- Add to `test/minimal_init.lua`:

```lua
local path_package = vim.fn.stdpath('data') .. '/site/'
local mini_path = path_package .. 'pack/deps/start/mini.test'
if not vim.loop.fs_stat(mini_path) then
  vim.fn.system({'git', 'clone', '--filter=blob:none', 'https://github.com/echasnovski/mini.test', mini_path})
end
vim.opt.rtp:prepend(mini_path)
```

**Step 2: Create test runner script**

- Create `test/run_tests.lua`:

```lua
vim.opt.rtp:prepend('.')
vim.opt.rtp:prepend('./test')

require('minimal_init')
local MiniTest = require('mini.test')

MiniTest.setup({
  execute = {
    reporter = MiniTest.gen_reporter.stdout(),
    stop_on_error = false,
  },
  collect = {
    find_files = function() return vim.fn.glob('test/test_*.lua', true, true) end,
    filter_cases = function(cases) return cases end,
  },
})

MiniTest.run()
```

**Step 3: Create concrete test files**

- `test/test_init.lua`:

```lua
local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'test/minimal_init.lua' })
      child.lua([[require('planner').setup()]])
    end,
    post_once = child.stop,
  },
})

T['setup()'] = function()
  child.lua([[require('planner').setup()]])
  local keymap_exists = child.lua_get([[vim.fn.mapcheck('<leader>pp', 'v') ~= '']])
  MiniTest.expect.equality(keymap_exists, true)
end

T['process_selected_text()'] = function()
  -- Create test buffer with content
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Test content', 'More content'})
    vim.api.nvim_win_set_cursor(0, {1, 0})
    vim.cmd('normal! vj')
  ]])
  
  -- Mock amp CLI response
  child.lua([[
    vim.fn.writefile({'Processed: Test content\nMore content'}, os.getenv('HOME') .. '/.planner.response')
  ]])
  
  child.lua([[require('planner').process_selected_text()]])
  
  -- Verify buffer content was updated
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  MiniTest.expect.equality(#lines, 2)
end

return T
```

- `test/test_utils.lua`:

```lua
local MiniTest = require('mini.test')

local T = MiniTest.new_set()

T['log_message()'] = function()
  local planner = require('planner')
  local log_file = os.getenv('HOME') .. '/.planner.log'
  
  -- Clear existing log
  vim.fn.writefile({}, log_file)
  
  planner.log_message('Test message')
  
  local log_content = vim.fn.readfile(log_file)
  MiniTest.expect.equality(#log_content, 1)
  MiniTest.expect.match(log_content[1], 'Test message')
end

return T
```

**Step 4: Create test configuration**

- Create `test/.busted`:

```lua
return {
  default = {
    verbose = true,
    output = 'plainTerminal',
    pattern = 'test_.*%.lua$',
    ROOT = {'.'},
    recursive = true,
  }
}
```

**Step 5: Add test runner to Makefile**

- Create `Makefile`:

```makefile
.PHONY: test
test:
 nvim --headless --noplugin -u test/minimal_init.lua -c "luafile test/run_tests.lua" -c "qa!"

.PHONY: test-watch
test-watch:
 find . -name "*.lua" | entr -c make test
```

**Step 6: GitHub Actions workflow**

- Create `.github/workflows/test.yml`:

```yaml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Neovim
        uses: rhymond/setup-neovim@v1
        with:
          neovim-version: stable
      - name: Run tests
        run: make test
```

**Step 7: Test isolation setup**

- Create `test/helpers.lua`:

```lua
local M = {}

function M.setup_test_env()
  -- Set XDG directories for isolation
  vim.env.XDG_CONFIG_HOME = vim.fn.tempname()
  vim.env.XDG_DATA_HOME = vim.fn.tempname()
  vim.env.XDG_CACHE_HOME = vim.fn.tempname()
  
  -- Create temp directories
  vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, 'p')
  vim.fn.mkdir(vim.env.XDG_DATA_HOME, 'p')
  vim.fn.mkdir(vim.env.XDG_CACHE_HOME, 'p')
end

function M.cleanup_test_env()
  vim.fn.delete(vim.env.XDG_CONFIG_HOME, 'rf')
  vim.fn.delete(vim.env.XDG_DATA_HOME, 'rf')
  vim.fn.delete(vim.env.XDG_CACHE_HOME, 'rf')
end

return M
```

**Step 8: Run tests**

```bash
# Run all tests
make test

# Run specific test file
nvim --headless -u test/minimal_init.lua -c "lua require('mini.test').run_file('test/test_init.lua')" -c "qa!"

# Watch mode for development
make test-watch
```

### Best Practices

#### Test Organization

- **Unit tests**: Test individual Lua modules in isolation
- **Functional tests**: Test complete plugin workflows with child processes
- **Integration tests**: Test plugin interactions with Neovim API

#### Performance Considerations

- Use `before_each`/`after_each` hooks for setup/teardown
- Isolate each test in separate Neovim processes for functional tests
- Mock external dependencies where possible

#### Quality Assurance

- Add `.luacheckrc` for static analysis
- Include `stylua.toml` for code formatting
- Document test requirements and setup in README
- Use descriptive test names and clear assertions

Goal achieved: Plugin will be easily installable through standard neovim plugin managers with proper documentation and structure.
