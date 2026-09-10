describe("albus-conflictius.dashboard", function()
  local dashboard

  before_each(function()
    package.loaded["albus-conflictius.dashboard"] = nil
    dashboard = require("albus-conflictius.dashboard")
  end)

  local function file_lines(bufnr)
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  local function close(handle)
    if handle and vim.api.nvim_win_is_valid(handle.win) then
      vim.api.nvim_win_close(handle.win, true)
    end
  end

  it("lists the given files, one per line, without a banner by default", function()
    local handle = dashboard.open({ "a.lua", "b/c.lua" }, {})
    assert.are.same({ "a.lua", "b/c.lua" }, file_lines(handle.bufnr))
    close(handle)
  end)

  it("prepends the banner art when show_banner is true", function()
    local handle = dashboard.open({ "a.lua" }, { show_banner = true })
    local lines = file_lines(handle.bufnr)
    assert.is_true(#lines > 1)
    assert.are.equal("a.lua", lines[#lines])
    close(handle)
  end)

  it("starts the cursor on the first file, not the banner art", function()
    local handle = dashboard.open({ "a.lua", "b.lua" }, { show_banner = true })
    assert.are.equal(handle.offset + 1, vim.api.nvim_win_get_cursor(handle.win)[1])
    close(handle)
  end)

  it("clamps the cursor so it can't move onto the banner art", function()
    local handle = dashboard.open({ "a.lua", "b.lua" }, { show_banner = true })
    vim.api.nvim_win_set_cursor(handle.win, { 1, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = handle.bufnr })
    assert.are.equal(handle.offset + 1, vim.api.nvim_win_get_cursor(handle.win)[1])
    close(handle)
  end)

  it("<CR> calls on_open with the file under cursor", function()
    local opened
    local handle = dashboard.open({ "a.lua", "b.lua" }, {
      on_open = function(path)
        opened = path
      end,
    })
    vim.api.nvim_win_set_cursor(handle.win, { 2, 0 })
    vim.api.nvim_buf_call(handle.bufnr, function()
      vim.cmd("normal \r")
    end)
    assert.are.equal("b.lua", opened)
    close(handle)
  end)

  it("w calls on_wand with the file under cursor", function()
    local wanded
    local handle = dashboard.open({ "a.lua", "b.lua" }, {
      on_wand = function(path)
        wanded = path
      end,
    })
    vim.api.nvim_win_set_cursor(handle.win, { 1, 0 })
    vim.api.nvim_buf_call(handle.bufnr, function()
      vim.cmd("normal w")
    end)
    assert.are.equal("a.lua", wanded)
    close(handle)
  end)

  it("W calls on_wand_all", function()
    local called = false
    local handle = dashboard.open({ "a.lua" }, {
      on_wand_all = function()
        called = true
      end,
    })
    vim.api.nvim_buf_call(handle.bufnr, function()
      vim.cmd("normal W")
    end)
    assert.is_true(called)
    close(handle)
  end)

  describe("refresh", function()
    it("rewrites the file list", function()
      local handle = dashboard.open({ "a.lua" }, {})
      dashboard.refresh(handle, { "x.lua", "y.lua" })
      assert.are.same({ "x.lua", "y.lua" }, file_lines(handle.bufnr))
      close(handle)
    end)

    it("closes the window when the new file list is empty", function()
      local handle = dashboard.open({ "a.lua" }, {})
      dashboard.refresh(handle, {})
      assert.is_false(vim.api.nvim_win_is_valid(handle.win))
    end)
  end)

  describe("close", function()
    it("closes an open window", function()
      local handle = dashboard.open({ "a.lua" }, {})
      dashboard.close(handle)
      assert.is_false(vim.api.nvim_win_is_valid(handle.win))
    end)
  end)

  describe("celebrate", function()
    it("plays the animation in the dashboard's own window and calls on_done", function()
      local handle = dashboard.open({ "a.lua" }, {})
      local done = false

      dashboard.celebrate(handle, function()
        done = true
      end)

      local lines = file_lines(handle.bufnr)
      assert.is_true(table.concat(lines, "\n"):find("CONFLICT", 1, true) ~= nil)

      vim.api.nvim_win_call(handle.win, function()
        vim.cmd("normal q")
      end)
      assert.is_true(done)
    end)

    it("calls on_done immediately if the window is already gone", function()
      local handle = dashboard.open({ "a.lua" }, {})
      close(handle)

      local done = false
      dashboard.celebrate(handle, function()
        done = true
      end)

      assert.is_true(done)
    end)

    it("still calls on_done if the celebration module fails to load or play", function()
      local handle = dashboard.open({ "a.lua" }, {})
      local real_celebrate = package.loaded["albus-conflictius.celebrate"]
      package.loaded["albus-conflictius.celebrate"] = {
        play = function()
          error("simulated celebration failure")
        end,
      }

      local done = false
      dashboard.celebrate(handle, function()
        done = true
      end)

      package.loaded["albus-conflictius.celebrate"] = real_celebrate
      assert.is_true(done)

      if vim.api.nvim_win_is_valid(handle.win) then
        vim.api.nvim_win_close(handle.win, true)
      end
    end)
  end)
end)
