describe("albus-conflictius.celebrate", function()
  local celebrate

  before_each(function()
    package.loaded["albus-conflictius.celebrate"] = nil
    package.loaded["albus-conflictius.banner"] = nil
    celebrate = require("albus-conflictius.celebrate")
  end)

  describe("frame", function()
    it("returns the same number of lines for every frame", function()
      local height = #celebrate.frame(1)
      for i = 1, celebrate.frame_count() * 2 do
        assert.are.equal(height, #celebrate.frame(i))
      end
    end)

    it("wraps around after frame_count() frames", function()
      assert.are.same(celebrate.frame(1), celebrate.frame(celebrate.frame_count() + 1))
    end)

    it("includes the wizard art and the celebration message", function()
      local lines = celebrate.frame(1)
      local joined = table.concat(lines, "\n")
      assert.is_true(joined:find("CONFLICT", 1, true) ~= nil)
      local banner = require("albus-conflictius.banner")
      local art_first_line = banner.art()[1]
      assert.is_true(joined:find(art_first_line, 1, true) ~= nil)
    end)

    it("produces different content across at least some frames (it actually animates)", function()
      local all_same = true
      local first = table.concat(celebrate.frame(1), "\n")
      for i = 2, celebrate.frame_count() do
        if table.concat(celebrate.frame(i), "\n") ~= first then
          all_same = false
          break
        end
      end
      assert.is_false(all_same)
    end)

    it("mirrors the wizard art on alternating frames", function()
      local function wizard_lines(lines)
        local out = {}
        for i = 3, #lines - 3 do
          table.insert(out, lines[i])
        end
        return out
      end

      local odd = wizard_lines(celebrate.frame(1))
      local even = wizard_lines(celebrate.frame(2))
      assert.are_not.same(odd, even)
    end)

    it("keeps a fixed message across frames instead of picking a new one each time", function()
      local lines1 = celebrate.frame(1, "CUSTOM MESSAGE")
      local lines2 = celebrate.frame(3, "CUSTOM MESSAGE")
      assert.is_true(lines1[#lines1]:find("CUSTOM MESSAGE", 1, true) ~= nil)
      assert.is_true(lines2[#lines2]:find("CUSTOM MESSAGE", 1, true) ~= nil)
    end)

    it("returns highlight marks covering sparkles, the laser, and the border", function()
      local _, highlights = celebrate.frame(1, "MSG")
      local groups = {}
      for _, h in ipairs(highlights) do
        groups[h.hl_group] = true
      end

      assert.is_true(groups["AlbusConflictiusLaser"])
      assert.is_true(groups["AlbusConflictiusBorder"])

      local has_spark = false
      for _, name in ipairs({
        "AlbusConflictiusSpark1",
        "AlbusConflictiusSpark2",
        "AlbusConflictiusSpark3",
        "AlbusConflictiusSpark4",
      }) do
        if groups[name] then
          has_spark = true
        end
      end
      assert.is_true(has_spark)
    end)
  end)

  describe("random_message", function()
    it("always returns one of the configured messages", function()
      for _ = 1, 20 do
        local msg = celebrate.random_message()
        local found = false
        for _, m in ipairs(celebrate.MESSAGES) do
          if m == msg then
            found = true
          end
        end
        assert.is_true(found)
      end
    end)
  end)

  describe("play", function()
    local function open_scratch_win()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        width = 10,
        height = 5,
        row = 0,
        col = 0,
        style = "minimal",
      })
      return bufnr, win
    end

    it("renders the first frame (with the chosen message) immediately into the buffer", function()
      local bufnr, win = open_scratch_win()
      celebrate.play(bufnr, win, function() end, { total_frames = 1, interval_ms = 10000, message = "PINNED" })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.same(celebrate.frame(1, "PINNED"), lines)

      vim.api.nvim_win_close(win, true)
    end)

    it("resizes the window to fit the animation", function()
      local bufnr, win = open_scratch_win()
      celebrate.play(bufnr, win, function() end, { total_frames = 1, interval_ms = 10000, message = "PINNED" })

      local config = vim.api.nvim_win_get_config(win)
      local expected_height = #celebrate.frame(1, "PINNED")
      assert.are.equal(expected_height, config.height)

      vim.api.nvim_win_close(win, true)
    end)

    it("calls on_done when a skip key is pressed", function()
      local bufnr, win = open_scratch_win()
      local done = false
      celebrate.play(bufnr, win, function()
        done = true
      end, { total_frames = 100, interval_ms = 10000 })

      vim.api.nvim_win_call(win, function()
        vim.cmd("normal q")
      end)

      assert.is_true(done)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)

    it("calls on_done on its own once total_frames elapses", function()
      local bufnr, win = open_scratch_win()
      local done = false
      celebrate.play(bufnr, win, function()
        done = true
      end, { total_frames = 2, interval_ms = 1 })

      vim.wait(200, function()
        return done
      end)

      assert.is_true(done)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)
  end)
end)
