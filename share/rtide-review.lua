-- RTIDE review-first editor entry.
--
-- Loaded by the launcher for a fresh workspace so the editor opens a
-- review-oriented project view instead of a real file buffer. It uses the
-- LazyVim-provided Snacks Explorer (which shows Git status) and defers until
-- plugins are loaded, so it never depends on the user's own keymaps or config.
--
-- Explicit file arguments bypass this file entirely (the launcher does not
-- source it in that case), preserving direct opening.

local M = {}

local function notify(message)
  pcall(vim.notify, message, vim.log.levels.WARN)
end

-- Open the review view: Snacks Explorer rooted at the given directory with Git
-- status enabled, and no real file buffer loaded.
function M.open(directory)
  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks.explorer) ~= "table"
      or type(snacks.explorer.open) ~= "function" then
    notify("rtide: Snacks Explorer is unavailable; open a file to begin")
    return false
  end

  -- Leave the initial buffer empty rather than naming a project file.
  local buffer = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buffer) == "" then
    vim.bo[buffer].buflisted = false
  end

  local opened = pcall(snacks.explorer.open, {
    cwd = directory,
    git_status = true,
    git_status_open = true,
    follow_file = false,
  })
  if not opened then
    notify("rtide: could not open the project review view")
    return false
  end
  return true
end

-- Whether Snacks can be required right now (requiring triggers lazy loading).
local function available()
  local ok, snacks = pcall(require, "snacks")
  return ok and type(snacks.explorer) == "table"
    and type(snacks.explorer.open) == "function"
end

-- Open the review view now if possible; otherwise wait for plugins to finish and
-- retry exactly once.
function M.setup(directory)
  local function run()
    if available() then
      vim.schedule(function()
        if not M.open(directory) then
          vim.api.nvim_create_autocmd("User", {
            pattern = "VeryLazy", once = true, nested = true,
            callback = function()
              vim.schedule(function() M.open(directory) end)
            end,
          })
        end
      end)
    else
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy", once = true, nested = true,
        callback = function()
          vim.schedule(function() M.open(directory) end)
        end,
      })
    end
  end
  run()
end

return M
