describe("albus-conflictius.resolve_view", function()
  local resolve_view
  local tmpdir

  before_each(function()
    package.loaded["albus-conflictius.resolve_view"] = nil
    resolve_view = require("albus-conflictius.resolve_view")
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    vim.fn.delete(tmpdir, "rf")
  end)

  local function fake_git(blobs)
    return {
      show = function(_, stage, _)
        return blobs[stage]
      end,
    }
  end

  it("opens the file plus base/ours/theirs scratch buffers, all diffed", function()
    local path = "conflict.txt"
    local full_path = tmpdir .. "/" .. path
    local file = io.open(full_path, "w")
    file:write("<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n")
    file:close()

    local handle = resolve_view.open(tmpdir, path, {
      git = fake_git({ [1] = "base content", [2] = "ours content", [3] = "theirs content" }),
    })

    assert.is_true(vim.api.nvim_win_is_valid(handle.main_win))
    assert.are.equal(3, #handle.scratch_bufnrs)

    local contents = {}
    for _, bufnr in ipairs(handle.scratch_bufnrs) do
      table.insert(contents, table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
    end
    table.sort(contents)
    assert.are.same({ "base content", "ours content", "theirs content" }, contents)

    for _, bufnr in ipairs(handle.scratch_bufnrs) do
      assert.is_false(vim.bo[bufnr].modifiable)
    end

    vim.cmd("tabclose!")
  end)

  it("calls on_resolved when the main buffer is saved with no remaining markers", function()
    local path = "conflict.txt"
    local full_path = tmpdir .. "/" .. path
    local file = io.open(full_path, "w")
    file:write("<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n")
    file:close()

    local resolved_path
    local handle = resolve_view.open(tmpdir, path, {
      git = fake_git({ [1] = "base", [2] = "ours", [3] = "theirs" }),
      on_resolved = function(p)
        resolved_path = p
      end,
    })

    vim.api.nvim_buf_set_lines(handle.main_bufnr, 0, -1, false, { "resolved content" })
    vim.api.nvim_buf_call(handle.main_bufnr, function()
      vim.cmd("silent write")
    end)

    assert.are.equal(path, resolved_path)

    vim.cmd("tabclose!")
  end)
end)
