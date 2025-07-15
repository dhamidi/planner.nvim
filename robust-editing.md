# Robust Process Tracking Implementation Plan

## Overview
This plan addresses the core issues with the current process tracking system where coordinates become invalid when text is edited during processing. The solution uses extmarks as the single source of truth and implements proper locking to prevent editing conflicts.

## Current Problems
1. Fixed coordinates become stale when text is edited above the selection
2. Multiple processes can have conflicting coordinate systems
3. No protection against editing text being processed
4. Race conditions with shared response files
5. Extmark positioning fights with automatic tracking

## Solution Architecture

### 1. Extmark-Based Region Tracking
Replace coordinate storage with extmark pairs that automatically track region boundaries:

```lua
-- Create start and end extmarks for each process
local start_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, start_line, start_col, {
  right_gravity = false,  -- left-sticky
})
local end_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, end_line, end_col, {
  right_gravity = true,   -- right-sticky
  virt_text = {{" " .. spinner_frames[1] .. " Processing...", "Comment"}},
  virt_text_pos = "eol",
  hl_group = 'ErrorMsg',
  priority = 200
})
```

### 2. Updated Data Model
```lua
active_processes[pid] = {
  bufnr = buffer_number,
  start_extmark_id = start_id,
  end_extmark_id = end_id,
  mode = "char" | "line" | "block",
  orig_hash = sha1(selected_text),
  response_file = unique_temp_file_path,
  timer = uv.new_timer(),
  stdout_pipe = pipe,
  handle = process_handle,
  start_time = hrtime,
  last_output = "",
  spinner_index = 1  -- per-process spinner state
}
```

### 3. Region Locking Implementation
Implement fine-grained locking using buffer callbacks:

```lua
-- Attach once per buffer, reuse for all processes
local function setup_buffer_lock(bufnr)
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _, changedtick, firstline, lastline, new_lastline)
      -- Check if change overlaps with any active process regions
      for pid, process_info in pairs(active_processes) do
        if process_info.bufnr == bufnr then
          local start_row = vim.api.nvim_buf_get_extmark_by_id(
            bufnr, namespace, process_info.start_extmark_id, {}
          )[1]
          local end_row = vim.api.nvim_buf_get_extmark_by_id(
            bufnr, namespace, process_info.end_extmark_id, {}
          )[1]
          
          if start_row and end_row and 
             firstline <= end_row and lastline >= start_row then
            vim.notify("Cannot edit text being processed by PID " .. pid, 
                      vim.log.levels.WARN)
            return true -- prevent the change
          end
        end
      end
    end
  })
end
```

### 4. Process Spawning Changes
```lua
function M.process_selected_text()
  -- ... existing selection logic ...
  
  -- Check for overlapping processes before starting
  local overlapping_pid = check_for_overlaps(bufnr, start_line, start_col, end_line, end_col)
  if overlapping_pid then
    vim.notify("Cannot start: overlaps with process " .. overlapping_pid, vim.log.levels.WARN)
    return
  end
  
  -- Create unique response file per process
  local response_file = vim.fn.tempname() .. "-planner-" .. pid .. ".txt"
  
  -- Create extmark pair for region tracking
  local start_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, start_line, start_col, {
    right_gravity = false,
  })
  local end_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, end_line, end_col, {
    right_gravity = true,
    virt_text = {{" " .. spinner_frames[1] .. " Processing...", "Comment"}},
    virt_text_pos = "eol",
    hl_group = 'ErrorMsg',
    priority = 200
  })
  
  -- Store process info with extmark IDs
  active_processes[pid] = {
    bufnr = bufnr,
    start_extmark_id = start_id,
    end_extmark_id = end_id,
    mode = mode,
    orig_hash = vim.fn.sha256(selected_text),
    response_file = response_file,
    timer = timer,
    stdout_pipe = stdout_pipe,
    handle = handle,
    start_time = start_time,
    last_output = "",
    spinner_index = 1
  }
  
  -- Update LLM prompt to use unique response file
  local llm_input = prepare_llm_prompt(file_contents, selected_text, response_file)
  
  -- Set up buffer lock if not already done
  setup_buffer_lock(bufnr)
  
  -- ... rest of spawn logic ...
end
```

### 5. Spinner Updates
```lua
-- Update spinner without repositioning extmark
local function update_spinner(pid)
  local process_info = active_processes[pid]
  if not process_info then return end
  
  local end_row, end_col = vim.api.nvim_buf_get_extmark_by_id(
    process_info.bufnr, namespace, process_info.end_extmark_id, {}
  )
  
  if not end_row then return end
  
  -- Update spinner index per process
  process_info.spinner_index = (process_info.spinner_index % #spinner_frames) + 1
  local spinner = spinner_frames[process_info.spinner_index]
  
  local elapsed = (vim.loop.hrtime() - process_info.start_time) / 1e9
  local time_str = string.format("%.1fs", elapsed)
  
  local display_text = string.format(" %s Processing (%s)", spinner, time_str)
  if process_info.last_output ~= "" then
    display_text = display_text .. " " .. process_info.last_output
  end
  
  -- Update only the virtual text, don't reposition
  vim.api.nvim_buf_set_extmark(process_info.bufnr, namespace, end_row, end_col, {
    id = process_info.end_extmark_id,
    virt_text = {{display_text, "Comment"}},
    virt_text_pos = "eol",
    hl_group = 'ErrorMsg',
    priority = 200
  })
end
```

### 6. Process Completion
```lua
local function complete_process(pid, exit_code, signal)
  local process_info = active_processes[pid]
  if not process_info then return end
  
  -- Get current region boundaries
  local start_row, start_col = vim.api.nvim_buf_get_extmark_by_id(
    process_info.bufnr, namespace, process_info.start_extmark_id, {}
  )
  local end_row, end_col = vim.api.nvim_buf_get_extmark_by_id(
    process_info.bufnr, namespace, process_info.end_extmark_id, {}
  )
  
  if not start_row or not end_row then
    log("Extmarks vanished - cannot apply result for PID " .. pid)
    cleanup_process(pid)
    return
  end
  
  -- Read response from unique file
  local response_content = ""
  local file = io.open(process_info.response_file, "r")
  if file then
    response_content = file:read("*all")
    file:close()
    -- Clean up temp file
    os.remove(process_info.response_file)
  else
    log("Failed to read response file for PID " .. pid)
    cleanup_process(pid)
    return
  end
  
  -- Optional: Check for conflicts
  local current_text = table.concat(
    vim.api.nvim_buf_get_text(process_info.bufnr, start_row, start_col, end_row, end_col, {}), 
    "\n"
  )
  if vim.fn.sha256(current_text) ~= process_info.orig_hash then
    log("Content changed during processing - conflicts possible")
  end
  
  -- Replace text based on mode
  local response_lines = vim.split(response_content, "\n")
  if response_lines[#response_lines] == "" then
    table.remove(response_lines, #response_lines)
  end
  
  if process_info.mode == "line" then
    vim.api.nvim_buf_set_lines(process_info.bufnr, start_row, end_row + 1, false, response_lines)
  else
    vim.api.nvim_buf_set_text(process_info.bufnr, start_row, start_col, end_row, end_col, response_lines)
  end
  
  -- Clean up extmarks and process
  vim.api.nvim_buf_del_extmark(process_info.bufnr, namespace, process_info.start_extmark_id)
  vim.api.nvim_buf_del_extmark(process_info.bufnr, namespace, process_info.end_extmark_id)
  
  cleanup_process(pid)
end
```

### 7. Overlap Detection
```lua
local function check_for_overlaps(bufnr, start_line, start_col, end_line, end_col)
  for pid, process_info in pairs(active_processes) do
    if process_info.bufnr == bufnr then
      local proc_start_row, proc_start_col = vim.api.nvim_buf_get_extmark_by_id(
        bufnr, namespace, process_info.start_extmark_id, {}
      )
      local proc_end_row, proc_end_col = vim.api.nvim_buf_get_extmark_by_id(
        bufnr, namespace, process_info.end_extmark_id, {}
      )
      
      if proc_start_row and proc_end_row then
        -- Check for overlap
        if not (end_line < proc_start_row or start_line > proc_end_row) then
          return pid
        end
      end
    end
  end
  return nil
end
```

### 8. Resource Cleanup
```lua
local function cleanup_process(pid)
  local process_info = active_processes[pid]
  if not process_info then return end
  
  -- Stop and close timer
  if process_info.timer then
    process_info.timer:stop()
    process_info.timer:close()
  end
  
  -- Close pipes
  if process_info.stdout_pipe then
    process_info.stdout_pipe:close()
  end
  
  -- Close process handle
  if process_info.handle then
    process_info.handle:close()
  end
  
  -- Clean up temp file
  if process_info.response_file and vim.fn.filereadable(process_info.response_file) == 1 then
    os.remove(process_info.response_file)
  end
  
  -- Remove from active processes
  active_processes[pid] = nil
end
```

### 9. Abort Process Updates
```lua
function M.abort_process()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1] - 1
  
  -- Find process by checking if cursor is within any active region
  for pid, process_info in pairs(active_processes) do
    if process_info.bufnr == vim.api.nvim_get_current_buf() then
      local start_row = vim.api.nvim_buf_get_extmark_by_id(
        process_info.bufnr, namespace, process_info.start_extmark_id, {}
      )[1]
      local end_row = vim.api.nvim_buf_get_extmark_by_id(
        process_info.bufnr, namespace, process_info.end_extmark_id, {}
      )[1]
      
      if start_row and end_row and cursor_line >= start_row and cursor_line <= end_row then
        -- Kill the process
        vim.loop.kill(pid, "sigterm")
        
        -- Clean up extmarks
        vim.api.nvim_buf_del_extmark(process_info.bufnr, namespace, process_info.start_extmark_id)
        vim.api.nvim_buf_del_extmark(process_info.bufnr, namespace, process_info.end_extmark_id)
        
        cleanup_process(pid)
        
        vim.notify("Process " .. pid .. " aborted", vim.log.levels.INFO)
        return
      end
    end
  end
  
  vim.notify("No active process found at cursor position", vim.log.levels.WARN)
end
```

## Implementation Order
1. Update data model to use extmark pairs
2. Implement unique response files per process
3. Add overlap detection before process spawning
4. Implement buffer locking with `on_lines` callback
5. Update spinner logic to use per-process state
6. Modify completion logic to use extmark boundaries
7. Update abort logic to work with extmark regions
8. Add proper resource cleanup throughout

## Benefits
- Coordinates never become invalid through automatic extmark tracking
- Multiple processes can run safely without interference
- Locked regions prevent editing conflicts
- Unique response files eliminate race conditions
- Proper resource cleanup prevents memory leaks
- Visual feedback shows locked regions clearly

## Edge Cases Handled
- Buffer becoming invalid during processing
- Overlapping process regions
- Process dying unexpectedly
- Temp file cleanup on all exit paths
- Extmark disappearing due to text changes
- Multiple spinners running concurrently
