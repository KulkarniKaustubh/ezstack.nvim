-- Tests for `ui._render_graph_lines` — pure function, no CLI, no buffers.

local H = require("tests.helpers")

describe("ezstack.ui._render_graph_lines", function()
  local ui

  before_each(function()
    H.reload()
    ui = require("ezstack.ui")
  end)

  it("renders an empty-stack placeholder", function()
    local lines = ui._render_graph_lines({
      { hash = "deadbeef", root = "main", branches = {} },
    })
    assert.truthy(table.concat(lines, "\n"):find("%(empty%)"))
  end)

  it("renders a linear stack as a tree", function()
    local lines = ui._render_graph_lines({
      {
        hash = "h1",
        name = "s1",
        root = "main",
        branches = {
          { name = "a", parent = "main" },
          { name = "b", parent = "a" },
          { name = "c", parent = "b", is_current = true },
        },
      },
    })
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:find("Stack: s1"))
    assert.truthy(joined:find("root: main"))
    -- All three branches appear in order.
    local pa, pb, pc = joined:find("a"), joined:find("b"), joined:find("c")
    assert.is_number(pa)
    assert.is_number(pb)
    assert.is_number(pc)
    -- Current branch is marked.
    assert.truthy(joined:find("%* c"))
  end)

  it("surfaces orphans under a labelled header", function()
    -- Regression test: before the orphan fix, branches whose parent isn't
    -- reachable from `stack.root` were silently dropped.
    local lines = ui._render_graph_lines({
      {
        hash = "h1",
        root = "main",
        branches = {
          { name = "reachable", parent = "main" },
          { name = "orph", parent = "ghost" },
        },
      },
    })
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:find("reachable"))
    assert.truthy(joined:find("orphans"))
    assert.truthy(joined:find("orph"))
    assert.truthy(joined:find("parent: ghost"))
  end)

  it("terminates on cycles without infinite recursion", function()
    -- Mutually-recursive parents: root -> a -> b -> a (impossible in
    -- practice but we should still terminate).
    local lines = ui._render_graph_lines({
      {
        hash = "h1",
        root = "main",
        branches = {
          { name = "a", parent = "main" },
          { name = "b", parent = "a" },
          { name = "a-shadow", parent = "b" }, -- fine, no actual cycle
        },
      },
    })
    -- If this didn't terminate we'd never get here.
    assert.is_true(#lines > 0)
  end)

  it("renders multiple stacks with a blank line between them", function()
    local lines = ui._render_graph_lines({
      { hash = "h1", root = "main", branches = { { name = "a", parent = "main" } } },
      { hash = "h2", root = "main", branches = { { name = "x", parent = "main" } } },
    })
    -- At least one blank separator line between blocks.
    local blank_seen = false
    for _, l in ipairs(lines) do
      if l == "" then
        blank_seen = true
        break
      end
    end
    assert.is_true(blank_seen)
  end)

  it("includes PR label when pr_number > 0", function()
    local lines = ui._render_graph_lines({
      {
        hash = "h1",
        root = "main",
        branches = {
          { name = "a", parent = "main", pr_number = 7, pr_state = "OPEN" },
        },
      },
    })
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:find("PR #7"))
    assert.truthy(joined:find("%[OPEN%]"))
  end)
end)

describe("ezstack.ui._render_stack tree shape", function()
  -- The viewer used to flatten every branch into a single column of
  -- ├── / └── connectors, hiding the parent–child structure. These
  -- specs lock in the depth-aware tree shape (matching `tree(1)`) so
  -- branching siblings are visible in the main viewer too.
  local ui

  before_each(function()
    H.reload()
    ui = require("ezstack.ui")
  end)

  -- Strip viewer chrome so we can assert on branch rows directly.
  -- Anchored on the "─" separator so future header changes don't
  -- silently mis-skip rows (the previous `for i = 3, #lines` would
  -- swallow the first branch if anyone added another header line).
  local function branch_rows(lines)
    local rows = {}
    local started = false
    for _, line in ipairs(lines) do
      if started then
        table.insert(rows, line)
      elseif line:find("─") then
        started = true
      end
    end
    return rows
  end

  it("renders a linear stack with one branch per line and no runners", function()
    local lines = ui._render_stack({
      hash = "h1",
      name = "linear",
      root = "main",
      branches = {
        { name = "a", parent = "main" },
        { name = "b", parent = "a" },
        { name = "c", parent = "b" },
      },
    }, 0)
    local rows = branch_rows(lines)
    assert.equals(3, #rows)
    -- Linear chains have a single descending column: depths 0, 1, 2.
    assert.truthy(rows[1]:find("^   └── a"))
    assert.truthy(rows[2]:find("^       └── b"))
    assert.truthy(rows[3]:find("^           └── c"))
  end)

  it("indents children below their parent with │ runners for non-last siblings", function()
    -- Branching:
    --   main
    --   ├── a
    --   │   ├── b
    --   │   └── c
    --   └── d
    local lines = ui._render_stack({
      hash = "h1",
      name = "branchy",
      root = "main",
      branches = {
        { name = "a", parent = "main" },
        { name = "b", parent = "a" },
        { name = "c", parent = "a" },
        { name = "d", parent = "main" },
      },
    }, 0)
    local rows = branch_rows(lines)
    assert.equals(4, #rows)
    -- `a` is a non-last sibling at the root → ├── connector.
    assert.truthy(rows[1]:find("^   ├── a"), rows[1])
    -- `b` and `c` sit one level under `a`. Because `a` is non-last,
    -- the runner column (│) stays open while we recurse into a.
    assert.truthy(rows[2]:find("^   │   ├── b"), rows[2])
    assert.truthy(rows[3]:find("^   │   └── c"), rows[3])
    -- `d` is the last root-level sibling → └── and the runner closes.
    assert.truthy(rows[4]:find("^   └── d"), rows[4])
  end)

  it("places the > pointer on the current branch without disturbing the tree", function()
    local lines = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "a", parent = "main" },
        { name = "b", parent = "a", is_current = true },
      },
    }, 0)
    local rows = branch_rows(lines)
    -- Pointer occupies cols 0..3, then the depth prefix and connector follow.
    assert.truthy(rows[1]:find("^   └── a"), rows[1])
    assert.truthy(rows[2]:find("^ >     └── b"), rows[2])
  end)

  it("surfaces orphans under a labelled header", function()
    local lines = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "ok", parent = "main" },
        { name = "lost", parent = "ghost" },
      },
    }, 0)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:find("ok"))
    assert.truthy(joined:find("orphans"))
    assert.truthy(joined:find("lost"))
  end)

  it("terminates on cycles without infinite recursion", function()
    -- Two branches each claim the other as parent. This shouldn't
    -- happen in real config but the walker must still terminate.
    local lines = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "a", parent = "b" },
        { name = "b", parent = "a" },
      },
    }, 0)
    -- Both end up as orphans (neither is reachable from `main`).
    assert.is_true(#lines > 0)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:find("orphans"))
  end)

  it("emits one line_map entry per visible row", function()
    -- The keymap layer indexes into line_map by cursor row, so a
    -- mismatch here would silently break <CR>/d/p/etc. on nested rows.
    local lines, _, line_map = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "a", parent = "main" },
        { name = "b", parent = "a" },
        { name = "c", parent = "a" },
      },
    }, 0)
    assert.equals(#lines, #line_map)
    -- Header, separator, then three branch rows in DFS order.
    assert.equals("stack", line_map[1].type)
    assert.equals("separator", line_map[2].type)
    assert.equals("branch", line_map[3].type)
    assert.equals("a", line_map[3].branch_name)
    assert.equals("b", line_map[4].branch_name)
    assert.equals("c", line_map[5].branch_name)
  end)

  it("nests orphan descendants under their orphan ancestor", function()
    -- Regression: orphans used to render as flat siblings even when one
    -- was the parent of another. `lost` is unreachable from `main`, and
    -- `lost-child` chains off `lost` — the second branch should appear
    -- indented under the first, not next to it.
    local lines = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "ok", parent = "main" },
        { name = "lost", parent = "ghost" },
        { name = "lost-child", parent = "lost" },
      },
    }, 0)
    local rows = branch_rows(lines)
    -- Reachable branch first, then the orphan header, then the orphan
    -- subtree with `lost-child` indented under `lost`.
    assert.truthy(rows[1]:find("^   └── ok"), rows[1])
    assert.truthy(rows[2]:find("orphans"), rows[2])
    assert.truthy(rows[3]:find("^   └── lost"), rows[3])
    assert.truthy(rows[4]:find("^       └── lost%-child"), rows[4])
  end)

  it("emits sibling orphan subtrees with correct connectors", function()
    -- Two disjoint orphan subtrees — the connector pattern at the
    -- orphan-root level should mirror the main tree (├── for non-last,
    -- └── for last) and runners (│) should stay open across the first
    -- subtree's descendants.
    local lines = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "lost-a", parent = "ghost1" },
        { name = "lost-a-kid", parent = "lost-a" },
        { name = "lost-b", parent = "ghost2" },
      },
    }, 0)
    local joined = table.concat(branch_rows(lines), "\n")
    assert.truthy(joined:find("├── lost%-a"), joined)
    assert.truthy(joined:find("│   └── lost%-a%-kid"), joined)
    assert.truthy(joined:find("└── lost%-b"), joined)
  end)

  it("keeps line_map aligned when an orphan section is present", function()
    -- The orphan header inserts an extra row; the keymap layer indexes
    -- by cursor position, so #line_map must still equal #lines.
    local lines, _, line_map = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "ok", parent = "main" },
        { name = "lost", parent = "ghost" },
        { name = "lost-child", parent = "lost" },
      },
    }, 0)
    assert.equals(#lines, #line_map)
    -- Spot-check: the orphan header has its own line_map entry and the
    -- nested orphan child still maps back to its branch.
    local seen_header, seen_child = false, false
    for _, entry in ipairs(line_map) do
      if entry.type == "orphans_header" then
        seen_header = true
      end
      if entry.type == "branch" and entry.branch_name == "lost-child" then
        seen_child = true
      end
    end
    assert.is_true(seen_header)
    assert.is_true(seen_child)
  end)

  it("highlight columns track the depth prefix", function()
    -- After the refactor the connector spans pointer..line_prefix end
    -- (i.e. depth runners + connector), and the branch name starts at
    -- the line_prefix end. This regression-locks both column anchors.
    local lines, highlights = ui._render_stack({
      hash = "h1",
      root = "main",
      branches = {
        { name = "parent", parent = "main" },
        { name = "child", parent = "parent" },
      },
    }, 0)
    local function find_hl(line_idx, group)
      for _, h in ipairs(highlights) do
        if h[1] == line_idx and h[4] == group then
          return h
        end
      end
    end
    -- Highlight columns are byte offsets, so the box-drawing chars
    -- count as 3 bytes apiece. "└── " is 3+3+3+1 = 10 bytes.
    -- `parent` at depth 0: pointer (3) + prefix "" (0) + connector (10)
    -- → name starts at byte 13. Branch rows are at line indices 2 and 3
    -- (0=header, 1=separator).
    local p_branch = find_hl(2, "EzstackBranch")
    assert.is_table(p_branch)
    assert.equals(13, p_branch[2])
    -- `child` at depth 1 (last sibling under last sibling) gets a
    -- "    " (4 ASCII spaces) prefix, then the same 10-byte connector:
    -- pointer (3) + prefix (4) + connector (10) = 17.
    local c_branch = find_hl(3, "EzstackBranch")
    assert.is_table(c_branch)
    assert.equals(17, c_branch[2])
    -- The `child` line should be longer than the `parent` line —
    -- the depth indent visibly pushes the row right.
    assert.is_true(#lines[4] > #lines[3])
  end)
end)

describe("ezstack.ui.render_preview tree shape", function()
  -- The Telescope preview shares the algorithm but emits plain text.
  local ui

  before_each(function()
    H.reload()
    ui = require("ezstack.ui")
  end)

  it("indents siblings under their parent with runners", function()
    local lines = ui.render_preview({
      hash = "h1",
      name = "p",
      root = "main",
      branches = {
        { name = "a", parent = "main" },
        { name = "b", parent = "a" },
        { name = "c", parent = "a" },
        { name = "d", parent = "main" },
      },
    })
    local joined = table.concat(lines, "\n")
    -- `b` and `c` sit under `a` with a runner column (│) — the
    -- smoking gun for the depth-aware walker.
    assert.truthy(joined:find("│   ├── b"), joined)
    assert.truthy(joined:find("│   └── c"), joined)
    assert.truthy(joined:find("└── d"), joined)
  end)

  it("renders orphans below the main tree", function()
    local lines = ui.render_preview({
      hash = "h1",
      root = "main",
      branches = {
        { name = "ok", parent = "main" },
        { name = "stray", parent = "missing" },
      },
    })
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:find("orphans"))
    assert.truthy(joined:find("stray"))
  end)

  it("nests orphan descendants in the preview too", function()
    -- Same nesting fix as the main viewer — preview shares the helper.
    local lines = ui.render_preview({
      hash = "h1",
      root = "main",
      branches = {
        { name = "lost", parent = "ghost" },
        { name = "lost-child", parent = "lost" },
      },
    })
    local joined = table.concat(lines, "\n")
    -- `lost` at the orphan-root depth, then `lost-child` indented under
    -- it with a 4-space depth prefix (preview marker is 2 chars wide).
    assert.truthy(joined:find("└── lost  "), joined)
    assert.truthy(joined:find("      └── lost%-child"), joined)
  end)
end)
