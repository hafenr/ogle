-- Connects the Neovim of mdpeek's editor pane to mdpeek, over the socket in $MDPEEK_SOCKET.
-- Loaded with --cmd, before the user's configuration. Both sides send JSON objects, one per
-- line: Neovim reports the first line shown in a window, whether any buffer has unsaved
-- changes and its background color, and mdpeek asks it to open the files it displays.

local channel
local partial = ""

local function send(message)
  vim.fn.chansend(channel, vim.json.encode(message) .. "\n")
end

local function handle(message)
  if message.command == "open" then
    vim.cmd("drop " .. vim.fn.fnameescape(message.path))
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

local last_scroll
local function report_scroll(window)
  local buffer = vim.api.nvim_win_get_buf(window)
  if vim.bo[buffer].buftype ~= "" then
    return
  end
  local scroll = { event = "scroll", path = vim.api.nvim_buf_get_name(buffer), line = vim.fn.line("w0", window) }
  if not vim.deep_equal(scroll, last_scroll) then
    last_scroll = scroll
    send(scroll)
  end
end

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

local function report_background()
  send({ event = "background", color = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg })
end

local group = vim.api.nvim_create_augroup("mdpeek", {})
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
-- Deleted buffers are still listed while their autocommands run.
vim.api.nvim_create_autocmd({ "BufModifiedSet", "BufDelete", "BufWipeout" }, {
  group = group,
  callback = function()
    vim.schedule(report_modified)
  end,
})
