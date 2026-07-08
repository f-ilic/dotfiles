# specs-browse v2 — searchable filetree — design

Date: 2026-07-08
Status: approved-pending-review
File touched: `bin/specs-browse` (bash, self-reinvoking)

## Problem

`specs-browse` is a `fzf`-based browser for files on a Spectacles device over
`adb`. Today it lists **one directory at a time** (`ls -1AF "$dir"`) and `fzf`'s
fuzzy filter only searches the entries of that single folder. Navigation is one
level up/down at a time. The user wants a **real filetree they can search across
the whole device**, not just the current directory.

## Goals

- A visual, indented, collapsible filetree (broot-style).
- Fuzzy search across the *entire* crawled tree; when a query matches a deep
  entry, that entry stays visible **together with its parent folders**.
- Search/filtering must feel instant despite `adb` round-trip latency.
- Preserve what already works: device/serial resolution, the right-hand preview
  pane, pull-to-`$PWD`, and opening files via `~/bin/preview`.
- Degrade gracefully when the device disconnects mid-session (observed to happen).

## Non-goals

- No device-side install, no FUSE (that is `specs-mount-fs`'s job).
- No editing/writing to the device (browse + preview + pull only, as today).
- No live filesystem watching. Freshness comes from an explicit re-crawl.

## Decisions (from brainstorming)

1. **Browsing model:** broot-style **collapsible searchable tree** — matches stay
   visible with their ancestor folders. (vs. flat fuzzy finder / hybrid.)
2. **Data loading:** **crawl once at startup**, cache in memory for the session,
   filter locally. Re-crawl on demand via a key. (vs. persistent cache / lazy.)
3. **Match semantics:** **fuzzy, fzf-style** (characters-in-order, space = AND),
   implemented by piping the cached paths through `fzf --filter="$query"` — the
   same engine, non-interactive — so behavior is identical to interactive fzf.
4. **Default scope:** crawl from `/` with `/proc /sys /dev /acct /apex /config`
   pruned by default (keeps startup fast, tree clean). Overridable.

## Architecture

Single bash script, same self-reinvoking pattern as today (the script calls
itself for `fzf`-side hooks). The `ls`-per-directory `while` loop is replaced by
a **crawl-once + local-render** engine. Everything the tree needs after the
initial crawl is computed locally from a cached path list — no `adb` per
keystroke.

Reused unchanged:
- Serial resolution (`-s` > `$CV_SOC` > auto `_cv` > `$ANDROID_SERIAL` > first).
- `adb` reachability check.
- `view_file` (pull to temp → `~/bin/preview`).
- The right-hand preview pane (metadata + text peek), keyed on a path.

New self-reinvoked subcommands (mirroring today's `--__preview`):
- `--__crawl`   — run the `find`, write the cache, print a progress spinner.
- `--__render`  — pure render: (cache, expanded-set, query) → tree lines on stdout.
- `--__act`     — activate highlighted row: dir → toggle expand; file → preview.
- `--__pull`    — pull highlighted path → `$PWD`.
- `--__expand-all` — write every directory path in the cache into `$EXPANDED`.
- `--__preview` — unchanged in spirit; now takes an absolute path.

### Session state (temp dir, one per run, `trap`-cleaned on exit)

- `$PATHS`    — cached crawl: one absolute path per line, in **tree order**.
- `$EXPANDED` — set of currently-expanded directory paths, one per line.

Helpers receive the paths to these files (and the serial) via exported env vars,
exactly like `SPECS_BROWSE_SERIAL`/`SPECS_BROWSE_DIR` today.

## Data flow

1. **Startup crawl** (`--__crawl`, behind a spinner):
   ```
   adb -s "$S" shell "find $ROOT <prune-expr> -print" 2>/dev/null
   ```
   `<prune-expr>` is `\( -path P1 -o -path P2 ... \) -prune -o ... -print`.
   Output is normalized (trailing-slash stripped, blanks dropped), **sorted into
   tree order** (see below), and written to `$PATHS`.

2. **Directory inference (local, zero adb):** a path `P` is a *directory* iff some
   other cached path begins with `P + "/"`. Computed in the render pass.
   - Trade-off: a genuinely **empty** directory has no descendants in the cache,
     so it renders as a leaf (not expandable). Acceptable — there is nothing to
     expand into.

3. **Render** (`--__render "$query"`, runs on every keystroke, 100% local):
   - **Empty query:** show the root's children, and deeper entries only where all
     ancestors are in `$EXPANDED` (collapsed tree).
   - **Non-empty query:**
     ```
     matches=$(printf '%s\n' "$paths" | fzf --filter="$query")   # fzf-style fuzzy
     ```
     Visible set = `matches` ∪ (all ancestor directories of each match). Ancestors
     are force-shown/expanded so the tree structure around matches is intact.
   - The `ROOT` itself is the first rendered row (`▾ /` when it has visible
     children). Its direct children render at depth 1.
   - For each visible path, emit one line:
     `<abspath> \t <indent><glyph> <basename>`
     - `indent` = 2 spaces × depth.
     - `glyph`  = `▾` expanded dir · `▸` collapsed dir · (space) file.
   - `fzf` displays only column 2 (`--delimiter='\t' --with-nth=2`); actions read
     the hidden absolute path as `{1}`.

4. **fzf invocation:**
   ```
   fzf --ansi --disabled --layout=reverse --height=100% \
       --delimiter='\t' --with-nth=2 \
       --bind 'start:reload(SELF --__render {q})' \
       --bind 'change:reload(SELF --__render {q})' \
       --bind 'enter:execute(SELF --__act {1})+reload(SELF --__render {q})' \
       --bind 'tab:execute(SELF --__act {1})+reload(SELF --__render {q})' \
       --bind 'ctrl-y:execute(SELF --__pull {1})+reload(SELF --__render {q})' \
       --bind 'ctrl-r:execute(SELF --__crawl)+reload(SELF --__render {q})' \
       --bind 'ctrl-e:execute-silent(SELF --__expand-all)+reload(SELF --__render {q})' \
       --bind 'ctrl-w:execute-silent(: > "$EXPANDED")+reload(SELF --__render {q})' \
       --preview 'SELF --__preview {1}' \
       --preview-window=right,58%,wrap
   ```
   `--disabled` turns off fzf's own matcher so *we* own visibility (and keep
   ancestors). `SELF` = resolved path to this script.

### Tree-order sort

Lexicographic sort of absolute paths is **not** correct pre-order (a sibling like
`a-b` sorts before children of `a/` because `-`(0x2D) < `/`(0x2F)). Fix: sort with
the separator forced lowest, e.g. translate `/`→`\x01` before `sort`, translate
back after. This yields parent-before-children with alphabetical siblings.

## Keybindings

| Key            | Action                                                        |
|----------------|---------------------------------------------------------------|
| *type*         | fuzzy filter; matches keep their parent folders               |
| `Enter`/`Tab`  | dir → expand/collapse · file → preview & open (`~/bin/preview`)|
| `Ctrl-Y`       | pull highlighted entry → `$PWD` (preserved)                   |
| `Ctrl-R`       | re-crawl the device                                           |
| `Ctrl-E`/`Ctrl-W` | expand-all / collapse-all                                  |
| `Esc`/`Ctrl-C` | quit                                                          |

## CLI & configuration (unchanged surface)

```
specs-browse [-s SERIAL] [ROOT]
specs-browse -h | --help
```
- `ROOT` default `/`. Passing a narrower root (e.g. `specs-browse /sys`) scopes
  the crawl and stays fast.
- `SPECS_BROWSE_PRUNE` env overrides the default prune list
  (`/proc /sys /dev /acct /apex /config`).

## Error handling

- **Crawl fails / device unreachable:** print a clear message; if a prior cache
  exists in this session, keep browsing it; otherwise exit with the same tone as
  today's "device not reachable".
- **Empty crawl result:** show "nothing found under `$ROOT`" instead of a blank
  tree.
- **Preview/pull failure mid-session** (device dropped): message + keep the UI
  alive; `Ctrl-R` retries the crawl. No crash on transient `adb` loss.

## Testing

`--__render` is a **pure function** of (`$PATHS` file, `$EXPANDED` file, query) →
stdout, so it is testable with a synthetic path list and **no device**:

- collapsed root view (empty query, empty expanded set)
- expand toggle reveals exactly one level
- filter keeps ancestors of matches, hides non-matching siblings
- tree ordering (siblings alphabetical, `a-b` after `a/` children handled)
- indent depth and glyph selection (dir vs file, expanded vs collapsed)
- empty-dir renders as a non-expandable leaf

A lightweight smoke check covers the adb-touching paths (crawl parse, pull) but
is skipped when no device is attached.

## Risks / open items

- **Startup crawl time** scales with tree size. Mitigated by the prune list and
  by allowing a scoped `ROOT`. If a `/`-crawl is ever too slow in practice, a
  depth cap (`-maxdepth`) is a cheap follow-up.
- **`fzf --filter` per keystroke** spawns a process each render. `fzf --filter`
  over tens of thousands of lines is sub-100ms, so this is expected to be fine;
  if not, fall back to an awk subsequence matcher.
- **Very large trees** (hundreds of thousands of lines) would make the awk render
  noticeable. Not expected on this device class; revisit only if observed.
