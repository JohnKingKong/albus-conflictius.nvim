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
      assert.is_true(joined:find("ALL CONFLICTS RESOLVED", 1, true) ~= nil)
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

    it("renders the first frame immediately into the buffer", function()
      local bufnr, win = open_scratch_win()
      celebrate.play(bufnr, win, function() end, { total_frames = 1, interval_ms = 10000 })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.same(celebrate.frame(1), lines)

      vim.api.nvim_win_close(win, true)
    end)

    it("resizes the window to fit the animation", function()
      local bufnr, win = open_scratch_win()
      celebrate.play(bufnr, win, function() end, { total_frames = 1, interval_ms = 10000 })

      local config = vim.api.nvim_win_get_config(win)
      local expected_height = #celebrate.frame(1)
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
