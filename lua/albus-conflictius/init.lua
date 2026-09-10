local M = {}

local config = require("albus-conflictius.config")
local wand = require("albus-conflictius.wand")
local banner = require("albus-conflictius.banner")

local git = require("albus-conflictius.git")
local dashboard = require("albus-conflictius.dashboard")
local resolve_view = require("albus-conflictius.resolve_view")
local watcher = require("albus-conflictius.watcher")

function M._set_git(fake)
  git = fake
end

function M._set_dashboard(fake)
  dashboard = fake
end

function M._set_resolve_view(fake)
  resolve_view = fake
end

function M._set_watcher(fake)
  watcher = fake
end

local dashboard_handle = nil

local function cwd()
  return vim.fn.getcwd()
end

local function refresh_dashboard()
  if not dashboard_handle then
    return
  end

  local files = git.conflicted_files(cwd())
  if #files == 0 and config.get().celebrate then
    local handle = dashboard_handle
    dashboard.celebrate(handle, function()
      dashboard.close(handle)
    end)
    return
  end

  dashboard.refresh(dashboard_handle, files)
end

local function open_file(path)
  resolve_view.open(cwd(), path, {
    on_resolved = function(resolved_path)
      if config.get().auto_stage then
        git.stage(cwd(), resolved_path)
      end
      refresh_dashboard()
    end,
  })
end

local function notify_wand_result(path, resolved_count, remaining_count)
  if resolved_count == 0 and remaining_count == 0 then
    vim.notify("albus-conflictius: " .. path .. " had no conflict markers", vim.log.levels.INFO)
  elseif remaining_count == 0 then
    vim.notify(
      string.format(
        "albus-conflictius: %s fully resolved (%d hunk%s)",
        path,
        resolved_count,
        resolved_count == 1 and "" or "s"
      ),
      vim.log.levels.INFO
    )
  else
    vim.notify(
      string.format(
        "albus-conflictius: %s — %d resolved, %d still need manual resolution",
        path,
        resolved_count,
        remaining_count
      ),
      vim.log.levels.WARN
    )
  end
end

function M.wand_file(path, wand_opts)
  wand_opts = wand_opts or {}
  local full_path = cwd() .. "/" .. path
  local file = io.open(full_path, "r")
  if not file then
    vim.notify("albus-conflictius: could not read " .. path .. " (skipped)", vim.log.levels.WARN)
    return { resolved_count = 0, remaining_count = 0 }
  end
  local content = file:read("*a")
  file:close()

  local new_content, resolved_count, remaining_count = wand.resolve_content(content)

  local out = io.open(full_path, "w")
  if not out then
    vim.notify("albus-conflictius: could not write " .. path .. " (skipped)", vim.log.levels.WARN)
    return { resolved_count = 0, remaining_count = 0 }
  end
  out:write(new_content)
  out:close()

  local bufnr = vim.fn.bufnr(full_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("edit!")
    end)
  end

  if remaining_count == 0 and config.get().auto_stage then
    git.stage(cwd(), path)
  end

  if not wand_opts.silent then
    notify_wand_result(path, resolved_count, remaining_count)
  end

  refresh_dashboard()

  return { resolved_count = resolved_count, remaining_count = remaining_count }
end

function M.wand_all()
  local total = { resolved_count = 0, remaining_count = 0 }
  local file_count = 0
  for _, path in ipairs(git.conflicted_files(cwd())) do
    local summary = M.wand_file(path, { silent = true })
    total.resolved_count = total.resolved_count + summary.resolved_count
    total.remaining_count = total.remaining_count + summary.remaining_count
    file_count = file_count + 1
  end

  vim.notify(
    string.format(
      "albus-conflictius: wanded %d file%s — %d resolved, %d still need manual resolution",
      file_count,
      file_count == 1 and "" or "s",
      total.resolved_count,
      total.remaining_count
    ),
    vim.log.levels.INFO
  )

  return total
end

function M.help()
  banner.show_help()
end

-- If a dashboard is already open (e.g. the watcher's fs_event re-fires because our own
-- stage/resolve just changed the conflict count, not because something new actually appeared),
-- refresh it in place instead of opening a second one stacked on top of the first.
local function open_dashboard(files, show_banner)
  if dashboard_handle and vim.api.nvim_win_is_valid(dashboard_handle.win) then
    dashboard.refresh(dashboard_handle, files)
    return
  end

  dashboard_handle = dashboard.open(files, {
    show_banner = show_banner,
    on_open = open_file,
    on_wand = function(path)
      M.wand_file(path)
    end,
    on_wand_all = function()
      M.wand_all()
    end,
    on_help = M.help,
  })
end

function M.open()
  local files = git.conflicted_files(cwd())
  if #files == 0 then
    vim.notify("albus-conflictius: no conflicts found", vim.log.levels.INFO)
    return
  end
  open_dashboard(files, false)
end

local function auto_open(files)
  open_dashboard(files, config.get().banner)
end

function M.setup(opts)
  config.setup(opts)
  git.ensure_diff3_style(cwd())
  watcher.setup(auto_open, { git = git })
end

return M
