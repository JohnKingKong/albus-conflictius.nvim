describe("albus-conflictius.init", function()
  local albus
  local tmpdir
  local original_cwd

  before_each(function()
    for _, name in ipairs({
      "albus-conflictius",
      "albus-conflictius.config",
      "albus-conflictius.git",
      "albus-conflictius.wand",
      "albus-conflictius.dashboard",
      "albus-conflictius.resolve_view",
      "albus-conflictius.watcher",
      "albus-conflictius.banner",
    }) do
      package.loaded[name] = nil
    end
    albus = require("albus-conflictius")

    original_cwd = vim.fn.getcwd()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    vim.cmd("cd " .. vim.fn.fnameescape(tmpdir))
    -- On macOS, tempname() paths go through /var, which is a symlink to
    -- /private/var; getcwd() reports the resolved path. Re-read tmpdir from
    -- getcwd() so string comparisons against cwd()-derived values agree.
    tmpdir = vim.fn.getcwd()
  end)

  after_each(function()
    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.fn.delete(tmpdir, "rf")
  end)

  local function write_conflict_file(path, content)
    local file = io.open(tmpdir .. "/" .. path, "w")
    file:write(content)
    file:close()
  end

  describe("wand_file", function()
    it("resolves the file and stages it when nothing remains conflicted", function()
      write_conflict_file(
        "clean.txt",
        table.concat({
          "<<<<<<< HEAD",
          "same",
          "||||||| base",
          "same",
          "=======",
          "changed",
          ">>>>>>> branch",
        }, "\n")
      )

      local staged_path
      albus._set_git({
        stage = function(_, path)
          staged_path = path
          return true
        end,
      })
      albus._set_dashboard({
        open = function() end,
        refresh = function() end,
        close = function() end,
      })

      local summary = albus.wand_file("clean.txt")

      assert.are.equal(1, summary.resolved_count)
      assert.are.equal(0, summary.remaining_count)
      assert.are.equal("clean.txt", staged_path)

      local file = io.open(tmpdir .. "/clean.txt", "r")
      local content = file:read("*a")
      file:close()
      assert.are.equal("changed", content)
    end)

    it("does not stage when a real conflict remains", function()
      write_conflict_file(
        "messy.txt",
        table.concat({
          "<<<<<<< HEAD",
          "ours",
          "||||||| base",
          "original",
          "=======",
          "theirs",
          ">>>>>>> branch",
        }, "\n")
      )

      local staged = false
      albus._set_git({
        stage = function()
          staged = true
          return true
        end,
      })
      albus._set_dashboard({
        open = function() end,
        refresh = function() end,
        close = function() end,
      })

      local summary = albus.wand_file("messy.txt")

      assert.are.equal(0, summary.resolved_count)
      assert.are.equal(1, summary.remaining_count)
      assert.is_false(staged)
    end)

    it("respects auto_stage = false", function()
      write_conflict_file(
        "clean2.txt",
        table.concat({ "<<<<<<< HEAD", "same", "||||||| base", "same", "=======", "changed", ">>>>>>> branch" }, "\n")
      )

      local staged = false
      albus.setup({ auto_stage = false })
      albus._set_git({
        stage = function()
          staged = true
          return true
        end,
      })
      albus._set_dashboard({
        open = function() end,
        refresh = function() end,
        close = function() end,
      })

      albus.wand_file("clean2.txt")

      assert.is_false(staged)
    end)
  end)

  describe("wand_file robustness", function()
    it("notifies and returns zero counts when the file cannot be read", function()
      local notified
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        notified = { msg = msg, level = level }
      end

      albus._set_dashboard({ open = function() end, refresh = function() end, close = function() end })

      local summary = albus.wand_file("does-not-exist.txt")

      vim.notify = original_notify
      assert.are.equal(0, summary.resolved_count)
      assert.are.equal(0, summary.remaining_count)
      assert.is_true(notified.msg:find("could not read", 1, true) ~= nil)
    end)

    it("reloads an already-open buffer for the resolved file so it doesn't show stale content", function()
      write_conflict_file(
        "open-buf.txt",
        table.concat({ "<<<<<<< HEAD", "same", "||||||| base", "same", "=======", "changed", ">>>>>>> branch" }, "\n")
      )

      vim.cmd("edit " .. tmpdir .. "/open-buf.txt")
      local bufnr = vim.api.nvim_get_current_buf()

      albus._set_git({ stage = function() end })
      albus._set_dashboard({ open = function() end, refresh = function() end, close = function() end })

      albus.wand_file("open-buf.txt")

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.same({ "changed" }, lines)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("wand_all", function()
    it("runs the wand across every conflicted file reported by git", function()
      write_conflict_file(
        "a.txt",
        table.concat({ "<<<<<<< HEAD", "x", "||||||| base", "x", "=======", "y", ">>>>>>> branch" }, "\n")
      )
      write_conflict_file(
        "b.txt",
        table.concat({ "<<<<<<< HEAD", "x", "||||||| base", "x", "=======", "y", ">>>>>>> branch" }, "\n")
      )

      local staged = {}
      albus._set_git({
        conflicted_files = function()
          return { "a.txt", "b.txt" }
        end,
        stage = function(_, path)
          table.insert(staged, path)
          return true
        end,
      })
      albus._set_dashboard({
        open = function() end,
        refresh = function() end,
        close = function() end,
      })

      local summary = albus.wand_all()

      assert.are.equal(2, summary.resolved_count)
      table.sort(staged)
      assert.are.same({ "a.txt", "b.txt" }, staged)
    end)
  end)

  describe("open", function()
    it("opens the dashboard with the repo's currently conflicted files", function()
      local opened_files
      albus._set_git({
        conflicted_files = function()
          return { "a.txt" }
        end,
      })
      albus._set_dashboard({
        open = function(files)
          opened_files = files
          return { win = -1, bufnr = -1 }
        end,
        refresh = function() end,
        close = function() end,
      })

      albus.open()

      assert.are.same({ "a.txt" }, opened_files)
    end)

    it("notifies instead of opening when there are no conflicts", function()
      local notified
      local original_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end

      albus._set_git({
        conflicted_files = function()
          return {}
        end,
      })
      local opened = false
      albus._set_dashboard({
        open = function()
          opened = true
          return { win = -1, bufnr = -1 }
        end,
        refresh = function() end,
        close = function() end,
      })

      albus.open()

      vim.notify = original_notify
      assert.is_false(opened)
      assert.is_true(notified:find("no conflicts", 1, true) ~= nil)
    end)
  end)

  describe("setup", function()
    it("calls git.ensure_diff3_style with the current cwd", function()
      local ensured_cwd
      albus._set_watcher({ setup = function() end })
      albus._set_git({
        ensure_diff3_style = function(cwd_arg)
          ensured_cwd = cwd_arg
        end,
      })

      albus.setup({})

      assert.are.equal(tmpdir, ensured_cwd)
    end)
  end)

  describe("auto_open (watcher callback) banner passthrough", function()
    it("passes show_banner = true when config.banner is true", function()
      local captured_show_banner
      local on_new_conflicts
      albus._set_git({ ensure_diff3_style = function() end })
      albus._set_watcher({
        setup = function(callback)
          on_new_conflicts = callback
        end,
      })
      albus._set_dashboard({
        open = function(_files, opts)
          captured_show_banner = opts.show_banner
          return { win = -1, bufnr = -1 }
        end,
        refresh = function() end,
        close = function() end,
      })

      albus.setup({ banner = true })
      on_new_conflicts({ "a.txt" })

      assert.is_true(captured_show_banner)
    end)

    it("passes show_banner = false when config.banner is false", function()
      local captured_show_banner
      local on_new_conflicts
      albus._set_git({ ensure_diff3_style = function() end })
      albus._set_watcher({
        setup = function(callback)
          on_new_conflicts = callback
        end,
      })
      albus._set_dashboard({
        open = function(_files, opts)
          captured_show_banner = opts.show_banner
          return { win = -1, bufnr = -1 }
        end,
        refresh = function() end,
        close = function() end,
      })

      albus.setup({ banner = false })
      on_new_conflicts({ "a.txt" })

      assert.is_false(captured_show_banner)
    end)
  end)

  describe("resolve_view on_resolved -> auto_stage", function()
    it("stages the file when auto_stage is true", function()
      local staged_path
      local captured_on_open
      require("albus-conflictius.config").setup({ auto_stage = true })
      albus._set_git({
        conflicted_files = function()
          return { "a.txt" }
        end,
        stage = function(_, path)
          staged_path = path
        end,
      })
      albus._set_dashboard({
        open = function(_files, opts)
          captured_on_open = opts.on_open
          return { win = -1, bufnr = -1 }
        end,
        refresh = function() end,
        close = function() end,
      })
      albus._set_resolve_view({
        open = function(_cwd, path, ropts)
          ropts.on_resolved(path)
        end,
      })

      albus.open()
      captured_on_open("a.txt")

      assert.are.equal("a.txt", staged_path)
    end)

    it("does not stage when auto_stage is false", function()
      local staged = false
      local captured_on_open
      require("albus-conflictius.config").setup({ auto_stage = false })
      albus._set_git({
        conflicted_files = function()
          return { "a.txt" }
        end,
        stage = function()
          staged = true
        end,
      })
      albus._set_dashboard({
        open = function(_files, opts)
          captured_on_open = opts.on_open
          return { win = -1, bufnr = -1 }
        end,
        refresh = function() end,
        close = function() end,
      })
      albus._set_resolve_view({
        open = function(_cwd, path, ropts)
          ropts.on_resolved(path)
        end,
      })

      albus.open()
      captured_on_open("a.txt")

      assert.is_false(staged)
    end)
  end)

  describe("refresh_dashboard celebration", function()
    it("celebrates instead of refreshing when the last conflict is resolved and celebrate=true", function()
      write_conflict_file(
        "only.txt",
        table.concat({ "<<<<<<< HEAD", "same", "||||||| base", "same", "=======", "changed", ">>>>>>> branch" }, "\n")
      )

      local conflicted_calls = 0
      local celebrate_called, refresh_called = false, false

      require("albus-conflictius.config").setup({ celebrate = true })
      albus._set_git({
        conflicted_files = function()
          conflicted_calls = conflicted_calls + 1
          if conflicted_calls == 1 then
            return { "only.txt" }
          end
          return {}
        end,
        stage = function() end,
      })
      albus._set_dashboard({
        open = function()
          return { win = -1, bufnr = -1 }
        end,
        refresh = function()
          refresh_called = true
        end,
        close = function() end,
        celebrate = function(_handle, on_done)
          celebrate_called = true
          on_done()
        end,
      })

      albus.open()
      albus.wand_file("only.txt")

      assert.is_true(celebrate_called)
      assert.is_false(refresh_called)
    end)

    it("falls back to a normal refresh when celebrate=false", function()
      write_conflict_file(
        "only2.txt",
        table.concat({ "<<<<<<< HEAD", "same", "||||||| base", "same", "=======", "changed", ">>>>>>> branch" }, "\n")
      )

      local conflicted_calls = 0
      local celebrate_called, refresh_called = false, false

      require("albus-conflictius.config").setup({ celebrate = false })
      albus._set_git({
        conflicted_files = function()
          conflicted_calls = conflicted_calls + 1
          if conflicted_calls == 1 then
            return { "only2.txt" }
          end
          return {}
        end,
        stage = function() end,
      })
      albus._set_dashboard({
        open = function()
          return { win = -1, bufnr = -1 }
        end,
        refresh = function()
          refresh_called = true
        end,
        close = function() end,
        celebrate = function(_handle, on_done)
          celebrate_called = true
          on_done()
        end,
      })

      albus.open()
      albus.wand_file("only2.txt")

      assert.is_false(celebrate_called)
      assert.is_true(refresh_called)
    end)
  end)
end)
