describe("albus-conflictius.watcher", function()
  local watcher

  before_each(function()
    package.loaded["albus-conflictius.watcher"] = nil
    watcher = require("albus-conflictius.watcher")
    watcher._reset_state()
  end)

  local function fake_git(in_progress, files)
    return {
      in_progress = function()
        return in_progress
      end,
      conflicted_files = function()
        return files
      end,
    }
  end

  it("does not fire when nothing is in progress", function()
    local called = false
    watcher._check(fake_git(false, {}), "/repo", function()
      called = true
    end)
    assert.is_false(called)
  end)

  it("does not fire when in progress but no conflicted files yet", function()
    local called = false
    watcher._check(fake_git(true, {}), "/repo", function()
      called = true
    end)
    assert.is_false(called)
  end)

  it("fires once for a newly-detected conflict set", function()
    local received
    watcher._check(fake_git(true, { "a.lua" }), "/repo", function(files)
      received = files
    end)
    assert.are.same({ "a.lua" }, received)
  end)

  it("does not fire again for the same unchanged conflict set", function()
    watcher._check(fake_git(true, { "a.lua" }), "/repo", function() end)
    local called = false
    watcher._check(fake_git(true, { "a.lua" }), "/repo", function()
      called = true
    end)
    assert.is_false(called)
  end)

  it("fires again when the conflict set changes", function()
    watcher._check(fake_git(true, { "a.lua" }), "/repo", function() end)
    local received
    watcher._check(fake_git(true, { "a.lua", "b.lua" }), "/repo", function(files)
      received = files
    end)
    assert.are.same({ "a.lua", "b.lua" }, received)
  end)

  it("fires again after the conflict clears and a new one appears", function()
    watcher._check(fake_git(true, { "a.lua" }), "/repo", function() end)
    watcher._check(fake_git(false, {}), "/repo", function() end)
    local received
    watcher._check(fake_git(true, { "a.lua" }), "/repo", function(files)
      received = files
    end)
    assert.are.same({ "a.lua" }, received)
  end)

  it("tracks dedup state independently per repo", function()
    watcher._check(fake_git(true, { "a.lua" }), "/repo-one", function() end)
    local received
    watcher._check(fake_git(true, { "a.lua" }), "/repo-two", function(files)
      received = files
    end)
    assert.are.same({ "a.lua" }, received)
  end)

  describe("_check_async", function()
    local function fake_git_async(in_progress, files)
      return {
        in_progress_async = function(_cwd, callback)
          callback(in_progress)
        end,
        conflicted_files_async = function(_cwd, callback)
          callback(files)
        end,
      }
    end

    it("fires with both files and cwd for a newly-detected conflict set", function()
      local received_files, received_cwd
      watcher._check_async(fake_git_async(true, { "a.lua" }), "/repo", function(files, cwd)
        received_files, received_cwd = files, cwd
      end)
      assert.are.same({ "a.lua" }, received_files)
      assert.are.equal("/repo", received_cwd)
    end)

    it("does not fire when nothing is in progress", function()
      local called = false
      watcher._check_async(fake_git_async(false, {}), "/repo", function()
        called = true
      end)
      assert.is_false(called)
    end)

    it("shares dedup state with the synchronous _check for the same repo", function()
      watcher._check(fake_git(true, { "a.lua" }), "/repo", function() end)
      local called = false
      watcher._check_async(fake_git_async(true, { "a.lua" }), "/repo", function()
        called = true
      end)
      assert.is_false(called, "async check must not re-fire for a set _check already saw")
    end)
  end)
end)
