# **albus-conflictius.nvim**

A merge-conflict manager for Neovim, with a "magic wand" that auto-resolves the easy conflicts — the Neovim equivalent of WebStorm's one-keystroke conflict resolution.

## Why this exists

Resolving a git conflict usually means opening each file, scanning past the conflict markers where only one side actually changed anything, and manually picking that side over and over. WebStorm's merge tool has a "magic wand" that does this automatically, leaving only the conflicts that truly need a human. Neovim had no equivalent, and no way to notice a conflict exists unless you're already looking at the file.

**`albus-conflictius.nvim` covers both.** It watches the repo itself for conflicts — from a merge, rebase, or cherry-pick, started from any tool (lazygit, a plain `git` command in another terminal, another plugin) — and pops up a dashboard the moment one appears. From there, the wand clears the easy hunks; anything left gets a guided accept-ours/accept-theirs view, not a wall of diff panes to decode.

---

## How it works

1. Conflict detection is repo-state based: it checks for `.git/MERGE_HEAD`, `.git/rebase-merge`, `.git/rebase-apply`, or `.git/CHERRY_PICK_HEAD`, then confirms the conflicted files via `git diff --diff-filter=U`. This runs on `FocusGained`/`DirChanged`/`VimResume`, plus a filesystem watcher on `.git`, so it fires even if the conflict was created in a different terminal or tool entirely.
2. The first time a new conflict set is detected, a floating dashboard pops up listing every conflicted file (with a small wizard art banner). Reopen it anytime with `:AlbusConflictius`.
3. From the dashboard: `<CR>` opens a file, `w` runs the magic wand on the file under the cursor, `W` runs it across every conflicted file at once.
4. The wand resolves each hunk where only one side actually changed relative to the merge base (or both sides converged on the same result) — it reads this straight from the conflict markers themselves, so it needs `merge.conflictstyle = diff3`, which the plugin sets on the repo automatically the first time `setup()` runs.
5. Hunks where both sides genuinely changed different things are left alone. Opening that file from the dashboard (`<CR>`) drops the cursor on the first remaining conflict, with the "ours"/"theirs" side of each hunk background-highlighted so they're visually distinct, and keymaps to act on the hunk under the cursor: `<leader>co` accept ours, `<leader>ct` accept theirs, `<leader>cb` accept both, `<leader>cn`/`<leader>cp` jump to the next/previous conflict, `<leader>cw` run the wand right there on the buffer (no need to go back to the dashboard). No diff panes to decode by default — you're just looking at your real file. For the harder cases, `<leader>cd` opens a 3-pane view — **ours** (left) | **result** (middle, your real file) | **theirs** (right) — where `<CR>` in either side pane accepts that side for the hunk under the cursor there, so which side you're looking at is which side you pick. `q` closes the panes (non-destructive, `<leader>cd` reopens them), or the whole view if they're already closed — with a confirmation prompt only if conflicts still remain.
6. The moment a file has zero remaining conflict markers — whether the wand cleared it or you finished it by hand — it's automatically `git add`ed on save.

**This is not a git client.** Continuing the rebase/merge and committing is left to lazygit or the CLI, same as before.

---

## Installation

> **Requirements:** Neovim >= 0.10, and `git` on your `$PATH`.

### lazy.nvim

```lua
{
  "johnkingkong/albus-conflictius.nvim",
  lazy = false,
  config = function()
    require("albus-conflictius").setup({
      -- see Configuration below
    })
  end,
}
```

### vim-plug

```vim
Plug 'johnkingkong/albus-conflictius.nvim'
```

```lua
require('albus-conflictius').setup()
```

---

## Configuration

```lua
require("albus-conflictius").setup({
  banner = true,       -- show the wizard art when the dashboard auto-pops for a new conflict
  auto_stage = true,   -- `git add` a file automatically once it has no conflict markers left
})
```

`setup()` is entirely optional — skip it and the plugin runs with the defaults above.

Commands: `:AlbusConflictius` (open the dashboard now), `:AlbusConflictiusHelp` (wizard art + command/keymap reference).

---

## Architecture

**`lua/albus-conflictius/init.lua`** — public API: `setup()`, `open()`, `wand_file()`, `wand_all()`, `help()`

**`lua/albus-conflictius/config.lua`** — defaults, option validation, `setup()`/`get()`

**`lua/albus-conflictius/git.lua`** — git plumbing: in-progress-operation detection, conflicted file listing, diff3 style enforcement, staging, `git show` for stage 1/2/3 blobs

**`lua/albus-conflictius/wand.lua`** — pure per-hunk resolution algorithm (no git/UI dependency)

**`lua/albus-conflictius/dashboard.lua`** — the floating conflicted-files window

**`lua/albus-conflictius/resolve_view.lua`** — accept-ours/accept-theirs hunk view for files with remaining conflicts, with an optional ours | result | theirs 3-pane diff toggle

**`lua/albus-conflictius/watcher.lua`** — autocmds + filesystem watcher with a dedup guard, driving auto-popup

**`lua/albus-conflictius/banner.lua`** — the wizard art and help window

**`plugin/albus-conflictius.lua`** — registers `:AlbusConflictius`, `:AlbusConflictiusHelp`

---

## Non-goals

- Not a git client — no staging UI beyond auto-`git add`, no commit/continue/abort/push commands.
- Not a replacement for lazygit or the git CLI.
- Not a semantic/AST-aware merge tool — resolution is line/hunk-based, same granularity as git's own 3-way merge.
- Does not attempt to resolve genuinely two-sided conflicts automatically.

---

## Development

```bash
make deps   # clone plenary.nvim test dep into .deps/
make test   # run the plenary busted test suite
make lint   # stylua --check and luacheck
```

---

## License

MIT
