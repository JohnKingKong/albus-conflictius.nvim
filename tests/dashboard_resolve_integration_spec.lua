describe("dashboard -> resolve_view integration", function()
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

  it("opening a file from the dashboard does not corrupt the dashboard window/buffer", function()
    local file = io.open(tmpdir .. "/messy.txt", "w")
    file:write("<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n")
    file:close()

    albus._set_git({
      conflicted_files = function()
        return { "messy.txt" }
      end,
      show = function(_, stage, _)
        return ({ [1] = "base", [2] = "ours", [3] = "theirs" })[stage]
      end,
      stage = function() end,
    })

    albus.open()

    -- simulate pressing <CR> on the dashboard entry (real dashboard.lua, real keymap)
    vim.cmd("normal \r")

    local current_buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(current_buf)
    assert.is_true(name:find("messy.txt", 1, true) ~= nil)
    assert.is_true(vim.bo[current_buf].modifiable)

    vim.cmd("diffoff!")
    vim.cmd("tabclose!")
  end)
end)
