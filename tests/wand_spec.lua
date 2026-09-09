describe("albus-conflictius.wand", function()
  local wand

  before_each(function()
    package.loaded["albus-conflictius.wand"] = nil
    wand = require("albus-conflictius.wand")
  end)

  describe("parse_hunks", function()
    it("finds a single diff3-style hunk", function()
      local lines = {
        "line before",
        "<<<<<<< HEAD",
        "ours line",
        "||||||| base",
        "base line",
        "=======",
        "theirs line",
        ">>>>>>> branch",
        "line after",
      }
      local hunks = wand.parse_hunks(lines)
      assert.are.equal(1, #hunks)
      local hunk = hunks[1]
      assert.are.equal(2, hunk.start_idx)
      assert.are.equal(8, hunk.end_idx)
      assert.are.same({ "ours line" }, hunk.ours)
      assert.are.same({ "base line" }, hunk.base)
      assert.are.same({ "theirs line" }, hunk.theirs)
      assert.is_true(hunk.has_base)
    end)

    it("finds a hunk with no base separator (plain diff2 style)", function()
      local lines = {
        "<<<<<<< HEAD",
        "ours line",
        "=======",
        "theirs line",
        ">>>>>>> branch",
      }
      local hunks = wand.parse_hunks(lines)
      assert.are.equal(1, #hunks)
      assert.is_false(hunks[1].has_base)
      assert.is_nil(hunks[1].base)
    end)

    it("finds multiple hunks in one file", function()
      local lines = {
        "<<<<<<< HEAD",
        "a-ours",
        "||||||| base",
        "a-base",
        "=======",
        "a-theirs",
        ">>>>>>> branch",
        "unchanged middle",
        "<<<<<<< HEAD",
        "b-ours",
        "||||||| base",
        "b-base",
        "=======",
        "b-theirs",
        ">>>>>>> branch",
      }
      local hunks = wand.parse_hunks(lines)
      assert.are.equal(2, #hunks)
    end)

    it("returns no hunks for a file with no conflict markers", function()
      local hunks = wand.parse_hunks({ "just", "plain", "lines" })
      assert.are.equal(0, #hunks)
    end)
  end)

  describe("resolve_hunk", function()
    it("auto-resolves to theirs when only theirs changed", function()
      local resolved, content = wand.resolve_hunk({
        ours = { "same" },
        base = { "same" },
        theirs = { "changed" },
        has_base = true,
      })
      assert.is_true(resolved)
      assert.are.same({ "changed" }, content)
    end)

    it("auto-resolves to ours when only ours changed", function()
      local resolved, content = wand.resolve_hunk({
        ours = { "changed" },
        base = { "same" },
        theirs = { "same" },
        has_base = true,
      })
      assert.is_true(resolved)
      assert.are.same({ "changed" }, content)
    end)

    it("auto-resolves when both sides converge on identical text", function()
      local resolved, content = wand.resolve_hunk({
        ours = { "same result" },
        base = { "original" },
        theirs = { "same result" },
        has_base = true,
      })
      assert.is_true(resolved)
      assert.are.same({ "same result" }, content)
    end)

    it("leaves a true two-sided conflict unresolved", function()
      local resolved = wand.resolve_hunk({
        ours = { "ours change" },
        base = { "original" },
        theirs = { "theirs change" },
        has_base = true,
      })
      assert.is_false(resolved)
    end)

    it("leaves a hunk unresolved when there is no base to compare against", function()
      local resolved = wand.resolve_hunk({
        ours = { "ours change" },
        base = nil,
        theirs = { "theirs change" },
        has_base = false,
      })
      assert.is_false(resolved)
    end)
  end)

  describe("resolve_lines", function()
    it("splices resolved hunks and leaves real conflicts with markers intact", function()
      local lines = {
        "top",
        "<<<<<<< HEAD",
        "same",
        "||||||| base",
        "same",
        "=======",
        "changed by theirs",
        ">>>>>>> branch",
        "middle",
        "<<<<<<< HEAD",
        "ours change",
        "||||||| base",
        "original",
        "=======",
        "theirs change",
        ">>>>>>> branch",
        "bottom",
      }
      local new_lines, resolved_count, remaining_count = wand.resolve_lines(lines)
      assert.are.equal(1, resolved_count)
      assert.are.equal(1, remaining_count)
      assert.are.same({
        "top",
        "changed by theirs",
        "middle",
        "<<<<<<< HEAD",
        "ours change",
        "||||||| base",
        "original",
        "=======",
        "theirs change",
        ">>>>>>> branch",
        "bottom",
      }, new_lines)
    end)

    it("passes through a file with no conflicts unchanged", function()
      local lines = { "a", "b", "c" }
      local new_lines, resolved_count, remaining_count = wand.resolve_lines(lines)
      assert.are.same(lines, new_lines)
      assert.are.equal(0, resolved_count)
      assert.are.equal(0, remaining_count)
    end)
  end)

  describe("resolve_content / has_conflict_markers", function()
    it("resolve_content resolves a fully-resolvable file to a clean string", function()
      local content = table.concat({
        "<<<<<<< HEAD",
        "same",
        "||||||| base",
        "same",
        "=======",
        "changed",
        ">>>>>>> branch",
      }, "\n")
      local new_content, resolved_count, remaining_count = wand.resolve_content(content)
      assert.are.equal("changed", new_content)
      assert.are.equal(1, resolved_count)
      assert.are.equal(0, remaining_count)
      assert.is_false(wand.has_conflict_markers(new_content))
    end)

    it("has_conflict_markers detects remaining markers", function()
      local content = table.concat({ "<<<<<<< HEAD", "x", "=======", "y", ">>>>>>> b" }, "\n")
      assert.is_true(wand.has_conflict_markers(content))
    end)

    it("has_conflict_markers is false for plain content", function()
      assert.is_false(wand.has_conflict_markers("just some text\nmore text"))
    end)
  end)
end)
