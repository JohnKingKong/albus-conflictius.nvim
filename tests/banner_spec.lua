describe("albus-conflictius.banner", function()
  local banner

  before_each(function()
    package.loaded["albus-conflictius.banner"] = nil
    banner = require("albus-conflictius.banner")
  end)

  describe("art", function()
    it("returns a non-empty array of strings", function()
      local art = banner.art()
      assert.is_true(#art > 0)
      for _, line in ipairs(art) do
        assert.are.equal("string", type(line))
      end
    end)
  end)

  describe("help_lines", function()
    it("includes the art and the command reference", function()
      local lines = banner.help_lines()
      local joined = table.concat(lines, "\n")
      assert.is_true(joined:find("AlbusConflictius", 1, true) ~= nil)
      assert.is_true(joined:find("wand", 1, true) ~= nil)
    end)
  end)

  describe("show_help", function()
    it("opens a floating window without erroring", function()
      local win = banner.show_help()
      assert.is_true(vim.api.nvim_win_is_valid(win))
      vim.api.nvim_win_close(win, true)
    end)
  end)
end)
