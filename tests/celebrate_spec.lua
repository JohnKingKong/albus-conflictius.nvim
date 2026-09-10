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

    it("includes the wizard art (static) and the celebration message", function()
      local lines = celebrate.frame(1)
      local joined = table.concat(lines, "\n")
      assert.is_true(joined:find("CONFLICT", 1, true) ~= nil)
      local banner = require("albus-conflictius.banner")
      local art_first_line = banner.art()[1]
      assert.is_true(joined:find(art_first_line, 1, true) ~= nil)
    end)

    it("keeps the wizard art identical across frames (no motion)", function()
      -- the wizard art is pasted in as-is (not centered against the frame's canvas width -- its
      -- shape depends on each line's own hand-authored leading whitespace), so the raw joined art
      -- should appear verbatim, unchanged, in every frame.
      local banner = require("albus-conflictius.banner")
      local art = table.concat(banner.art(), "\n")
      for i = 1, celebrate.frame_count() do
        local joined = table.concat(celebrate.frame(i), "\n")
        assert.is_true(joined:find(art, 1, true) ~= nil)
      end
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

      -- the laser spark now flashes through the same rainbow palette as the sparkle rows,
      -- rather than a single dedicated color -- just confirm at least one spark color is used.
      assert.is_true(groups["AlbusConflictiusBorder"])

      local has_spark = false
      for _, name in ipairs({
        "AlbusConflictiusSpark1",
        "AlbusConflictiusSpark2",
        "AlbusConflictiusSpark3",
        "AlbusConflictiusSpark4",
        "AlbusConflictiusSpark5",
        "AlbusConflictiusSpark6",
      }) do
        if groups[name] then
          has_spark = true
        end
      end
      assert.is_true(has_spark)
    end)

    it("colors the message text letter-by-letter with multiple distinct colors, not one flat color", function()
      local lines, highlights = celebrate.frame(1, "A LONGER TEST MESSAGE")
      local message_row = #lines - 1 -- 0-based row index of the last line (the message line)

      local colors_on_message_line = {}
      for _, h in ipairs(highlights) do
        if h.row == message_row and h.hl_group ~= "AlbusConflictiusBorder" then
          colors_on_message_line[h.hl_group] = true
        end
      end
      local count = 0
      for _ in pairs(colors_on_message_line) do
        count = count + 1
      end
      assert.is_true(count >= 3)
    end)

    it("uses several distinct spark colors across a frame's sparkle rows, not just one", function()
      local _, highlights = celebrate.frame(1, "MSG")
      local spark_groups = {}
      for _, h in ipairs(highlights) do
        if h.hl_group:match("^AlbusConflictiusSpark%d$") then
          spark_groups[h.hl_group] = true
        end
      end
      local count = 0
      for _ in pairs(spark_groups) do
        count = count + 1
      end
      assert.is_true(count >= 3)
    end)

    it("aligns the sparkle rows, laser row, and message on the same center column", function()
      local lines = celebrate.frame(1, "MSG")
      local function center_col(line)
        local leading = #(line:match("^( *)"))
        local trimmed = line:match("^%s*(.-)%s*$")
        return leading + #trimmed / 2
      end
      local top_center = center_col(lines[1])
      local laser_row_index = #lines - 2 -- message is last, blank before it, laser before that
      local laser_center = center_col(lines[laser_row_index])
      local message_center = center_col(lines[#lines])
      assert.is_true(math.abs(top_center - laser_center) <= 1)
      assert.is_true(math.abs(top_center - message_center) <= 1)
    end)

    it("centers the sparkle/laser rows against the message even when it's much wider than them", function()
      -- long enough that the message line (border + text + border) exceeds the laser/sparkle
      -- width -- this used to clamp their shared reference width, or (in an earlier attempt)
      -- push the unrelated wizard art out of its authored position. Neither should happen: the
      -- message becomes the reference width (little to no padding of its own), and the
      -- laser/sparkle rows pad out to stay centered under it, while the wizard art is untouched.
      local long_message = string.rep("VERY LONG MESSAGE ", 5)
      local lines = celebrate.frame(1, long_message)

      local message_line = lines[#lines]
      assert.is_true(#(message_line:match("^( *)")) <= 1)

      local top_row = lines[1]
      assert.is_true(#(top_row:match("^( *)")) > 0)
      assert.is_true(#top_row <= #message_line)

      local banner = require("albus-conflictius.banner")
      local wizard_first_line = banner.art()[1]
      local wizard_row
      for _, line in ipairs(lines) do
        if line:find(wizard_first_line, 1, true) then
          wizard_row = line
        end
      end
      assert.are.equal(wizard_first_line, wizard_row)
    end)

    it("keeps both sparkle rows solid and exactly as wide as the laser row", function()
      local lines = celebrate.frame(1, "MSG")
      local top_content = lines[1]:match("^ *(.-) *$")
      local bottom_content = lines[2]:match("^ *(.-) *$")
      assert.is_nil(top_content:find("%s"))
      assert.is_nil(bottom_content:find("%s"))
      assert.are.equal(33, #top_content)
      assert.are.equal(33, #bottom_content)
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

    it("vertically centers the frame with blank padding when the window is taller than the content", function()
      local frame_lines = celebrate.frame(1, "PINNED")
      local extra = 10
      -- headless Neovim defaults to a 24-line "screen", too short to actually fit
      -- #frame_lines + extra -- give it enough room so the window isn't silently clamped.
      local original_lines = vim.o.lines
      vim.o.lines = #frame_lines + extra + 10

      local bufnr = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        width = 60,
        height = #frame_lines + extra,
        row = 0,
        col = 0,
        style = "minimal",
      })

      celebrate.play(bufnr, win, function() end, { total_frames = 1, interval_ms = 10000, message = "PINNED" })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local expected_pad = math.floor(extra / 2)
      for i = 1, expected_pad do
        assert.are.equal("", lines[i])
      end
      assert.are.equal(frame_lines[1], lines[expected_pad + 1])

      vim.api.nvim_win_close(win, true)
      vim.o.lines = original_lines
    end)

    it("never resizes the window -- it plays at whatever size the window already is", function()
      local bufnr, win = open_scratch_win()
      local before = vim.api.nvim_win_get_config(win)

      celebrate.play(bufnr, win, function() end, { total_frames = 1, interval_ms = 10000 })

      local after = vim.api.nvim_win_get_config(win)
      assert.are.equal(before.width, after.width)
      assert.are.equal(before.height, after.height)

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

    it("still calls on_done if rendering a frame errors partway through", function()
      local bufnr, win = open_scratch_win()
      -- force a real rendering failure: wipe the buffer out from under play() so
      -- nvim_buf_set_lines on the next step fails, without touching stopped/bufnr checks.
      local real_set_lines = vim.api.nvim_buf_set_lines
      vim.api.nvim_buf_set_lines = function()
        error("simulated rendering failure")
      end

      local done = false
      celebrate.play(bufnr, win, function()
        done = true
      end, { total_frames = 100, interval_ms = 1 })

      vim.api.nvim_buf_set_lines = real_set_lines
      assert.is_true(done)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)
  end)
end)
