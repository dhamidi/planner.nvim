.PHONY: test

test:
	@cd test && for test_file in test_*.lua; do \
		if [ -f "$$test_file" ]; then \
			echo "Running $$test_file..."; \
			nvim --headless -u minimal_init.lua -c "lua local MiniTest = require('mini.test'); MiniTest.run_file('$$test_file')" -c "qa!" || exit 1; \
		fi \
	done
