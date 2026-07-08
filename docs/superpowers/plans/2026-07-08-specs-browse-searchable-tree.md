# specs-browse Searchable Filetree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `bin/specs-browse` from a one-directory-at-a-time `adb` file browser into a broot-style collapsible filetree with whole-device fuzzy search.

**Architecture:** One self-reinvoking bash script. A single startup `find` crawl is cached to a session temp file; all filtering/rendering happens locally (no `adb` per keystroke). `fzf` runs with its own matcher **disabled** and re-renders the tree via `change:reload($self --__render {q})`, so matches stay on screen together with their ancestor folders. New behavior is added as pure, testable self-subcommands (`--__treesort`, `--__render`, `--__expand-all`, `--__act`, `--__crawl`, `--__pull`, `--__preview`, `--__prune-expr`) before the main loop is finally swapped over — the tool stays runnable at every commit.

**Tech Stack:** bash 3.2, BSD awk, `fzf` 0.65, `adb`, `~/bin/preview`.

## Global Constraints

- Target `/bin/bash` 3.2.57: **no** `${var,,}`, **no** associative arrays (`declare -A`), **no** `mapfile`/`readarray`. Use `tr` and awk arrays instead.
- BSD awk only: **no** `gensub`, **no** `ARGIND`. `FILENAME`, `gsub`, `substr`, `index`, user functions are fine.
- Device-side `find` is toybox: use only POSIX predicates — `-path`, `-prune`, `-print`, `-o`, grouping `\( \)`.
- Preserve the public CLI: `specs-browse [-s SERIAL] [ROOT]` and `-h|--help`.
- Reuse `~/bin/preview`; do not reimplement previewing.
- Every commit must leave the tool runnable (subcommands are additive until the final swap).
- Display glyphs are UTF-8 `▾` (expanded dir) / `▸` (collapsed dir) / space (file). The crawl spinner stays **ASCII** (bash 3.2 substrings are byte-wise).
- Tests: plain-bash runner under `tests/specs-browse/`, no external deps. Run all with `bash tests/specs-browse/run.sh`.
- State is passed to subcommands via exported env vars:
  `SPECS_BROWSE_SERIAL`, `SPECS_BROWSE_ROOT`, `SPECS_BROWSE_PATHS` (cache file),
  `SPECS_BROWSE_EXPANDED` (expanded-set file), `SPECS_BROWSE_PRUNE` (optional).
- `self` = resolved path to this script (already computed in v1 as `self="$(command -v "$0" ... )"`); reused for all reinvocations.

---

## Interfaces (locked names/signatures used across tasks)

- `do_treesort` — stdin: raw paths → stdout: normalized, unique, tree-ordered paths.
- `do_render "$query"` — reads `$SPECS_BROWSE_PATHS`, `$SPECS_BROWSE_EXPANDED`, `$SPECS_BROWSE_ROOT`; empty query → collapsed tree, non-empty → fuzzy-filtered tree keeping ancestors. Emits `abspath \t display` per line.
- `do_expand_all` — appends every directory path in the cache to `$SPECS_BROWSE_EXPANDED` (then dedups).
- `is_dir_in_cache "$path"` — exit 0 if some cache line starts with `$path/`.
- `toggle_expanded "$path"` — adds/removes an exact line in `$SPECS_BROWSE_EXPANDED`.
- `do_act "$abspath"` — dir → `toggle_expanded`; file → `view_file`. (bound to Enter)
- `do_toggle "$abspath"` — dir-only toggle; no-op on files. (bound to Tab, `execute-silent`)
- `build_prune_expr "$space_list"` — echoes `-path A -o -path B ...`.
- `do_crawl` — runs the device `find`, pipes through `do_treesort`, writes `$SPECS_BROWSE_PATHS`; exit 1 if empty.
- `do_pull "$abspath"` — `adb pull` into `$PWD`.
- `do_preview "$abspath"` — right-pane preview (dir listing, or file metadata + text peek).
- `view_file "$abspath"` — pull to temp, open with `~/bin/preview`.

Dispatch: a single `case "${1:-}" in … esac` placed **after** all function definitions and **before** argument parsing; each arm calls one `do_*` and exits.

---

### Task 1: Test harness + `--__treesort` (tree-order normalization)

**Files:**
- Create: `tests/specs-browse/_helpers.sh`
- Create: `tests/specs-browse/run.sh`
- Create: `tests/specs-browse/treesort_test.sh`
- Modify: `bin/specs-browse` (add `do_treesort`, add dispatch `case`)

**Interfaces:**
- Produces: `do_treesort` (stdin→stdout), and the dispatch `case` skeleton other tasks extend.

- [ ] **Step 1: Write the shared test harness**

Create `tests/specs-browse/_helpers.sh`:

```bash
# shared test helpers — source me
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB="$(cd "$_here/../.." && pwd)/bin/specs-browse"
_p=0; _f=0
assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then _p=$((_p+1)); else _f=$((_f+1));
    printf 'FAIL %s\n--- expected ---\n%s\n--- actual ---\n%s\n---\n' "$1" "$2" "$3"; fi
}
assert_contains() { # name haystack needle
  case "$2" in *"$3"*) _p=$((_p+1));; *) _f=$((_f+1));
    printf 'FAIL %s (missing: %s)\n%s\n' "$1" "$3" "$2";; esac
}
assert_not_contains() { # name haystack needle
  case "$2" in *"$3"*) _f=$((_f+1));
    printf 'FAIL %s (should NOT contain: %s)\n%s\n' "$1" "$3" "$2";; *) _p=$((_p+1));; esac
}
finish() { echo "$(basename "$0"): pass=$_p fail=$_f"; [ "$_f" -eq 0 ]; }
```

Create `tests/specs-browse/run.sh`:

```bash
#!/usr/bin/env bash
# runs every *_test.sh in this directory; nonzero exit if any fail
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$here"/*_test.sh; do bash "$t" || rc=1; done
exit $rc
```

- [ ] **Step 2: Write the failing test**

Create `tests/specs-browse/treesort_test.sh`:

```bash
#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"

raw=$'/a/z\n/a//b/\n/a\n/\n/a-b\n/a/b/c\n/a'
# expected pre-order: '/' sorts first, children of /a before sibling /a-b
exp=$'/\n/a\n/a/b\n/a/b/c\n/a/z\n/a-b'
got="$(printf '%s\n' "$raw" | "$SB" --__treesort)"
assert_eq "treesort: pre-order + collapse-slash + strip-trailing + dedup" "$exp" "$got"
finish
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/specs-browse/treesort_test.sh`
Expected: FAIL — current script treats `--__treesort` as an unknown option (exit 1, empty stdout), so `actual` is empty.

- [ ] **Step 4: Add `do_treesort` and the dispatch case**

In `bin/specs-browse`, add `do_treesort` immediately after the `join_path()` definition (around line 29):

```bash
do_treesort() {
    # stdin: raw find output; stdout: normalized, unique, tree-ordered paths.
    # Tree order = pre-order DFS with alphabetical siblings. Achieved by making
    # the path separator sort before every other byte (translate '/' -> \001).
    awk 'NF' \
      | awk '{ gsub(/\/+/, "/"); if ($0 != "/") sub(/\/$/, ""); print }' \
      | tr '/' '\001' \
      | LC_ALL=C sort -u \
      | tr '\001' '/'
}
```

Then add the dispatch `case` right after the existing `--__preview` `if [ "$1" = "--__preview" ]; then … fi` block (before `show_help`):

```bash
# ─── self-subcommand dispatch (invoked by this script / fzf) ─────────────────
case "${1:-}" in
    --__treesort) do_treesort; exit $? ;;
esac
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/specs-browse/treesort_test.sh`
Expected: `treesort_test.sh: pass=1 fail=0`

- [ ] **Step 6: Confirm the tool still runs**

Run: `bash bin/specs-browse -h`
Expected: help text prints (no regression).

- [ ] **Step 7: Commit**

```bash
git add tests/specs-browse/_helpers.sh tests/specs-browse/run.sh tests/specs-browse/treesort_test.sh bin/specs-browse
git commit -m "feat(specs-browse): add test harness + --__treesort tree-order normalizer"
```

---

### Task 2: `--__render` — collapsed tree (empty query)

**Files:**
- Create: `tests/specs-browse/render_tree_test.sh`
- Modify: `bin/specs-browse` (add `do_render`, extend dispatch)

**Interfaces:**
- Consumes: `$SPECS_BROWSE_PATHS`, `$SPECS_BROWSE_EXPANDED`, `$SPECS_BROWSE_ROOT`.
- Produces: `do_render "$query"` emitting `abspath \t display`. This task implements the empty-query (tree) path; Task 3 adds the filter path in the same function.

- [ ] **Step 1: Write the failing test**

Create `tests/specs-browse/render_tree_test.sh`:

```bash
#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/paths" <<'EOF'
/
/data
/data/app
/data/app/lens.apk
/data/system
/data/system/batterystats.bin
/vendor
/vendor/etc
/vendor/etc/battery.cfg
EOF
: > "$tmp/expanded"
export SPECS_BROWSE_PATHS="$tmp/paths" SPECS_BROWSE_EXPANDED="$tmp/expanded" SPECS_BROWSE_ROOT="/"

exp_collapsed=$'▾ /\n  ▸ data\n  ▸ vendor'
got="$("$SB" --__render "" | cut -f2)"
assert_eq "collapsed root shows depth-1 dirs only" "$exp_collapsed" "$got"

printf '/data\n' > "$tmp/expanded"
exp_expanded=$'▾ /\n  ▾ data\n    ▸ app\n    ▸ system\n  ▸ vendor'
got="$("$SB" --__render "" | cut -f2)"
assert_eq "expanding /data reveals exactly one more level" "$exp_expanded" "$got"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/specs-browse/render_tree_test.sh`
Expected: FAIL — `--__render` is an unknown option today (empty stdout).

- [ ] **Step 3: Add `do_render` (tree mode) and dispatch arm**

Add `do_render` after `do_treesort` in `bin/specs-browse`:

```bash
do_render() {
    local q="$1"
    local paths="$SPECS_BROWSE_PATHS"
    local expf="$SPECS_BROWSE_EXPANDED"
    local root="${SPECS_BROWSE_ROOT:-/}"
    local matchf=""
    [ -f "$expf" ] || expf=/dev/null
    # (filter matching added in Task 3)
    awk -v root="$root" -v expfile="$expf" -v matchfile="${matchf:-}" \
        -v mode="${q:+filter}" '
      function comps(p,   n){ if (p=="/") return 0; n=gsub(/\//,"",p); return n }
      function parent(p,   k){ if (p=="/") return "/"; k=p; sub(/\/[^\/]*$/,"",k); if (k=="") return "/"; return k }
      function base(p,   k){ if (p=="/") return "/"; k=p; sub(/^.*\//,"",k); return k }
      FILENAME==expfile { expset[$0]=1; next }
      matchfile!="" && FILENAME==matchfile { m[$0]=1; next }
      { n++; path[n]=$0 }
      END {
        for (i=1;i<=n;i++)
          isdir[i] = ( (path[i]=="/" && n>1) || (i<n && substr(path[i+1],1,length(path[i])+1)==path[i] "/") ) ? 1 : 0
        for (i=1;i<=n;i++) byname[path[i]]=i
        if (mode=="filter") {
          for (i=1;i<=n;i++) if (path[i] in m) {
            show[i]=1; p=path[i]
            while (p!="/" && p!=root) { p=parent(p); anc[p]=1 }
            anc[root]=1; anc["/"]=1
          }
          for (i=1;i<=n;i++) if (path[i] in anc) show[i]=1
        } else {
          for (i=1;i<=n;i++) {
            p=path[i]
            if (p==root) { show[i]=1; continue }
            par=parent(p)
            parshown = (par==root) ? 1 : show[byname[par]]
            parexp   = (par==root) ? 1 : (par in expset)
            if (parshown && parexp) show[i]=1
          }
        }
        for (i=1;i<=n;i++) {
          if (!show[i]) continue
          p=path[i]
          d=comps(p)-comps(root); if (d<0) d=0
          ind=""; for (j=0;j<d;j++) ind=ind "  "
          if (isdir[i]) {
            ex = (mode=="filter") ? 1 : ((p==root) ? 1 : (p in expset))
            g = ex ? "▾" : "▸"
          } else g=" "
          printf "%s\t%s%s %s\n", p, ind, g, base(p)
        }
      }
    ' "$expf" ${matchf:+"$matchf"} "$paths"
    return 0
}
```

Extend the dispatch `case`:

```bash
    --__render)   shift; do_render "${1:-}"; exit $? ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/specs-browse/render_tree_test.sh`
Expected: `render_tree_test.sh: pass=2 fail=0`

- [ ] **Step 5: Commit**

```bash
git add tests/specs-browse/render_tree_test.sh bin/specs-browse
git commit -m "feat(specs-browse): render collapsed tree (--__render, empty query)"
```

---

### Task 3: `--__render` — fuzzy filter keeping ancestors

**Files:**
- Create: `tests/specs-browse/render_filter_test.sh`
- Modify: `bin/specs-browse` (add `fzf --filter` matching to `do_render`)

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: filter behavior — matches (fzf-style fuzzy) plus all their ancestor dirs; ancestors render expanded (`▾`); non-matching siblings hidden.

- [ ] **Step 1: Write the failing test**

Create `tests/specs-browse/render_filter_test.sh`:

```bash
#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"
command -v fzf >/dev/null || { echo "$(basename "$0"): SKIP (no fzf)"; exit 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/paths" <<'EOF'
/
/data
/data/app
/data/app/lens.apk
/data/system
/data/system/batterystats.bin
/vendor
/vendor/etc
/vendor/etc/battery.cfg
EOF
: > "$tmp/expanded"
export SPECS_BROWSE_PATHS="$tmp/paths" SPECS_BROWSE_EXPANDED="$tmp/expanded" SPECS_BROWSE_ROOT="/"

out="$("$SB" --__render "battery" | cut -f2)"
assert_contains     "match keeps batterystats leaf"   "$out" "batterystats.bin"
assert_contains     "match keeps battery.cfg leaf"    "$out" "battery.cfg"
assert_contains     "ancestor 'system' shown expanded" "$out" "▾ system"
assert_contains     "ancestor 'etc' shown expanded"    "$out" "▾ etc"
assert_not_contains "non-matching lens.apk hidden"     "$out" "lens.apk"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/specs-browse/render_filter_test.sh`
Expected: FAIL — with no matcher wired, `m[]` is empty, so a non-empty query yields empty output (leaves missing).

- [ ] **Step 3: Wire `fzf --filter` into `do_render`**

In `do_render`, replace the placeholder comment line:

```bash
    # (filter matching added in Task 3)
```

with:

```bash
    if [ -n "$q" ]; then
        matchf="$(mktemp)"
        fzf --filter="$q" < "$paths" > "$matchf" 2>/dev/null
    fi
```

And after the `awk … "$paths"` invocation, add cleanup before `return 0`:

```bash
    [ -n "$matchf" ] && rm -f "$matchf"
```

(The awk body already consumes `matchfile`/`m[]` and the `mode=="filter"` branch — no awk change needed.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/specs-browse/render_filter_test.sh`
Expected: `render_filter_test.sh: pass=5 fail=0`

- [ ] **Step 5: Confirm tree mode still passes (no regression)**

Run: `bash tests/specs-browse/render_tree_test.sh`
Expected: `render_tree_test.sh: pass=2 fail=0`

- [ ] **Step 6: Commit**

```bash
git add tests/specs-browse/render_filter_test.sh bin/specs-browse
git commit -m "feat(specs-browse): fuzzy filter keeps matches + ancestor folders"
```

---

### Task 4: `--__expand-all` and `--__act` (dir toggle)

**Files:**
- Create: `tests/specs-browse/expand_test.sh`
- Modify: `bin/specs-browse` (add `do_expand_all`, `is_dir_in_cache`, `toggle_expanded`, `do_act`, dispatch arms)

**Interfaces:**
- Produces: `do_expand_all`, `is_dir_in_cache`, `toggle_expanded`, `do_act`, `do_toggle`. `do_act` on a file calls `view_file` (added Task 5); this task tests only the dir/no-op paths (no device).

- [ ] **Step 1: Write the failing test**

Create `tests/specs-browse/expand_test.sh`:

```bash
#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/paths" <<'EOF'
/
/data
/data/app
/data/app/lens.apk
/data/system
/data/system/batterystats.bin
/vendor
/vendor/etc
/vendor/etc/battery.cfg
EOF
export SPECS_BROWSE_PATHS="$tmp/paths" SPECS_BROWSE_EXPANDED="$tmp/expanded"

: > "$tmp/expanded"
"$SB" --__expand-all
exp=$'/\n/data\n/data/app\n/data/system\n/vendor\n/vendor/etc'
assert_eq "expand-all records every directory" "$exp" "$(cat "$tmp/expanded")"

: > "$tmp/expanded"
"$SB" --__act /data
assert_eq "act on dir adds it to expanded"      "/data" "$(cat "$tmp/expanded")"
"$SB" --__act /data
assert_eq "act on same dir removes it"          ""      "$(cat "$tmp/expanded")"

# --__toggle is dir-only (safe to bind to a silent key that never opens files)
: > "$tmp/expanded"
"$SB" --__toggle /data/app/lens.apk
assert_eq "toggle on a FILE is a no-op"         ""        "$(cat "$tmp/expanded")"
"$SB" --__toggle /vendor
assert_eq "toggle on a DIR expands it"          "/vendor" "$(cat "$tmp/expanded")"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/specs-browse/expand_test.sh`
Expected: FAIL — `--__expand-all` / `--__act` are unknown options.

- [ ] **Step 3: Add the functions and dispatch arms**

Add after `do_render` in `bin/specs-browse`:

```bash
do_expand_all() {
    local paths="$SPECS_BROWSE_PATHS" expf="$SPECS_BROWSE_EXPANDED"
    awk '
      { n++; p[n]=$0 }
      END { for (i=1;i<=n;i++)
              if ( (p[i]=="/" && n>1) || (i<n && substr(p[i+1],1,length(p[i])+1)==p[i] "/") )
                print p[i] }
    ' "$paths" >> "$expf"
    LC_ALL=C sort -u "$expf" -o "$expf"
}

is_dir_in_cache() {
    awk -v t="$1/" 'index($0,t)==1 { found=1; exit } END { exit found?0:1 }' "$SPECS_BROWSE_PATHS"
}

toggle_expanded() {
    local t="$1" f="$SPECS_BROWSE_EXPANDED"
    if grep -qxF -- "$t" "$f" 2>/dev/null; then
        grep -vxF -- "$t" "$f" > "$f.tmp" 2>/dev/null; mv "$f.tmp" "$f"
    else
        printf '%s\n' "$t" >> "$f"
    fi
}

do_act() {
    local target="$1"
    [ -z "$target" ] && return 0
    if is_dir_in_cache "$target"; then toggle_expanded "$target"; else view_file "$target"; fi
}

do_toggle() {
    # dir-only toggle — safe to bind to a silent key (no-op on files, never opens)
    [ -n "$1" ] && is_dir_in_cache "$1" && toggle_expanded "$1"
    return 0
}
```

Extend the dispatch `case`:

```bash
    --__expand-all) do_expand_all; exit $? ;;
    --__act)        shift; do_act "${1:-}"; exit $? ;;
    --__toggle)     shift; do_toggle "${1:-}"; exit $? ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/specs-browse/expand_test.sh`
Expected: `expand_test.sh: pass=5 fail=0`

- [ ] **Step 5: Commit**

```bash
git add tests/specs-browse/expand_test.sh bin/specs-browse
git commit -m "feat(specs-browse): expand-all + dir expand/collapse toggle (--__act)"
```

---

### Task 5: Device layer — prune expr, crawl, pull, preview

**Files:**
- Create: `tests/specs-browse/prune_expr_test.sh`
- Modify: `bin/specs-browse` (add `build_prune_expr`, `spin`, `do_crawl`, `do_pull`, `view_file`, `do_preview`, dispatch arms)

**Interfaces:**
- Produces: `build_prune_expr` (pure, tested), plus device-touching `do_crawl`/`do_pull`/`view_file`/`do_preview` (manually verified — smoke-checked only when a device is attached).

- [ ] **Step 1: Write the failing test (pure part)**

Create `tests/specs-browse/prune_expr_test.sh`:

```bash
#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"
assert_eq "prune expr joins paths with -o -path" \
  "-path /proc -o -path /sys -o -path /dev" \
  "$("$SB" --__prune-expr "/proc /sys /dev")"
assert_eq "prune expr single path" \
  "-path /proc" \
  "$("$SB" --__prune-expr "/proc")"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/specs-browse/prune_expr_test.sh`
Expected: FAIL — `--__prune-expr` unknown option.

- [ ] **Step 3: Add device-layer functions and dispatch arms**

Add after `do_act` in `bin/specs-browse`:

```bash
build_prune_expr() {
    # echo: -path A -o -path B ...   (input: space-separated roots)
    local first=1 p out=""
    for p in $1; do
        if [ "$first" = 1 ]; then out="-path $p"; first=0; else out="$out -o -path $p"; fi
    done
    printf '%s' "$out"
}

spin() {
    # spin <pid> <label>   (ASCII frames — bash 3.2 substrings are byte-wise)
    local pid="$1" label="$2" frames='|/-\' i=0 n=4
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % n ))
        printf '\r%s %s ' "${frames:$i:1}" "$label" >&2
        sleep 0.1
    done
    printf '\r\033[K' >&2
}

do_crawl() {
    local root="${SPECS_BROWSE_ROOT:-/}" S="$SPECS_BROWSE_SERIAL"
    local prune="${SPECS_BROWSE_PRUNE:-/proc /sys /dev /acct /apex /config}"
    local expr tmp pid
    expr="$(build_prune_expr "$prune")"
    tmp="${SPECS_BROWSE_PATHS}.tmp"
    ( adb -s "$S" shell "find '$root' \\( $expr \\) -prune -o -print" 2>/dev/null \
        | "$self" --__treesort > "$tmp" ) &
    pid=$!
    spin "$pid" "crawling $S"
    wait "$pid"
    if [ -s "$tmp" ]; then mv "$tmp" "$SPECS_BROWSE_PATHS"; else rm -f "$tmp"; return 1; fi
}

do_pull() {
    local p="$1" S="$SPECS_BROWSE_SERIAL"
    printf '↓ pulling %s → %s/\n' "$p" "$PWD"
    if adb -s "$S" pull "$p" . ; then echo "done."; else echo "pull failed."; fi
    read -rsn1 -p 'press any key…'; echo
}

view_file() {
    local p="$1" S="$SPECS_BROWSE_SERIAL" tmp f
    tmp="$(mktemp -d)"; f="$tmp/$(basename "$p")"
    if adb -s "$S" pull "$p" "$f" >/dev/null 2>&1; then
        if command -v preview >/dev/null; then preview "$f"; else less -R "$f" 2>/dev/null || cat "$f"; fi
    else
        printf 'could not pull %s\n' "$p"; read -rsn1 -p 'press any key…'; echo
    fi
    rm -rf "$tmp"
}

do_preview() {
    local p="$1" S="$SPECS_BROWSE_SERIAL" ext
    if is_dir_in_cache "$p"; then
        printf '📁 %s\n\n' "$p"; adb -s "$S" shell "ls -lAh '$p'" 2>&1; return 0
    fi
    adb -s "$S" shell "ls -lh '$p'" 2>&1; echo
    ext="$(printf '%s' "${p##*.}" | tr '[:upper:]' '[:lower:]')"
    case "$ext" in
        png|jpg|jpeg|gif|bmp|webp|tif|tiff|ico|heic|heif|mp4|mov|webm|\
        bin|so|a|o|zip|gz|tar|apk|jar|dex|odex|ttf|otf|pdf)
            printf '[%s — binary, press Enter to open]\n' "$ext";;
        *)
            adb -s "$S" exec-out "cat '$p'" 2>/dev/null | head -c 16384 | cat -v
            [ "${PIPESTATUS[0]}" -ne 0 ] && printf '\n[no preview available]\n';;
    esac
    return 0
}
```

Extend the dispatch `case`:

```bash
    --__prune-expr) shift; build_prune_expr "${1:-}"; exit $? ;;
    --__crawl)      do_crawl; exit $? ;;
    --__pull)       shift; do_pull "${1:-}"; exit $? ;;
```

(Note: `--__preview` is still served by the **old** top-of-file block until Task 6 — do not remove it yet.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/specs-browse/prune_expr_test.sh`
Expected: `prune_expr_test.sh: pass=2 fail=0`

- [ ] **Step 5: Device smoke check (only if a device is attached)**

If `adb devices` shows a device, verify the crawl end-to-end:
```bash
out="$(mktemp)"
SPECS_BROWSE_SERIAL="$CV_SOC" SPECS_BROWSE_ROOT="/vendor/etc" \
SPECS_BROWSE_PATHS="$out" bash bin/specs-browse --__crawl \
  && echo "crawl OK ($(wc -l < "$out") paths)" && head "$out"
```
Expected: an ASCII spinner, then `crawl OK (N paths)` and a listing of `/vendor/etc/...` entries in tree order.
If no device is attached, skip — the pure suite (`prune_expr_test.sh`) plus `bash -n` is the automated gate; the device path is verified manually in Task 6 Step 7.

- [ ] **Step 6: Commit**

```bash
git add tests/specs-browse/prune_expr_test.sh bin/specs-browse
git commit -m "feat(specs-browse): device layer — prune expr, crawl, pull, path-based preview"
```

---

### Task 6: Swap the main loop to the tree engine

**Files:**
- Modify: `bin/specs-browse` (replace old `--__preview` block + browse loop + help; remove dead helpers)

**Interfaces:**
- Consumes: every `do_*` from Tasks 1–5.
- Produces: the interactive tree UI (final deliverable).

- [ ] **Step 1: Replace the old `--__preview` handler with a dispatch arm**

Delete the top-of-file block `if [ "$1" = "--__preview" ]; then … exit 0; fi` (v1 lines ~31–58). Add to the dispatch `case`:

```bash
    --__preview)  shift; do_preview "${1:-}"; exit $? ;;
```

- [ ] **Step 2: Remove now-dead helpers**

Delete `strip_classifier()` and `join_path()` (unused by the tree engine — the cache stores clean absolute paths).

- [ ] **Step 3: Replace the browse loop (v1 lines ~102–148) with the tree engine**

Replace the old `view_file` definition (now provided by Task 5) and the `while :; do … done` loop with:

```bash
# ─── tree engine ─────────────────────────────────────────────────────────────
STATE="$(mktemp -d)"; trap 'rm -rf "$STATE"' EXIT
export SPECS_BROWSE_SERIAL="$S"
export SPECS_BROWSE_ROOT="$START"
export SPECS_BROWSE_PATHS="$STATE/paths"
export SPECS_BROWSE_EXPANDED="$STATE/expanded"
: > "$SPECS_BROWSE_EXPANDED"

if ! "$self" --__crawl; then
    echo "specs-browse: nothing found under $START (device unreachable or empty)" >&2
    exit 1
fi

fzf --ansi --disabled --layout=reverse --height=100% \
    --delimiter=$'\t' --with-nth=2 \
    --header="📱 $S   $START"$'\n'"type=filter  Enter/Tab=open/expand  Ctrl-Y=pull→$PWD  Ctrl-R=refresh  Ctrl-E/W=expand/collapse-all  Esc=quit" \
    --bind "start:reload($self --__render {q})" \
    --bind "change:reload($self --__render {q})" \
    --bind "enter:execute($self --__act {1})+reload($self --__render {q})" \
    --bind "tab:execute-silent($self --__toggle {1})+reload($self --__render {q})" \
    --bind "ctrl-y:execute($self --__pull {1})+reload($self --__render {q})" \
    --bind "ctrl-r:execute($self --__crawl)+reload($self --__render {q})" \
    --bind "ctrl-e:execute-silent($self --__expand-all)+reload($self --__render {q})" \
    --bind "ctrl-w:execute-silent(: > \"$SPECS_BROWSE_EXPANDED\")+reload($self --__render {q})" \
    --preview "$self --__preview {1}" \
    --preview-window=right,58%,wrap
```

- [ ] **Step 4: Update the header comment + `show_help`**

In the top comment block, replace the key legend with the tree keys (Enter/Tab expand or open, Ctrl-Y pull, Ctrl-R refresh, Ctrl-E/W expand/collapse-all, type to fuzzy-search the whole tree). Update the `show_help` usage note:

```
Defaults: ROOT=/ (crawled once, minus $SPECS_BROWSE_PRUNE)
          prune=${SPECS_BROWSE_PRUNE:-/proc /sys /dev /acct /apex /config}
Pass a narrower ROOT (e.g. specs-browse /sys) to scope the crawl.
```

- [ ] **Step 5: Full regression — all unit tests still pass**

Run: `bash tests/specs-browse/run.sh`
Expected: every `*_test.sh` prints `fail=0`; overall exit 0.

- [ ] **Step 6: Syntax check + help**

Run: `bash -n bin/specs-browse && bash bin/specs-browse -h`
Expected: no syntax errors; help shows the new keys/defaults.

- [ ] **Step 7: Manual end-to-end (device attached)**

Run: `specs-browse /vendor` (or `specs-browse` for whole device). Verify:
- initial collapsed tree renders after the crawl spinner;
- typing filters and matches keep their parent folders;
- Tab expands/collapses a highlighted dir with no screen flash (and is a no-op on files);
- Enter opens a highlighted file (via `~/bin/preview`) and toggles a highlighted dir;
- Ctrl-Y pulls; Ctrl-R re-crawls; Ctrl-E/Ctrl-W expand/collapse all; Esc quits.
If no device is attached, note it and rely on the unit suite + `bash -n`.

- [ ] **Step 8: Commit**

```bash
git add bin/specs-browse
git commit -m "feat(specs-browse): searchable collapsible filetree UI (main loop swap)"
```

---

## Notes for the implementer

- **Why `fzf --disabled`:** we own filtering so ancestor folders stay visible around matches. fzf still fires `change`/`start` and tracks the query (`{q}`), which drives `--__render`. This is fzf's documented "external filter" pattern.
- **Why lexicographic sort needs the `\001` trick:** plain sort places `a-b` before `a/child` (because `-` < `/`), breaking pre-order. Translating `/`→`\001` (which sorts before all printable bytes) restores parent-before-children with alphabetical siblings. Covered by `treesort_test.sh`.
- **Empty directories** render as non-expandable leaves (no cache descendants). Accepted trade-off from the spec.
- **Filter tests use `battery`** — a literal substring of both target basenames — so membership is stable across fzf versions while still exercising the fuzzy path.
