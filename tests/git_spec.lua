describe("albus-conflictius.git", function()
  local git

  before_each(function()
    package.loaded["albus-conflictius.git"] = nil
    git = require("albus-conflictius.git")
  end)

  after_each(function()
    git._reset_run_fn()
  end)

  local function stub(handler)
    git._set_run_fn(function(cmd, opts)
      return handler(cmd, opts)
    end)
  end

  describe("run", function()
    it("prepends 'git' and passes cwd through", function()
      local captured_cmd, captured_opts
      stub(function(cmd, opts)
        captured_cmd = cmd
        captured_opts = opts
        return { code = 0, stdout = "ok\n", stderr = "" }
      end)

      local result = git.run("/repo", { "status", "--porcelain=v1" })

      assert.are.same({ "git", "status", "--porcelain=v1" }, captured_cmd)
      assert.are.equal("/repo", captured_opts.cwd)
      assert.are.equal(0, result.code)
      assert.are.equal("ok\n", result.stdout)
    end)
  end)

  describe("git_dir", function()
    it("returns the trimmed stdout of rev-parse --git-dir", function()
      stub(function()
        return { code = 0, stdout = ".git\n", stderr = "" }
      end)
      assert.are.equal("/repo/.git", git.git_dir("/repo"))
    end)

    it("returns nil when not a git repo", function()
      stub(function()
        return { code = 128, stdout = "", stderr = "fatal: not a git repository" }
      end)
      assert.is_nil(git.git_dir("/not-a-repo"))
    end)
  end)

  describe("conflicted_files", function()
    it("splits diff --name-only output into a list", function()
      stub(function()
        return { code = 0, stdout = "a.lua\nb/c.lua\n", stderr = "" }
      end)
      assert.are.same({ "a.lua", "b/c.lua" }, git.conflicted_files("/repo"))
    end)

    it("returns an empty list when there is no output", function()
      stub(function()
        return { code = 0, stdout = "", stderr = "" }
      end)
      assert.are.same({}, git.conflicted_files("/repo"))
    end)
  end)

  describe("ensure_diff3_style", function()
    it("returns false and makes no change when already diff3", function()
      local calls = {}
      stub(function(cmd)
        table.insert(calls, cmd)
        return { code = 0, stdout = "diff3\n", stderr = "" }
      end)
      assert.is_false(git.ensure_diff3_style("/repo"))
      assert.are.equal(1, #calls)
    end)

    it("returns false and makes no change when already zdiff3", function()
      stub(function()
        return { code = 0, stdout = "zdiff3\n", stderr = "" }
      end)
      assert.is_false(git.ensure_diff3_style("/repo"))
    end)

    it("sets diff3 and returns true when unset", function()
      local calls = {}
      stub(function(cmd)
        table.insert(calls, cmd)
        if cmd[3] == "merge.conflictstyle" and #cmd == 3 then
          return { code = 1, stdout = "", stderr = "" }
        end
        return { code = 0, stdout = "", stderr = "" }
      end)
      assert.is_true(git.ensure_diff3_style("/repo"))
      assert.are.same({ "git", "config", "merge.conflictstyle", "diff3" }, calls[2])
    end)
  end)

  describe("stage", function()
    it("runs git add -- <path> and returns true on success", function()
      local captured_cmd
      stub(function(cmd)
        captured_cmd = cmd
        return { code = 0, stdout = "", stderr = "" }
      end)
      assert.is_true(git.stage("/repo", "a.lua"))
      assert.are.same({ "git", "add", "--", "a.lua" }, captured_cmd)
    end)

    it("returns false on failure", function()
      stub(function()
        return { code = 1, stdout = "", stderr = "error" }
      end)
      assert.is_false(git.stage("/repo", "a.lua"))
    end)
  end)

  describe("show", function()
    it("runs git show :<stage>:<path> and returns stdout", function()
      local captured_cmd
      stub(function(cmd)
        captured_cmd = cmd
        return { code = 0, stdout = "content", stderr = "" }
      end)
      assert.are.equal("content", git.show("/repo", 2, "a.lua"))
      assert.are.same({ "git", "show", ":2:a.lua" }, captured_cmd)
    end)

    it("returns nil on failure", function()
      stub(function()
        return { code = 1, stdout = "", stderr = "error" }
      end)
      assert.is_nil(git.show("/repo", 1, "a.lua"))
    end)
  end)

  describe("in_progress", function()
    it("returns true when a merge is in progress", function()
      stub(function(cmd)
        if cmd[2] == "rev-parse" then
          return { code = 0, stdout = "/repo/.git\n", stderr = "" }
        end
        error("unexpected git call: " .. table.concat(cmd, " "))
      end)
      local original_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path)
        if path == "/repo/.git/MERGE_HEAD" then
          return { type = "file" }
        end
        return nil
      end

      local result = git.in_progress("/repo")

      vim.uv.fs_stat = original_stat
      assert.is_true(result)
    end)

    it("returns false when nothing is in progress", function()
      stub(function(cmd)
        if cmd[2] == "rev-parse" then
          return { code = 0, stdout = "/repo/.git\n", stderr = "" }
        end
        error("unexpected git call")
      end)
      local original_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function()
        return nil
      end

      local result = git.in_progress("/repo")

      vim.uv.fs_stat = original_stat
      assert.is_false(result)
    end)
  end)
end)
