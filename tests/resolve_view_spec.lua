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

  local function write_file(path, content)
    local file = io.open(tmpdir .. "/" .. path, "w")
    file:write(content)
    file:close()
  end

  local function feed(win, keys)
    vim.api.nvim_set_current_win(win)
    local raw = vim.api.nvim_replace_termcodes(keys, true, false, true)
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal " .. raw)
    end)
  end

  local function buf_content(bufnr)
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end

  it("opens the file alone (no diff panes) and places the cursor on the first conflict", function()
    write_file("conflict.txt", "top\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\nbottom\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", { git = fake_git({}) })

    assert.is_true(vim.api.nvim_win_is_valid(handle.main_win))
    assert.are.equal(0, #handle.scratch_bufnrs)
    assert.are.equal(2, vim.api.nvim_win_get_cursor(handle.main_win)[1])

    vim.cmd("tabclose!")
  end)

  it("<leader>co accepts ours for the hunk under the cursor", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", { git = fake_git({}) })
    feed(handle.main_win, "<leader>co")

    assert.are.equal("ours line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("<leader>ct accepts theirs for the hunk under the cursor", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", { git = fake_git({}) })
    feed(handle.main_win, "<leader>ct")

    assert.are.equal("theirs line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("<leader>cb accepts both, ours then theirs", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", { git = fake_git({}) })
    feed(handle.main_win, "<leader>cb")

    assert.are.equal("ours line\ntheirs line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("jumps to the next remaining hunk after resolving one", function()
    write_file(
      "conflict.txt",
      table.concat({
        "<<<<<<< HEAD",
        "a-ours",
        "=======",
        "a-theirs",
        ">>>>>>> branch",
        "middle",
        "<<<<<<< HEAD",
        "b-ours",
        "=======",
        "b-theirs",
        ">>>>>>> branch",
        "",
      }, "\n")
    )

    local handle = resolve_view.open(tmpdir, "conflict.txt", { git = fake_git({}) })
    feed(handle.main_win, "<leader>co")

    -- first hunk collapsed to 1 line ("a-ours"), so the second hunk's <<<<<<< now starts at line 3
    assert.are.equal(3, vim.api.nvim_win_get_cursor(handle.main_win)[1])

    vim.cmd("tabclose!")
  end)

  it("<leader>cn / <leader>cp navigate between multiple hunks without resolving them", function()
    write_file(
      "conflict.txt",
      table.concat({
        "<<<<<<< HEAD",
        "a-ours",
        "=======",
        "a-theirs",
        ">>>>>>> branch",
        "middle",
        "<<<<<<< HEAD",
        "b-ours",
        "=======",
        "b-theirs",
        ">>>>>>> branch",
        "",
      }, "\n")
    )

    local handle = resolve_view.open(tmpdir, "conflict.txt", { git = fake_git({}) })
    feed(handle.main_win, "<leader>cn")
    assert.are.equal(7, vim.api.nvim_win_get_cursor(handle.main_win)[1])

    feed(handle.main_win, "<leader>cp")
    assert.are.equal(1, vim.api.nvim_win_get_cursor(handle.main_win)[1])

    vim.cmd("tabclose!")
  end)

  it("<leader>cd opens the base/ours/theirs diff panes, and toggles them closed again", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {
      git = fake_git({ [1] = "base content", [2] = "ours content", [3] = "theirs content" }),
    })

    feed(handle.main_win, "<leader>cd")
    assert.are.equal(3, #handle.scratch_bufnrs)

    local contents = {}
    for _, bufnr in ipairs(handle.scratch_bufnrs) do
      table.insert(contents, buf_content(bufnr))
      assert.is_false(vim.bo[bufnr].modifiable)
    end
    table.sort(contents)
    assert.are.same({ "base content", "ours content", "theirs content" }, contents)

    feed(handle.main_win, "<leader>cd")
    assert.are.equal(0, #handle.scratch_bufnrs)

    vim.cmd("tabclose!")
  end)

  it("calls on_resolved when the main buffer is saved with no remaining markers", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n")

    local resolved_path
    local handle = resolve_view.open(tmpdir, "conflict.txt", {
      git = fake_git({ [1] = "base", [2] = "ours", [3] = "theirs" }),
      on_resolved = function(p)
        resolved_path = p
      end,
    })

    vim.api.nvim_buf_set_lines(handle.main_bufnr, 0, -1, false, { "resolved content" })
    vim.api.nvim_buf_call(handle.main_bufnr, function()
      vim.cmd("silent write")
    end)

    assert.are.equal("conflict.txt", resolved_path)

    vim.cmd("tabclose!")
  end)
end)
