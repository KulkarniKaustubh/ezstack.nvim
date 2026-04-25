-- Contract tests for the `:Ezs` command dispatcher.

local H = require("tests.helpers")

describe("ezstack.commands", function()
  local cmds

  before_each(function()
    H.reload()
    cmds = require("ezstack.commands")
  end)

  it("every SUBCOMMAND_NAMES entry has a dispatch handler", function()
    -- This is the regression test for the `:Ezs actions` bug: a name
    -- advertised in tab-completion must resolve to a real handler.
    for _, name in ipairs(cmds._subcommand_names) do
      assert.equals(
        "function",
        type(cmds._subcommands[name]),
        "missing handler for subcommand: " .. name
      )
    end
  end)

  it("SUBCOMMAND_NAMES is deduplicated and sorted-ish (no trailing dupes)", function()
    local seen = {}
    for _, n in ipairs(cmds._subcommand_names) do
      assert.is_nil(seen[n], "duplicate in SUBCOMMAND_NAMES: " .. n)
      seen[n] = true
    end
  end)

  describe(":Ezs config set value parsing", function()
    -- Regression for the strict-arg change in the CLI: `config set` now
    -- requires the value as a single argv slot. The plugin's `:Ezs` arg
    -- splitter is whitespace-only, so multi-word values had to be re-joined
    -- by parse_config_set to survive the trip. These cases pin both the
    -- happy path and the quote-stripping behavior.
    local p

    before_each(function()
      p = cmds._parse_config_set
    end)

    it("returns key + value for a single-token value", function()
      local k, v = p("set agent_command claude")
      assert.equals("agent_command", k)
      assert.equals("claude", v)
    end)

    it("joins multi-token unquoted value by whitespace", function()
      -- Mirrors the pre-strict CLI behavior so users who relied on
      -- `:Ezs config set agent_command claude --foo` still get
      -- "claude --foo" stored as one value.
      local k, v = p("set agent_command claude --dangerously-skip-permissions")
      assert.equals("agent_command", k)
      assert.equals("claude --dangerously-skip-permissions", v)
    end)

    it("strips surrounding double quotes", function()
      local k, v = p('set agent_command "claude --foo"')
      assert.equals("agent_command", k)
      assert.equals("claude --foo", v)
    end)

    it("strips surrounding single quotes", function()
      local k, v = p("set agent_command 'claude --foo'")
      assert.equals("agent_command", k)
      assert.equals("claude --foo", v)
    end)

    it("preserves embedded quotes inside the value", function()
      -- Only one outer layer is stripped; embedded quotes survive.
      local k, v = p('set agent_command "claude \'inner\'"')
      assert.equals("agent_command", k)
      assert.equals("claude 'inner'", v)
    end)

    it("does not strip mismatched quote characters", function()
      local k, v = p([[set agent_command "claude --foo']])
      assert.equals("agent_command", k)
      assert.equals([["claude --foo']], v)
    end)

    it("returns nil for missing value", function()
      local k, v = p("set agent_command")
      assert.is_nil(k)
      assert.is_nil(v)
    end)

    it("returns nil for missing key and value", function()
      local k, v = p("set")
      assert.is_nil(k)
      assert.is_nil(v)
    end)

    it("returns nil when input doesn't start with 'set'", function()
      local k, v = p("show agent_command")
      assert.is_nil(k)
      assert.is_nil(v)
    end)

    it("trims trailing whitespace from value", function()
      local k, v = p("set agent_command claude   ")
      assert.equals("agent_command", k)
      assert.equals("claude", v)
    end)

    it("handles paths with spaces when quoted", function()
      local k, v = p([[set worktree_base_dir "/path with spaces/wt"]])
      assert.equals("worktree_base_dir", k)
      assert.equals("/path with spaces/wt", v)
    end)
  end)

  describe(":Ezs diff passthrough detection", function()
    local p

    before_each(function()
      p = cmds._looks_like_diff_passthrough
    end)

    it("returns false for no args (use viewer)", function()
      assert.is_false(p({}))
    end)

    it("returns false for a plain branch name", function()
      assert.is_false(p({ "feature-1" }))
      assert.is_false(p({ "origin/main" }))
    end)

    it("returns true for an explicit `--` terminator", function()
      assert.is_true(p({ "--", "--stat" }))
    end)

    it("returns true for any single-dash or double-dash flag", function()
      assert.is_true(p({ "-b", "main" }))
      assert.is_true(p({ "--stat" }))
      assert.is_true(p({ "--json" }))
      assert.is_true(p({ "branch", "--stat" }))
    end)
  end)
end)
