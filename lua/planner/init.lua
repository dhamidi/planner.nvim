local M = {}

-- Default configuration
local default_config = {
  custom_instructions = "",
  log_path = vim.fn.expand("~/.local/state/nvim/planner.log"),
  response_path = vim.fn.expand("~/.local/tmp/planner.txt"),
}

-- Store the merged configuration
local config = {}

-- Store active processes
local active_processes = {}

-- Track buffers with attached locks
local locked_buffers = {}

-- Create namespace for planner virtual text
local namespace = vim.api.nvim_create_namespace("planner")

-- Spinner animation frames
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Prepare input for subprocess
local function prepare_llm_prompt(file_contents, selected_text, response_file)
  local prompt = "You are the technical planner, operating on a markdown file.\n\n"

  -- Add custom instructions if provided
  if config.custom_instructions and config.custom_instructions ~= "" then
    prompt = prompt .. config.custom_instructions .. "\n\n"
  end

  prompt = prompt
    .. string.format(
      [[The user has asked you to break down a step of the plan.

Inspect the entire plan, and then take the selected step and break it down into more detailed steps.

Respond only with the more detailed version of selected_text.  Your response will replace selected_text
in the original plan. You MUST write your response to %s

If selected_text contains the word "study", actually perform the research and include the results in your response.

<plan_file>%s</plan_file>
<selected_text>%s</selected_text>
  ]],
      response_file,
      file_contents,
      selected_text
    )

  return prompt
end

-- Logging function
local function log(msg)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_entry = string.format("[%s] %s\n", timestamp, msg)

  local file = io.open(config.log_path, "a")
  if file then
    file:write(log_entry)
    file:close()
  end
end

-- Per-process logging function
local function log_process_output(pid, stream, data)
local process_info = active_processes[pid]
if not process_info or not process_info.log_file then
return
end

-- Write raw data without timestamps or stream labels
local file = io.open(process_info.log_file, "a")
if file then
  file:write(data)
  file:close()
end
end

-- Check for overlapping processes
local function check_for_overlaps(bufnr, start_line, start_col, end_line, end_col)
  for pid, process_info in pairs(active_processes) do
    if process_info.bufnr == bufnr then
      local start_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, process_info.start_extmark_id, {})
      local end_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, process_info.end_extmark_id, {})

      if start_pos and #start_pos >= 2 and end_pos and #end_pos >= 2 then
        local proc_start_row, proc_end_row = start_pos[1], end_pos[1]
        -- Check for overlap (ranges overlap if not completely separate)
        if not (end_line < proc_start_row or start_line > proc_end_row) then
          return pid
        end
      end
    end
  end
  return nil
end

-- Set up buffer locking
local function setup_buffer_lock(bufnr)
  if locked_buffers[bufnr] then
    return -- Already set up
  end

  locked_buffers[bufnr] = true

  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _, changedtick, firstline, lastline, new_lastline)
      -- Check if change overlaps with any active process regions
      for pid, process_info in pairs(active_processes) do
        if process_info.bufnr == bufnr then
          local start_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, process_info.start_extmark_id, {})
          local end_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, process_info.end_extmark_id, {})

          if start_pos and #start_pos >= 2 and end_pos and #end_pos >= 2 then
            local start_row, end_row = start_pos[1], end_pos[1]
            if firstline <= end_row and lastline >= start_row then
              vim.notify("Cannot edit text being processed by PID " .. pid, vim.log.levels.WARN)
              return true -- prevent the change
            end
          end
        end
      end
    end,
  })
end

-- Update virtual text for a specific process
local function update_virtual_text(pid)
  local process_info = active_processes[pid]
  if not process_info then
    return
  end

  local elapsed = (vim.loop.hrtime() - process_info.start_time) / 1e9

  -- Update spinner animation per process
  process_info.spinner_index = (process_info.spinner_index % #spinner_frames) + 1
  local spinner = spinner_frames[process_info.spinner_index]

  -- Format elapsed time
  local time_str = string.format("%.1fs", elapsed)

  -- Build display text with just spinner, time, and processing text
  local display_text = string.format(" %s Processing (%s)", spinner, time_str)

  -- Get current extmark position
  local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(process_info.bufnr, namespace, process_info.end_extmark_id, {})

  -- Update the extmark with new virtual text
  if extmark_pos and #extmark_pos >= 2 then
    local end_row, end_col = extmark_pos[1], extmark_pos[2]
    if end_col >= 0 then
      vim.api.nvim_buf_set_extmark(process_info.bufnr, namespace, end_row, end_col, {
        id = process_info.end_extmark_id,
        virt_text = { { display_text, "Comment" } },
        virt_text_pos = "eol",
        hl_group = "ErrorMsg",
        priority = 200,
      })
    end
  end
end

-- Clean up process resources
local function cleanup_process(pid)
  local process_info = active_processes[pid]
  if not process_info then
    return
  end

  -- Stop and close spinner timer
  if process_info.timer then
    process_info.timer:stop()
    process_info.timer:close()
  end

  -- Stop and close check timer
  if process_info.check_timer then
    process_info.check_timer:stop()
    process_info.check_timer:close()
  end

  -- Clean up temp file
  if process_info.response_file and vim.fn.filereadable(process_info.response_file) == 1 then
    os.remove(process_info.response_file)
  end

  -- Clean up log file
  if process_info.log_file and vim.fn.filereadable(process_info.log_file) == 1 then
    os.remove(process_info.log_file)
  end

  -- Remove from active processes
  active_processes[pid] = nil
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

  -- Determine visual mode type
  local visual_mode
  if mode == "V" then
    -- Visual line mode - select entire lines
    visual_mode = "line"
    start_col = 0
    end_col = -1 -- Use -1 as our special marker for line mode
  elseif mode == "\22" then
    -- Visual block mode - keep as is
    visual_mode = "block"
  else
    -- Character visual mode - ensure proper column range
    visual_mode = "char"
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

  -- Check for overlapping processes before starting
  local current_bufnr = vim.api.nvim_get_current_buf()
  local overlapping_pid = check_for_overlaps(current_bufnr, start_line, start_col, end_line, end_col)
  if overlapping_pid then
    vim.notify("Cannot start: overlaps with process " .. overlapping_pid, vim.log.levels.WARN)
    return
  end

  -- Get entire file contents
  local file_contents = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  log(string.format("File contents length: %d", #file_contents))

  -- Exit visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)

  -- Spawn the process
  local stdin_pipe = vim.loop.new_pipe(false)
  local stdout_pipe = vim.loop.new_pipe(false)
  local stderr_pipe = vim.loop.new_pipe(false)

  local handle, pid = vim.loop.spawn("amp", {
    args = {},
    stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
  })

  if not handle then
    log("Failed to spawn process")
    return
  end

  log(string.format("Spawned process with PID: %s", tostring(pid)))

  -- Create unique response file for this process
  local response_file = vim.fn.tempname() .. "-planner-" .. pid .. ".txt"

  -- Create unique log file for this process
  local log_file = vim.fn.tempname() .. "-planner-" .. pid .. ".log"

  -- Generate LLM prompt with unique response file
  local llm_input = prepare_llm_prompt(file_contents, selected_text, response_file)
  log(string.format("LLM input length: %d", #llm_input))

  -- Create extmark pair for region tracking
  local start_extmark_id = vim.api.nvim_buf_set_extmark(0, namespace, start_line, start_col, {
    right_gravity = false, -- left-sticky
  })
  -- For line mode, use column 0 instead of -1
  local end_extmark_col = (visual_mode == "line") and 0 or end_col
  local end_extmark_id = vim.api.nvim_buf_set_extmark(0, namespace, end_line, end_extmark_col, {
    right_gravity = true, -- right-sticky
    virt_text = { { " " .. spinner_frames[1] .. " Processing...", "Comment" } },
    virt_text_pos = "eol",
    hl_group = "ErrorMsg",
    priority = 200,
  })

  -- Store process info with extmark IDs
  active_processes[pid] = {
    bufnr = vim.api.nvim_get_current_buf(),
    start_time = vim.loop.hrtime(),
    timer = vim.loop.new_timer(),
    handle = handle,
    stdout_pipe = stdout_pipe,
    stderr_pipe = stderr_pipe,
    start_extmark_id = start_extmark_id,
    end_extmark_id = end_extmark_id,
    mode = visual_mode,
    orig_hash = vim.fn.sha256(selected_text),
    response_file = response_file,
    log_file = log_file,
    selected_text = selected_text,
    spinner_index = 1, -- per-process spinner state
  }

  -- Set up completion callback with captured pid
  local completion_callback = function(code, signal)
    vim.schedule(function()
      log(string.format("Process %s finished with code %s", tostring(pid), tostring(code)))

      local process_info = active_processes[pid]
      if not process_info then
        log("No process info found for PID " .. tostring(pid))
        return
      end

      -- Read response from unique file
      local file = io.open(process_info.response_file, "r")
      local response_content = ""

      if file then
        response_content = file:read("*all")
        file:close()
        log(string.format("Read response from file: '%s'", response_content))
        -- Clean up temp file
        os.remove(process_info.response_file)
      else
        log("Failed to read response file: " .. (process_info.response_file or "unknown"))
        response_content = "Error: Could not read response file"
      end

      local bufnr = process_info.bufnr

      -- Get current region boundaries from extmarks
      local start_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, process_info.start_extmark_id, {})
      local end_pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, process_info.end_extmark_id, {})

      local start_row, start_col, end_row, end_col
      if start_pos and #start_pos >= 2 then
        start_row, start_col = start_pos[1], start_pos[2]
      end
      if end_pos and #end_pos >= 2 then
        end_row, end_col = end_pos[1], end_pos[2]
      end

      if not start_row or not end_row then
        log("Extmarks vanished - cannot apply result for PID " .. pid)
        cleanup_process(pid)
        return
      end

      -- Clear the extmarks
      vim.api.nvim_buf_del_extmark(bufnr, namespace, process_info.start_extmark_id)
      vim.api.nvim_buf_del_extmark(bufnr, namespace, process_info.end_extmark_id)

      -- Split response into lines and remove empty trailing line
      local response_lines = vim.split(response_content, "\n")
      if response_lines[#response_lines] == "" then
        table.remove(response_lines, #response_lines)
      end

      -- Replace the selected text with the LLM response
      if process_info.mode == "line" then
        -- Visual line mode - replace entire lines
        vim.api.nvim_buf_set_lines(bufnr, start_row, end_row + 1, false, response_lines)
      else
        -- Character/block mode - replace text range
        -- For extmarks, we need to get the actual end position, not the stored -1
        local actual_end_col = end_col
        if actual_end_col == -1 then
          -- This shouldn't happen anymore, but just in case
          actual_end_col = 0
        end
        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, actual_end_col, response_lines)
      end

      log(string.format("Replaced selection with %d lines", #response_lines))
      for k, new_line in ipairs(response_lines) do
        log(string.format("  Line %d: '%s'", k, new_line))
      end

      -- Clean up
      cleanup_process(pid)
      -- stdin_pipe is already closed after writing
    end)
  end

  -- Store the check timer for cleanup
  local check_timer = vim.loop.new_timer()
  active_processes[pid].check_timer = check_timer

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

  -- Start reading stdout and log to per-process file
  stdout_pipe:read_start(function(err, data)
    if err then
      log("Error reading stdout: " .. err)
      log_process_output(pid, "STDOUT-ERROR", err)
    elseif data then
      -- Log to per-process log file
      log_process_output(pid, "STDOUT", data)
    end
  end)

  -- Start reading stderr and log to per-process file
  stderr_pipe:read_start(function(err, data)
    if err then
      log("Error reading stderr: " .. err)
      log_process_output(pid, "STDERR-ERROR", err)
    elseif data then
      -- Log to per-process log file
      log_process_output(pid, "STDERR", data)
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

  log(string.format("Created extmarks: start=%d, end=%d", start_extmark_id, end_extmark_id))

  -- Set up buffer lock if not already done
  setup_buffer_lock(current_bufnr)

  -- Start timer to update spinner and counter
  active_processes[pid].timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      if not active_processes[pid] then
        return
      end

      -- Use the centralized update function
      update_virtual_text(pid)
    end)
  )
end

-- Find active process at cursor position
local function find_process_at_cursor()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1] - 1 -- Convert to 0-indexed
  local current_bufnr = vim.api.nvim_get_current_buf()

  -- Find process by checking if cursor is within any active region
  for pid, process_info in pairs(active_processes) do
    if process_info.bufnr == current_bufnr then
      local start_pos =
        vim.api.nvim_buf_get_extmark_by_id(process_info.bufnr, namespace, process_info.start_extmark_id, {})
      local end_pos = vim.api.nvim_buf_get_extmark_by_id(process_info.bufnr, namespace, process_info.end_extmark_id, {})

      if start_pos and #start_pos >= 2 and end_pos and #end_pos >= 2 then
        local start_row, end_row = start_pos[1], end_pos[1]
        if cursor_line >= start_row and cursor_line <= end_row then
          return pid, process_info
        end
      end
    end
  end

  return nil, nil
end

-- Abort process at cursor position
function M.abort_process()
  local pid, process_info = find_process_at_cursor()

  if not pid then
    vim.notify("No active process found at cursor position", vim.log.levels.WARN)
    return
  end

  log(string.format("Aborting process %s", tostring(pid)))

  -- Try to kill the process
  local success = vim.loop.kill(pid, "sigterm")
  if not success then
    -- Fallback to SIGKILL
    success = vim.loop.kill(pid, "sigkill")
  end

  if success then
    -- Clean up extmarks
    vim.api.nvim_buf_del_extmark(process_info.bufnr, namespace, process_info.start_extmark_id)
    vim.api.nvim_buf_del_extmark(process_info.bufnr, namespace, process_info.end_extmark_id)

    -- Clean up process resources
    cleanup_process(pid)

    vim.notify("Process " .. pid .. " aborted", vim.log.levels.INFO)
    log(string.format("Successfully aborted process %s", tostring(pid)))
  else
    vim.notify("Failed to abort process", vim.log.levels.ERROR)
    log(string.format("Failed to abort process %s", tostring(pid)))
  end
end

-- Show process log in terminal window
function M.show_process_log()
  local pid, process_info = find_process_at_cursor()

  if not pid then
    vim.notify("No active process found at cursor position", vim.log.levels.WARN)
    return
  end

  local log_file = process_info.log_file
  if not log_file or vim.fn.filereadable(log_file) == 0 then
    vim.notify("No log file found for process " .. pid, vim.log.levels.WARN)
    return
  end

  -- Create a new terminal buffer
  local term_buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(term_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(term_buf, "buflisted", false)
  vim.api.nvim_buf_set_option(term_buf, "swapfile", false)

  -- Split current window and show terminal
  vim.cmd("split")
  local term_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(term_win, term_buf)

  -- Set window title
  vim.api.nvim_win_set_option(term_win, "statusline", string.format("Process %s Log (tail -f)", pid))

  -- Start tail command in terminal
  local job_id = vim.fn.termopen(string.format('tail -f "%s"', log_file), {
    on_exit = function()
      -- Close terminal window when tail exits
      if vim.api.nvim_win_is_valid(term_win) then
        vim.api.nvim_win_close(term_win, true)
      end
    end,
  })

  -- Set up keybindings for terminal buffer
  local function close_terminal()
    if vim.api.nvim_win_is_valid(term_win) then
      vim.api.nvim_win_close(term_win, true)
    end
  end

  -- Map 'q' and '<C-c>' to close terminal
  vim.api.nvim_buf_set_keymap(term_buf, "t", "q", "", {
    callback = close_terminal,
    noremap = true,
    silent = true,
  })

  vim.api.nvim_buf_set_keymap(term_buf, "t", "<C-c>", "", {
    callback = close_terminal,
    noremap = true,
    silent = true,
  })

  -- Also map in normal mode for when terminal is not active
  vim.api.nvim_buf_set_keymap(term_buf, "n", "q", "", {
    callback = close_terminal,
    noremap = true,
    silent = true,
  })

  log(string.format("Opened log viewer for process %s", tostring(pid)))
end

function M.setup(opts)
  opts = opts or {}

  -- Merge configuration
  config = vim.tbl_deep_extend("force", default_config, opts)

  -- Validate configuration
  if type(config.custom_instructions) ~= "string" then
    error("planner.nvim: custom_instructions must be a string")
  end

  if type(config.log_path) ~= "string" or config.log_path == "" then
    error("planner.nvim: log_path must be a non-empty string")
  end

  if type(config.response_path) ~= "string" or config.response_path == "" then
    error("planner.nvim: response_path must be a non-empty string")
  end

  -- Create directory structure for configurable paths
  local log_dir = vim.fn.fnamemodify(config.log_path, ":h")
  local response_dir = vim.fn.fnamemodify(config.response_path, ":h")

  local success = vim.fn.mkdir(log_dir, "p")
  if success == 0 then
    error("planner.nvim: Failed to create log directory: " .. log_dir)
  end

  success = vim.fn.mkdir(response_dir, "p")
  if success == 0 then
    error("planner.nvim: Failed to create response directory: " .. response_dir)
  end

  -- Set up default key mapping
  vim.keymap.set("v", "<leader>pp", M.process_selected_text, {
    desc = "Process selected text",
    noremap = true,
    silent = true,
  })

  -- Set up abort key mapping
  vim.keymap.set("n", "<leader>pa", M.abort_process, {
    desc = "Abort planner process at cursor",
    noremap = true,
    silent = true,
  })

  -- Set up log viewing key mapping
  vim.keymap.set("n", "<leader>pl", M.show_process_log, {
    desc = "Show planner process log at cursor",
    noremap = true,
    silent = true,
  })
end

return M
