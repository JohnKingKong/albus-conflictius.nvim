local M = {}

local uv = vim.uv or vim.loop

local function default_run_fn(cmd, opts)
  local result = vim.system(cmd, { cwd = opts.cwd, text = true }):wait()
  return { code = result.code, stdout = result.stdout or "", stderr = result.stderr or "" }
end

local run_fn = default_run_fn

function M._set_run_fn(fn)
  run_fn = fn
end

function M._reset_run_fn()
  run_fn = default_run_fn
end

-- `vim.fn.getcwd()` can return an empty string if the process's working directory has been
-- removed out from under it (e.g. the directory was deleted while Neovim was still open in it) --
-- vim.system throws on an invalid cwd, so guard here rather than let every caller crash.
function M.run(cwd, args)
  if not cwd or cwd == "" then
    return { code = 1, stdout = "", stderr = "albus-conflictius: invalid cwd" }
  end

  local cmd = { "git" }
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end
  return run_fn(cmd, { cwd = cwd })
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.git_dir(cwd)
  local result = M.run(cwd, { "rev-parse", "--git-dir" })
  if result.code ~= 0 then
    return nil
  end
  local dir = trim(result.stdout)
  if dir == "" then
    return nil
  end
  if dir:sub(1, 1) ~= "/" then
    dir = cwd .. "/" .. dir
  end
  return dir
end

local IN_PROGRESS_MARKERS = {
  "MERGE_HEAD",
  "CHERRY_PICK_HEAD",
  "rebase-merge",
  "rebase-apply",
}

function M.in_progress(cwd)
  local git_dir = M.git_dir(cwd)
  if not git_dir then
    return false
  end
  for _, marker in ipairs(IN_PROGRESS_MARKERS) do
    if uv.fs_stat(git_dir .. "/" .. marker) then
      return true
    end
  end
  return false
end

function M.conflicted_files(cwd)
  local result = M.run(cwd, { "diff", "--name-only", "--diff-filter=U" })
  local files = {}
  if result.code ~= 0 then
    return files
  end
  for line in result.stdout:gmatch("[^\n]+") do
    table.insert(files, line)
  end
  return files
end

-- Non-blocking counterparts of run/in_progress/conflicted_files, for call
-- sites that run on frequent/background events (FocusGained, fs-watcher
-- callbacks) where a synchronous `git` subprocess would otherwise freeze
-- the editor on every trigger -- most noticeably on a large repo.
local async_run_fn = function(cmd, opts, callback)
  vim.system(cmd, { cwd = opts.cwd, text = true }, function(result)
    vim.schedule(function()
      callback({ code = result.code, stdout = result.stdout or "", stderr = result.stderr or "" })
    end)
  end)
end

function M._set_async_run_fn(fn)
  async_run_fn = fn
end

function M._reset_async_run_fn()
  async_run_fn = function(cmd, opts, callback)
    vim.system(cmd, { cwd = opts.cwd, text = true }, function(result)
      vim.schedule(function()
        callback({ code = result.code, stdout = result.stdout or "", stderr = result.stderr or "" })
      end)
    end)
  end
end

function M.run_async(cwd, args, callback)
  if not cwd or cwd == "" then
    callback({ code = 1, stdout = "", stderr = "albus-conflictius: invalid cwd" })
    return
  end
  local cmd = { "git" }
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end
  async_run_fn(cmd, { cwd = cwd }, callback)
end

function M.git_dir_async(cwd, callback)
  M.run_async(cwd, { "rev-parse", "--git-dir" }, function(result)
    if result.code ~= 0 then
      callback(nil)
      return
    end
    local dir = trim(result.stdout)
    if dir == "" then
      callback(nil)
      return
    end
    if dir:sub(1, 1) ~= "/" then
      dir = cwd .. "/" .. dir
    end
    callback(dir)
  end)
end

function M.in_progress_async(cwd, callback)
  M.git_dir_async(cwd, function(git_dir)
    if not git_dir then
      callback(false)
      return
    end
    for _, marker in ipairs(IN_PROGRESS_MARKERS) do
      if uv.fs_stat(git_dir .. "/" .. marker) then
        callback(true)
        return
      end
    end
    callback(false)
  end)
end

function M.conflicted_files_async(cwd, callback)
  M.run_async(cwd, { "diff", "--name-only", "--diff-filter=U" }, function(result)
    local files = {}
    if result.code == 0 then
      for line in result.stdout:gmatch("[^\n]+") do
        table.insert(files, line)
      end
    end
    callback(files)
  end)
end

local DIFF3_STYLES = { diff3 = true, zdiff3 = true }

function M.ensure_diff3_style(cwd)
  local current = M.run(cwd, { "config", "merge.conflictstyle" })
  local style = current.code == 0 and trim(current.stdout) or nil
  if style and DIFF3_STYLES[style] then
    return false
  end
  M.run(cwd, { "config", "merge.conflictstyle", "diff3" })
  return true
end

function M.stage(cwd, path)
  local result = M.run(cwd, { "add", "--", path })
  return result.code == 0
end

function M.show(cwd, stage, path)
  local result = M.run(cwd, { "show", ":" .. tostring(stage) .. ":" .. path })
  if result.code ~= 0 then
    return nil
  end
  return result.stdout
end

return M
