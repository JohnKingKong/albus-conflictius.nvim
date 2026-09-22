local M = {}

local uv = vim.uv or vim.loop

local last_seen_by_repo = {}
-- Keyed by git_dir, not a single handle: an earlier version replaced this on
-- every DirChanged, so switching between fireplaces silently stopped
-- watching every repo except whichever one was most recently visited.
local fs_event_handles = {}

function M._reset_state()
  last_seen_by_repo = {}
  for _, handle in pairs(fs_event_handles) do
    pcall(handle.stop, handle)
  end
  fs_event_handles = {}
end

-- Pure dedup logic, given already-fetched state -- kept synchronous (and
-- thus easy to unit test with a plain fake git module) even though real
-- callers fetch `in_progress`/`files` asynchronously via _check_async below.
local function apply_check(cwd, in_progress, files, on_new_conflicts)
  if not in_progress or #files == 0 then
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
  on_new_conflicts(files, cwd)
end

function M._check(git_mod, cwd, on_new_conflicts)
  apply_check(cwd, git_mod.in_progress(cwd), git_mod.conflicted_files(cwd), on_new_conflicts)
end

-- Same as _check, but via git_mod's non-blocking variants -- used at every
-- real call site so a check triggered by FocusGained/a background fs event
-- never freezes the editor waiting on a `git` subprocess (most noticeable on
-- a large repo).
function M._check_async(git_mod, cwd, on_new_conflicts)
  git_mod.in_progress_async(cwd, function(in_progress)
    if not in_progress then
      apply_check(cwd, false, {}, on_new_conflicts)
      return
    end
    git_mod.conflicted_files_async(cwd, function(files)
      apply_check(cwd, true, files, on_new_conflicts)
    end)
  end)
end

-- Every open tab's own working directory, deduplicated -- not just "the
-- current" one, so a fireplace you're not currently looking at still gets
-- checked (its conflicts don't just sit undetected until you happen to
-- switch back to it).
local function all_tab_cwds()
  local cwds, seen = {}, {}
  for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    local tabnr = vim.api.nvim_tabpage_get_number(tabid)
    local cwd = vim.fn.getcwd(-1, tabnr)
    if not seen[cwd] then
      seen[cwd] = true
      table.insert(cwds, cwd)
    end
  end
  return cwds
end

local function arm_fs_watcher(git_mod, on_new_conflicts, cwd)
  git_mod.git_dir_async(cwd, function(git_dir)
    if not git_dir or fs_event_handles[git_dir] then
      return
    end

    local handle = uv.new_fs_event()
    if not handle then
      return
    end
    fs_event_handles[git_dir] = handle

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
          M._check_async(git_mod, cwd, on_new_conflicts)
        end)
      )
    end)
  end)
end

local function check_and_arm_all(git_mod, on_new_conflicts)
  for _, cwd in ipairs(all_tab_cwds()) do
    M._check_async(git_mod, cwd, on_new_conflicts)
    arm_fs_watcher(git_mod, on_new_conflicts, cwd)
  end
end

-- Deferred so our dashboard wins any focus race with other startup UI that opens on VimEnter
-- (e.g. neo-tree auto-opening and focusing itself) — since setup() typically runs during plugin
-- config load, well before VimEnter, an immediate dashboard open here would just get its focus
-- stolen the moment VimEnter-time plugins finish opening their own windows afterward.
local function initial_check(git_mod, on_new_conflicts)
  vim.defer_fn(function()
    check_and_arm_all(git_mod, on_new_conflicts)
  end, 100)
end

function M.setup(on_new_conflicts, opts)
  opts = opts or {}
  local git_mod = opts.git or require("albus-conflictius.git")

  local augroup = vim.api.nvim_create_augroup("albus-conflictius-watcher", { clear = true })

  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = augroup,
    callback = function()
      for _, cwd in ipairs(all_tab_cwds()) do
        M._check_async(git_mod, cwd, on_new_conflicts)
      end
    end,
    desc = "albus-conflictius: check for conflicts on focus",
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      local cwd = vim.fn.getcwd()
      M._check_async(git_mod, cwd, on_new_conflicts)
      arm_fs_watcher(git_mod, on_new_conflicts, cwd)
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

  check_and_arm_all(git_mod, on_new_conflicts)
end

return M
