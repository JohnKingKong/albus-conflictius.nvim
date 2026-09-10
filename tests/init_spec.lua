describe("albus-conflictius.init", function()
  local albus
  local tmpdir

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

    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    vim.cmd("cd " .. vim.fn.fnameescape(tmpdir))
  end)

  after_each(function()
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
end)
