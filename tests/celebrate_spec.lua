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
      -- the wizard art is pasted in as-is (not centered/padded -- its shape depends on each
      -- line's own hand-authored leading whitespace), so the raw joined art should appear
      -- verbatim, unchanged, in every frame.
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
      -- the message is the second-to-last row: laser, message, star-line.
      assert.is_true(lines1[#lines1 - 1]:find("CUSTOM MESSAGE", 1, true) ~= nil)
      assert.is_true(lines2[#lines2 - 1]:find("CUSTOM MESSAGE", 1, true) ~= nil)
    end)

    it("returns highlight marks covering the sparkle rows and the laser", function()
      local _, highlights = celebrate.frame(1, "MSG")
      local groups = {}
      for _, h in ipairs(highlights) do
        groups[h.hl_group] = true
      end

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
      local message_row = #lines - 2 -- 0-based row index of the message (laser, message, star-line)

      local colors_on_message_line = {}
      for _, h in ipairs(highlights) do
        if h.row == message_row then
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
      local laser_row_index = #lines - 2 -- laser, message, star-line
      local laser_center = center_col(lines[laser_row_index])
      local message_center = center_col(lines[#lines - 1])
      assert.is_true(math.abs(top_center - laser_center) <= 1)
      assert.is_true(math.abs(top_center - message_center) <= 1)
    end)

    it("sizes the laser, message, and star-line rows to the given width, not a fixed constant", function()
      local width = 50
      local lines = celebrate.frame(1, "MSG", width)
      local laser_row = lines[#lines - 2]
      local message_row = lines[#lines - 1]
      local star_row = lines[#lines]

      assert.are.equal(width, #laser_row)
      assert.are.equal(width, #star_row)
      assert.is_true(#message_row <= width)

      -- a different width produces differently-sized rows -- confirms the width is actually
      -- threaded through rather than silently falling back to a fixed internal constant.
      local other_width = 20
      local other_lines = celebrate.frame(1, "MSG", other_width)
      assert.are.equal(other_width, #other_lines[#other_lines - 2])
      assert.are.equal(other_width, #other_lines[#other_lines])
    end)

    it("sweeps the laser spark across the full inner width, not just the first few columns", function()
      -- the spark's ping-pong used to be scaled to `width` directly (a step per physical column),
      -- but `frame()` only ever sees `frame_count()` distinct indices before wrapping back to
      -- frame 1 -- so on any window wider than ~frame_count() columns, the spark got stuck
      -- sweeping the first handful of columns and never reached the rest of the row.
      local width = 50
      local min_col, max_col = width, 0
      for idx = 1, celebrate.frame_count() do
        local lines = celebrate.frame(idx, "MSG", width)
        local laser_row = lines[#lines - 2]
        local col = laser_row:find("%*")
        min_col = math.min(min_col, col)
        max_col = math.max(max_col, col)
      end
      assert.is_true(min_col <= 3)
      assert.is_true(max_col >= width - 2)
    end)

    it("never clips the message -- it's centered within width regardless of message length", function()
      local width = 40
      local short = celebrate.frame(1, "HI", width)
      local long = celebrate.frame(1, "A FAIRLY LONG CELEBRATION MESSAGE HERE", width)
      assert.is_true(short[#short - 1]:find("HI", 1, true) ~= nil)
      assert.is_true(long[#long - 1]:find("A FAIRLY LONG CELEBRATION MESSAGE HERE", 1, true) ~= nil)
    end)

    it("keeps both sparkle rows solid and exactly as wide as the laser/star-line rows", function()
      local width = 24
      local lines = celebrate.frame(1, "MSG", width)
      local top_content = lines[1]
      local bottom_content = lines[2]
      assert.is_nil(top_content:find("%s"))
      assert.is_nil(bottom_content:find("%s"))
      assert.are.equal(width, #top_content)
      assert.are.equal(width, #bottom_content)
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
    local function open_scratch_win(width, height)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        width = width or 10,
        height = height or 5,
        row = 0,
        col = 0,
        style = "minimal",
      })
      return bufnr, win
    end

    it("renders the first frame (with the chosen message), sized to the window's own width", function()
      local width = 10
      local bufnr, win = open_scratch_win(width)
      celebrate.play(bufnr, win, function() end, { total_frames = 1, interval_ms = 10000, message = "PINNED" })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.same(celebrate.frame(1, "PINNED", width), lines)

      vim.api.nvim_win_close(win, true)
    end)

    it("vertically centers the frame with blank padding when the window is taller than the content", function()
      local width = 60
      local frame_lines = celebrate.frame(1, "PINNED", width)
      local extra = 10
      -- headless Neovim defaults to a 24-line "screen", too short to actually fit
      -- #frame_lines + extra -- give it enough room so the window isn't silently clamped.
      local original_lines = vim.o.lines
      vim.o.lines = #frame_lines + extra + 10

      local bufnr, win = open_scratch_win(width, #frame_lines + extra)

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
