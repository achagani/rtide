-- Minimal Snacks stub for the RTIDE review-view tests. It records open/close
-- and can report a clamped sidebar width.
local state = { open = false, opened_cwd = nil, reported_width = 40 }
package.loaded["rtide_snacks_state"] = state
local M = {}
M.explorer = {
  open = function(opts)
    state.opened_cwd = opts and opts.cwd
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "snacks_picker_list"
    state.win = vim.api.nvim_open_win(buf, false, {
      relative = "editor", row = 0, col = 0, width = 40, height = 10,
      style = "minimal", border = "none",
    })
    state.open = true
    return true
  end,
}
local real_width = vim.api.nvim_win_get_width
vim.api.nvim_win_get_width = function(win)
  if state.win and win == state.win then
    return state.reported_width
  end
  return real_width(win)
end
M.picker = {
  get = function()
    if not state.open then
      return {}
    end
    return { {
      source = "explorer",
      main = state.win,
      close = function()
        state.open = false
        if state.win and vim.api.nvim_win_is_valid(state.win) then
          pcall(vim.api.nvim_win_close, state.win, true)
        end
      end,
    } }
  end,
}
return M
