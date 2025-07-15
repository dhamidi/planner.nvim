-- minimal_init.lua for testing planner.nvim plugin
-- This file sets up a minimal Neovim environment for testing with mini.test

-- Set up isolated test environment with custom XDG directories
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, 'p')
vim.env.XDG_CONFIG_HOME = temp_dir .. '/.config'
vim.env.XDG_DATA_HOME = temp_dir .. '/.local/share'
vim.env.XDG_STATE_HOME = temp_dir .. '/.local/state'
vim.env.XDG_CACHE_HOME = temp_dir .. '/.cache'

-- Ensure plugin is in runtime path
-- Get the parent directory of the test directory
local current_dir = vim.fn.getcwd()
local plugin_dir = vim.fn.fnamemodify(current_dir, ':h')
vim.opt.rtp:prepend(plugin_dir)

-- Add mini.test to runtime path (assumes it's installed)
local function add_to_rtp(path)
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
  end
end

-- Common locations for mini.test
local possible_paths = {
  plugin_dir .. '/deps/mini.nvim',
  vim.fn.stdpath('data') .. '/site/pack/packer/start/mini.test',
  vim.fn.stdpath('data') .. '/lazy/mini.test',
  vim.fn.stdpath('data') .. '/plugged/mini.test',
  vim.fn.stdpath('data') .. '/site/pack/deps/start/mini.test',
}

for _, path in ipairs(possible_paths) do
  add_to_rtp(path)
end

-- Configure mini.test framework
local ok, mini_test = pcall(require, 'mini.test')
if not ok then
  error('mini.test is not available. Please install it first.')
end

-- Disable swap files and other distractions
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false

-- Set leader key for testing
vim.g.mapleader = ' '

-- Create empty buffer for testing
vim.cmd('enew')


