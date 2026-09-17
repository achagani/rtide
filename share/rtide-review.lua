-- RTIDE review-first editor entry.
--
-- Loaded by the launcher for a fresh workspace so the editor opens a
-- review-oriented project view instead of a real file buffer. It uses the
-- LazyVim-provided Snacks Explorer (which shows Git status) and waits for
-- plugin loading, so it never depends on the user's own keymaps or config.
--
-- Explicit file arguments bypass this file entirely (the launcher does not
-- source it in that case), preserving direct opening.
--
-- The Snacks Explorer sidebar clamps to whatever width exists when it opens.
-- RTIDE starts the editor before it finishes splitting panes, so the editor can
-- briefly be one column wide and then widen (or the reverse). This module
-- reconciles the view against the *current* pane width on every resize: it opens
-- only when there is room, closes a clamped sidebar, and never leaves a sliver
-- behind. `vim.o.columns` reflects this nvim process's pane width, which is the
-- width the sidebar will actually occupy.

local M = {}

-- Pane width required before the sidebar is shown, and the sidebar width below
-- which an open sidebar is considered clamped and must be reopened.
M.MIN_COLUMNS = tonumber(vim.env.RTIDE_REVIEW_MIN_COLUMNS or "") or 40
M.MIN_SIDEBAR = tonumber(vim.env.RTIDE_REVIEW_MIN_SIDEBAR or "") or 30

local directory = nil
local timer = nil

local function notify(message)
  pcall(vim.notify, message, vim.log.levels.WARN)
end

local function pane_width()
  return vim.o.columns
end

local function snacks()
  local ok, module = pcall(require, "snacks")
  if not ok or type(module.explorer) ~= "table"
      or type(module.explorer.open) ~= "function" then
    return nil
  end
  return module
end

-- The open explorer picker, if any.
local function explorer_picker()
  local module = snacks()
  if not module or type(module.picker) ~= "table"
      or type(module.picker.get) ~= "function" then
    return nil
  end
  for _, picker in ipairs(module.picker.get() or {}) do
    if picker.source == "explorer" then
      return picker
    end
  end
  return nil
end

-- Width of the sidebar's list window, used to detect a clamped layout.
local function sidebar_width(picker)
  for _, win in ipairs({ picker.main, picker.list, picker.win }) do
    if type(win) == "number" and vim.api.nvim_win_is_valid(win) then
      return vim.api.nvim_win_get_width(win)
    end
  end
  return 0
end

local function close_explorer()
  local picker = explorer_picker()
  if picker then
    pcall(function()
      picker:close()
    end)
  end
end

-- Open the explorer, leaving no real file buffer selected.
local function open_explorer()
  local module = snacks()
  if not module then
    notify("rtide: Snacks Explorer is unavailable; open a file to begin")
    return false
  end
  local buffer = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buffer) == "" then
    vim.bo[buffer].buflisted = false
  end
  return pcall(module.explorer.open, {
    cwd = directory,
    git_status = true,
    git_status_open = true,
    follow_file = false,
  })
end

-- Reconcile the view with the current pane width. Safe to call repeatedly.
function M.reconcile()
  if not directory or not snacks() then
    return
  end
  local picker = explorer_picker()
  local width = pane_width()

  if width < M.MIN_COLUMNS then
    -- No room: remove any existing (clamped) sidebar.
    if picker then
      close_explorer()
    end
    return
  end

  if not picker then
    open_explorer()
    return
  end

  -- A sidebar that opened narrower than its minimum is clamped; reopen it now
  -- that the pane has room.
  if sidebar_width(picker) < M.MIN_SIDEBAR then
    close_explorer()
    open_explorer()
  end
end

-- Public entry point: open the review view for a directory. Returns true when
-- the explorer is shown at a usable width.
function M.open(path)
  directory = path or directory or vim.fn.getcwd()
  if pane_width() < M.MIN_COLUMNS then
    return false
  end
  if explorer_picker() then
    return true
  end
  return open_explorer()
end

-- Defer a reconciliation so rapid sequential resizes settle into one pass.
local function schedule_reconcile()
  if timer then
    pcall(vim.fn.timer_stop, timer)
  end
  timer = vim.defer_fn(function()
    timer = nil
    M.reconcile()
  end, 150)
end

-- Watch for a usable pane width and open the review view.
function M.setup(directory_path)
  directory = directory_path
  local group = vim.api.nvim_create_augroup("rtide_review", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = schedule_reconcile,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VeryLazy",
    nested = true,
    callback = schedule_reconcile,
  })
  schedule_reconcile()
end

return M
