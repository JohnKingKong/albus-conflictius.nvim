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

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})

    assert.is_true(vim.api.nvim_win_is_valid(handle.main_win))
    assert.is_false(handle.diff_open)
    assert.are.equal(2, vim.api.nvim_win_get_cursor(handle.main_win)[1])

    vim.cmd("tabclose!")
  end)

  it("<CR> accepts ours when the cursor is on the ours side of the hunk", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    vim.api.nvim_win_set_cursor(handle.main_win, { 2, 0 }) -- "ours line"
    feed(handle.main_win, "<CR>")

    assert.are.equal("ours line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("<CR> accepts theirs when the cursor is on the theirs side of the hunk", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    vim.api.nvim_win_set_cursor(handle.main_win, { 4, 0 }) -- "theirs line"
    feed(handle.main_win, "<CR>")

    assert.are.equal("theirs line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("<CR> on a marker line warns instead of guessing a side", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    vim.api.nvim_win_set_cursor(handle.main_win, { 3, 0 }) -- "=======" separator line
    feed(handle.main_win, "<CR>")

    assert.is_true(buf_content(handle.main_bufnr):find("<<<<<<<", 1, true) ~= nil)

    vim.cmd("tabclose!")
  end)

  it("<leader>co accepts ours for the hunk under the cursor", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>co")

    assert.are.equal("ours line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("<leader>ct accepts theirs for the hunk under the cursor", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>ct")

    assert.are.equal("theirs line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("<leader>cb accepts both, ours then theirs", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
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

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
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

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>cn")
    assert.are.equal(7, vim.api.nvim_win_get_cursor(handle.main_win)[1])

    feed(handle.main_win, "<leader>cp")
    assert.are.equal(1, vim.api.nvim_win_get_cursor(handle.main_win)[1])

    vim.cmd("tabclose!")
  end)

  it("<leader>cd opens ours (left) | result (middle) | theirs (right)", function()
    write_file(
      "conflict.txt",
      table.concat({ "top", "<<<<<<< HEAD", "a-ours", "=======", "a-theirs", ">>>>>>> branch", "middle" }, "\n")
    )

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>cd")

    assert.is_true(handle.diff_open)
    assert.is_true(vim.api.nvim_win_is_valid(handle.ours_win))
    assert.is_true(vim.api.nvim_win_is_valid(handle.theirs_win))

    local ours_col = vim.api.nvim_win_get_position(handle.ours_win)[2]
    local main_col = vim.api.nvim_win_get_position(handle.main_win)[2]
    local theirs_col = vim.api.nvim_win_get_position(handle.theirs_win)[2]
    assert.is_true(ours_col < main_col)
    assert.is_true(main_col < theirs_col)

    assert.are.equal("top\na-ours\nmiddle", buf_content(handle.ours_bufnr))
    assert.are.equal("top\na-theirs\nmiddle", buf_content(handle.theirs_bufnr))
    assert.is_true(buf_content(handle.main_bufnr):find("<<<<<<<", 1, true) ~= nil)

    feed(handle.main_win, "<leader>cd")
    assert.is_false(handle.diff_open)

    vim.cmd("tabclose!")
  end)

  it("<CR> in the ours pane accepts ours for the hunk at the cursor and refreshes every pane", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>cd")

    vim.api.nvim_win_set_cursor(handle.ours_win, { 1, 0 })
    feed(handle.ours_win, "<CR>")

    assert.are.equal("ours line", buf_content(handle.main_bufnr))
    assert.are.equal("ours line", buf_content(handle.ours_bufnr))
    assert.are.equal("ours line", buf_content(handle.theirs_bufnr))

    vim.cmd("tabclose!")
  end)

  it("<CR> in the theirs pane accepts theirs for the hunk at the cursor", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>cd")

    vim.api.nvim_win_set_cursor(handle.theirs_win, { 1, 0 })
    feed(handle.theirs_win, "<CR>")

    assert.are.equal("theirs line", buf_content(handle.main_bufnr))

    vim.cmd("tabclose!")
  end)

  it("highlights ours and theirs with distinct extmarks", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})

    local ns = vim.api.nvim_create_namespace("albus-conflictius-resolve-view")
    local marks = vim.api.nvim_buf_get_extmarks(handle.main_bufnr, ns, 0, -1, { details = true })
    assert.is_true(#marks > 0)

    local groups = {}
    for _, mark in ipairs(marks) do
      table.insert(groups, mark[4].hl_group)
    end
    table.sort(groups)
    assert.are.same({ "AlbusConflictiusOurs", "AlbusConflictiusTheirs" }, groups)

    vim.cmd("tabclose!")
  end)

  it("<leader>cw runs the wand on the buffer without touching disk", function()
    write_file(
      "conflict.txt",
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

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>cw")

    assert.are.equal("changed", buf_content(handle.main_bufnr))

    local file = io.open(tmpdir .. "/conflict.txt", "r")
    local disk_content = file:read("*a")
    file:close()
    assert.is_true(disk_content:find("<<<<<<<", 1, true) ~= nil)

    vim.cmd("tabclose!")
  end)

  it("q closes the diff panes first, then closes the whole view once nothing remains", function()
    write_file(
      "conflict.txt",
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

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})
    feed(handle.main_win, "<leader>cd")
    assert.is_true(handle.diff_open)

    feed(handle.main_win, "q")
    assert.is_false(handle.diff_open)
    assert.is_true(vim.api.nvim_win_is_valid(handle.main_win))

    feed(handle.main_win, "<leader>cw")
    feed(handle.main_win, "q")
    assert.is_false(vim.api.nvim_win_is_valid(handle.main_win))
  end)

  it("q prompts for confirmation before closing when conflicts remain, and respects the answer", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n")

    local handle = resolve_view.open(tmpdir, "conflict.txt", {})

    local original_confirm = vim.fn.confirm
    local confirm_calls = 0

    vim.fn.confirm = function()
      confirm_calls = confirm_calls + 1
      return 2 -- "No"
    end
    feed(handle.main_win, "q")
    assert.are.equal(1, confirm_calls)
    assert.is_true(vim.api.nvim_win_is_valid(handle.main_win))

    vim.fn.confirm = function()
      confirm_calls = confirm_calls + 1
      return 1 -- "Yes"
    end
    feed(handle.main_win, "q")
    assert.is_false(vim.api.nvim_win_is_valid(handle.main_win))

    vim.fn.confirm = original_confirm
  end)

  it("calls on_resolved when the main buffer is saved with no remaining markers", function()
    write_file("conflict.txt", "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n")

    local resolved_path
    local handle = resolve_view.open(tmpdir, "conflict.txt", {
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
