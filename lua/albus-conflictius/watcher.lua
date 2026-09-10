local M = {}

local uv = vim.uv or vim.loop

local last_seen_by_repo = {}
local fs_event_handle = nil

function M._reset_state()
  last_seen_by_repo = {}
end

function M._check(git_mod, cwd, on_new_conflicts)
  if not git_mod.in_progress(cwd) then
    last_seen_by_repo[cwd] = nil
    return
  end

  local files = git_mod.conflicted_files(cwd)
  if #files == 0 then
    last_seen_by_repo[cwd] = nil
    return
  end

  local sorted = vim.deepcopy(files)
  table.sort(sorted)
  local signature = table.concat(sorted, "\n")

  if last_seen_by_repo[cwd] == signature then
    return
  end
  last_seen_by_repo[cwd] = signature
  on_new_conflicts(files)
end

local function arm_fs_watcher(git_mod, on_new_conflicts)
  if fs_event_handle then
    fs_event_handle:stop()
    fs_event_handle = nil
  end

  local cwd = vim.fn.getcwd()
  local git_dir = git_mod.git_dir(cwd)
  if not git_dir then
    return
  end

  local handle = uv.new_fs_event()
  if not handle then
    return
  end
  fs_event_handle = handle

  local debounce_timer = nil
  handle:start(git_dir, {}, function()
    if debounce_timer then
      debounce_timer:stop()
      debounce_timer:close()
    end
    debounce_timer = uv.new_timer()
    debounce_timer:start(
      50,
      0,
      vim.schedule_wrap(function()
        M._check(git_mod, vim.fn.getcwd(), on_new_conflicts)
      end)
    )
  end)
end

-- Deferred so our dashboard wins any focus race with other startup UI that opens on VimEnter
-- (e.g. neo-tree auto-opening and focusing itself) — since setup() typically runs during plugin
-- config load, well before VimEnter, an immediate dashboard open here would just get its focus
-- stolen the moment VimEnter-time plugins finish opening their own windows afterward.
local function initial_check(git_mod, on_new_conflicts)
  vim.defer_fn(function()
    M._check(git_mod, vim.fn.getcwd(), on_new_conflicts)
  end, 100)
end

function M.setup(on_new_conflicts, opts)
  opts = opts or {}
  local git_mod = opts.git or require("albus-conflictius.git")

  local augroup = vim.api.nvim_create_augroup("albus-conflictius-watcher", { clear = true })

  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = augroup,
    callback = function()
      M._check(git_mod, vim.fn.getcwd(), on_new_conflicts)
    end,
    desc = "albus-conflictius: check for conflicts on focus",
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      M._check(git_mod, vim.fn.getcwd(), on_new_conflicts)
      arm_fs_watcher(git_mod, on_new_conflicts)
    end,
    desc = "albus-conflictius: check for conflicts on cwd change",
  })

  if vim.v.vim_did_enter == 1 then
    initial_check(git_mod, on_new_conflicts)
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = augroup,
      once = true,
      callback = function()
        initial_check(git_mod, on_new_conflicts)
      end,
      desc = "albus-conflictius: check for conflicts once Neovim finishes starting",
    })
  end

  arm_fs_watcher(git_mod, on_new_conflicts)
end

return M
