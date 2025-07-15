.PHONY: test

test:
	@cd test && nvim --headless -u minimal_init.lua -c "lua local MiniTest = require('mini.test'); MiniTest.run_file('test_init.lua')" -c "qa!"
