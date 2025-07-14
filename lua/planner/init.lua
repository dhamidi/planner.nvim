local M = {}

-- Store active processes
local active_processes = {}

-- Prepare input for subprocess
local function prepare_llm_prompt(file_contents, selected_text)
  return string.format(
    [[You are the technical planner, operating on a markdown file.

The user has asked you to break down a step of the plan.

Inspect the entire plan, and then take the selected step and break it down into more detailed steps.

Respond only with the more detailed version of selected_text.  Your response will replace selected_text
in the original plan. You MUST write your response to ~/.planner.response

If selected_text contains the word "study", actually perform the research and include the results in your response.

<plan_file>%s</plan_file>
<selected_text>%s</selected_text>
  ]],
    file_contents,
    selected_text
  )
end

-- Logging function
local function log(msg)
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
  local log_file = home .. "/.planner.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_entry = string.format("[%s] %s\n", timestamp, msg)

  local file = io.open(log_file, "a")
  if file then
    file:write(log_entry)
    file:close()
  end
end

function M.process_selected_text()
  -- Get the current visual selection
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    log("No text selected")
    return
  end

  -- Get selection range using visual marks
  local start_pos = vim.fn.getpos("'<") -- Start of visual selection
  local end_pos = vim.fn.getpos("'>") -- End of visual selection

  -- Check if we have valid visual marks
  log(string.format("Raw start_pos: [%d,%d,%d,%d]", start_pos[1], start_pos[2], start_pos[3], start_pos[4]))
  log(string.format("Raw end_pos: [%d,%d,%d,%d]", end_pos[1], end_pos[2], end_pos[3], end_pos[4]))

  if start_pos[2] == 0 or end_pos[2] == 0 then
    log("Invalid visual marks - falling back to current position")
    -- Fallback to current position if marks aren't available
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
    log(string.format("Fallback start_pos: [%d,%d,%d,%d]", start_pos[1], start_pos[2], start_pos[3], start_pos[4]))
    log(string.format("Fallback end_pos: [%d,%d,%d,%d]", end_pos[1], end_pos[2], end_pos[3], end_pos[4]))
  end

  -- Convert to 0-indexed
  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_col = end_pos[3]

  -- Handle different visual modes
  if mode == "V" then
    -- Visual line mode - select entire lines
    -- In line mode, start_col should be 0 and end_col should be v:maxcol
    start_col = 0
    end_col = -1 -- Use -1 as our special marker for line mode
  elseif mode == "\22" then
    -- Visual block mode - keep as is
  else
    -- Character visual mode - ensure proper column range
    -- In character mode, end_col is inclusive, so we need to add 1 for exclusive end
    if start_line == end_line then
      end_col = end_col + 1
    end
  end

  -- Debug output
  log(string.format("Selection: [%d,%d] to [%d,%d]", start_line, start_col, end_line, end_col))

  -- Get the selected text content before replacing it
  local selected_text
  if end_col == -1 then
    -- Visual line mode - get entire lines
    selected_text = table.concat(vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, false), "\n")
  else
    -- Character/block mode - get text range
    selected_text = table.concat(vim.api.nvim_buf_get_text(0, start_line, start_col, end_line, end_col, {}), "\n")
  end

  log(string.format("Selected text: '%s'", selected_text))

  -- Get entire file contents
  local file_contents = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  log(string.format("File contents length: %d", #file_contents))

  -- Generate LLM prompt
  local llm_input = prepare_llm_prompt(file_contents, selected_text)
  log(string.format("LLM input length: %d", #llm_input))

  -- Exit visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)

  -- Spawn the process
  local stdin_pipe = vim.loop.new_pipe(false)

  local handle, pid = vim.loop.spawn("amp", {
    args = {},
    stdio = { stdin_pipe, nil, nil },
  })

  if not handle then
    log("Failed to spawn process")
    return
  end

  log(string.format("Spawned process with PID: %s", tostring(pid)))

  -- Store process info immediately
  active_processes[pid] = {
    bufnr = vim.api.nvim_get_current_buf(),
    start_time = vim.loop.now(),
    timer = vim.loop.new_timer(),
    handle = handle,
  }

  -- Set up completion callback with captured pid
  local completion_callback = function(code, signal)
    vim.schedule(function()
      log(string.format("Process %s finished with code %s", tostring(pid), tostring(code)))

      -- Read response from file
      local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
      local response_file = home .. "/.planner.response"
      local file = io.open(response_file, "r")
      local response_content = ""

      if file then
        response_content = file:read("*all")
        file:close()
        log(string.format("Read response from file: '%s'", response_content))
      else
        log("Failed to read response file")
        response_content = "Error: Could not read response file"
      end

      local process_info = active_processes[pid]
      if process_info then
        -- Replace placeholder with stdout
        local placeholder_pattern = "%[working%-" .. pid .. " %d+s%]"
        local bufnr = process_info.bufnr
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        log(string.format("Looking for pattern: %s", placeholder_pattern))
        log(string.format("Buffer has %d lines", #lines))

        local found = false
        for i, line in ipairs(lines) do
          log(string.format("Line %d: '%s'", i, line))
          if string.find(line, placeholder_pattern) then
            log(string.format("Found placeholder in line %d: '%s'", i, line))

            -- Split response into lines and remove empty trailing line
            local response_lines = vim.split(response_content, "\n")
            if response_lines[#response_lines] == "" then
              table.remove(response_lines, #response_lines)
            end

            -- Find the placeholder position in the line
            local before_placeholder, placeholder_match, after_placeholder =
              string.match(line, "^(.-)(" .. placeholder_pattern .. ")(.*)$")
            if before_placeholder then
              -- Split the line at the placeholder
              local prefix = before_placeholder or ""
              local suffix = after_placeholder or ""

              -- Create new lines
              local new_lines = {}
              for j, response_line in ipairs(response_lines) do
                if j == 1 then
                  -- First line: prefix + response_line
                  table.insert(new_lines, prefix .. response_line)
                elseif j == #response_lines then
                  -- Last line: response_line + suffix
                  table.insert(new_lines, response_line .. suffix)
                else
                  -- Middle lines: just response_line
                  table.insert(new_lines, response_line)
                end
              end

              -- Handle case where there's only one response line
              if #response_lines == 1 then
                new_lines = { prefix .. response_lines[1] .. suffix }
              end

              -- Replace the single line with multiple lines
              vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, new_lines)
              log(string.format("Replaced with %d lines", #new_lines))
              for k, new_line in ipairs(new_lines) do
                log(string.format("  Line %d: '%s'", k, new_line))
              end
              found = true
              break
            end
          end
        end

        if not found then
          log("Placeholder not found in any line")
        end

        -- Clean up
        if process_info.timer then
          process_info.timer:stop()
          process_info.timer:close()
        end
        active_processes[pid] = nil
      else
        log("No process info found for PID " .. tostring(pid))
      end
      -- stdin_pipe is already closed after writing
    end)
  end

  -- Use a timer to periodically check if process is done
  local check_timer = vim.loop.new_timer()
  check_timer:start(100, 100, function()
    if not active_processes[pid] then
      check_timer:stop()
      check_timer:close()
      return
    end

    -- Check if process is still running
    local success, exit_code, signal = vim.loop.kill(pid, 0)
    if not success then
      -- Process is done
      check_timer:stop()
      check_timer:close()
      completion_callback(exit_code or 0, signal or 0)
    end
  end)

  -- Write LLM prompt to stdin
  stdin_pipe:write(llm_input, function(err)
    if err then
      log("Error writing to stdin: " .. err)
    else
      log("Successfully wrote LLM input to stdin")
    end
    -- Close stdin after writing
    stdin_pipe:close()
  end)

  -- Create placeholder with PID
  local placeholder = "[working-" .. pid .. " 0s]"

  -- Replace the selected text with placeholder
  if end_col == -1 then
    -- Visual line mode - replace entire lines
    vim.api.nvim_buf_set_lines(0, start_line, end_line + 1, false, { placeholder })
  else
    -- Character/block mode - replace text range
    vim.api.nvim_buf_set_text(0, start_line, start_col, end_line, end_col, { placeholder })
  end

  -- Start timer to update counter
  active_processes[pid].timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      local process_info = active_processes[pid]
      if not process_info then
        return
      end

      local elapsed = math.floor((vim.loop.now() - process_info.start_time) / 1000)
      local new_placeholder = "[working-" .. pid .. " " .. elapsed .. "s]"

      -- Find and update the placeholder
      local bufnr = process_info.bufnr
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      for i, line in ipairs(lines) do
        local old_pattern = "%[working%-" .. pid .. " %d+s%]"
        if string.find(line, old_pattern) then
          local new_line = string.gsub(line, old_pattern, new_placeholder)
          vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
          break
        end
      end
    end)
  )
end

function M.setup(opts)
  opts = opts or {}

  -- Set up default key mapping
  vim.keymap.set("v", "<leader>pp", M.process_selected_text, {
    desc = "Process selected text",
    noremap = true,
    silent = true,
  })
end

return M
