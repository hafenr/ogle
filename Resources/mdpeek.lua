-- Connects the Neovim of mdpeek's editor pane to mdpeek, over the socket in $MDPEEK_SOCKET.
-- Loaded with --cmd, before the user's configuration. Both sides send JSON objects, one per
-- line: Neovim reports the first line shown in a window, the line of the cursor, whether any
-- buffer has unsaved changes and its background color, and mdpeek asks it to open the files it displays and to
-- scroll to the line at the top of the preview. $MDPEEK_LINE, if set, is the line to show
-- the file at once Neovim's terminal UI has attached, which sets the size of its windows.

local channel
local partial = ""

local function send(message)
  vim.fn.chansend(channel, vim.json.encode(message) .. "\n")
end

local function scroll_state(window)
  local buffer = vim.api.nvim_win_get_buf(window)
  if vim.bo[buffer].buftype ~= "" then
    return nil
  end
  return { event = "scroll", path = vim.api.nvim_buf_get_name(buffer), line = vim.fn.line("w0", window) }
end

-- No reports while Neovim starts, or opens a file for mdpeek: either side's position may
-- win, which `position` settles.
local quiet = true

local last_scroll
local function report_scroll(window, force)
  if quiet then
    return
  end
  local scroll = scroll_state(window)
  if scroll and (force or not vim.deep_equal(scroll, last_scroll)) then
    last_scroll = scroll
    send(scroll)
  end
end

-- Scrolls the window showing the file at `path` (the current one if it does) so that `line`
-- is at the top, without reporting it back. Scrolls as CTRL-E and CTRL-Y do, which move the
-- cursor only as far as needed to keep it in view. They skip concealed lines and closed
-- folds, so a count can overshoot: a few passes settle on the line, or next to it if it is
-- hidden.
local function scroll_to(path, line)
  local target = vim.fn.resolve(path)
  local windows = vim.api.nvim_tabpage_list_wins(0)
  table.insert(windows, 1, vim.api.nvim_get_current_win())
  for _, window in ipairs(windows) do
    if vim.fn.resolve(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window))) == target then
      for _ = 1, 3 do
        local delta = line - vim.fn.line("w0", window)
        if delta == 0 then
          break
        end
        vim.api.nvim_win_call(window, function()
          vim.cmd("normal! " .. math.abs(delta) .. vim.keycode(delta > 0 and "<C-e>" or "<C-y>"))
        end)
      end
      last_scroll = scroll_state(window)
      return
    end
  end
end

-- Shows `line` of the file at `path` at the top if given, and otherwise reports where the
-- current window shows its file.
local function position(path, line)
  if line then
    scroll_to(path, line)
  else
    report_scroll(vim.api.nvim_get_current_win(), true)
  end
end

local function handle(message)
  if message.command == "open" then
    quiet = true
    local ok, err = pcall(vim.cmd, "drop " .. vim.fn.fnameescape(message.path))
    quiet = false
    if not ok then
      error(err, 0)
    end
    position(message.path, message.line)
  elseif message.command == "scroll" then
    scroll_to(message.path, message.line)
  else
    error("mdpeek: unknown command " .. vim.inspect(message))
  end
end

-- `data` is the received text split at newlines: its first item continues the previous
-- incomplete line and its last item starts the next one.
local function receive(_, data)
  partial = partial .. data[1]
  for i = 2, #data do
    handle(vim.json.decode(partial))
    partial = data[i]
  end
end

channel = vim.fn.sockconnect("pipe", vim.env.MDPEEK_SOCKET, { on_data = receive })

local modified = false
local function report_modified()
  local any = vim.iter(vim.api.nvim_list_bufs()):any(function(buffer)
    return vim.bo[buffer].modified and vim.bo[buffer].buftype == ""
  end)
  if any ~= modified then
    modified = any
    send({ event = "modified", value = any })
  end
end

-- Reports the cursor's line in the current file, at most every 50 ms, so the preview can
-- outline the block it is in.
local cursor_timer = vim.uv.new_timer()
local cursor_scheduled = false
local last_cursor
local function report_cursor()
  local buffer = vim.api.nvim_get_current_buf()
  if vim.bo[buffer].buftype ~= "" then
    return
  end
  local cursor = { event = "cursor", path = vim.api.nvim_buf_get_name(buffer), line = vim.api.nvim_win_get_cursor(0)[1] }
  if not vim.deep_equal(cursor, last_cursor) then
    last_cursor = cursor
    send(cursor)
  end
end

local function schedule_cursor_report()
  if cursor_scheduled then
    return
  end
  cursor_scheduled = true
  cursor_timer:start(50, 0, vim.schedule_wrap(function()
    cursor_scheduled = false
    report_cursor()
  end))
end

local function report_background()
  send({ event = "background", color = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg })
end

local group = vim.api.nvim_create_augroup("mdpeek", {})
vim.api.nvim_create_autocmd("UIEnter", {
  group = group,
  once = true,
  callback = function()
    quiet = false
    position(vim.api.nvim_buf_get_name(0), tonumber(vim.env.MDPEEK_LINE))
  end,
})
vim.api.nvim_create_autocmd({ "VimEnter", "ColorScheme" }, { group = group, callback = report_background })
vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = "background",
  callback = function()
    vim.schedule(report_background)
  end,
})
vim.api.nvim_create_autocmd("WinScrolled", {
  group = group,
  callback = function(args)
    report_scroll(tonumber(args.match))
  end,
})
vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function()
    report_scroll(vim.api.nvim_get_current_win())
  end,
})
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
  group = group,
  callback = schedule_cursor_report,
})
-- Deleted buffers are still listed while their autocommands run.
vim.api.nvim_create_autocmd({ "BufModifiedSet", "BufDelete", "BufWipeout" }, {
  group = group,
  callback = function()
    vim.schedule(report_modified)
  end,
})
