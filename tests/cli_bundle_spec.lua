-- Tests for the CLI-bundle features added to ezstack.nvim:
-- doctor, push --verify / --all-remotes, delete --cascade, pr --draft-all,
-- goto --search, config export / import. The companion CLI features in
-- the ezstack repo were already exercised there; these tests verify the
-- nvim plugin builds the right argv and dispatches to the right handler.

local H = require("tests.helpers")

-- Strip the binary path (first element) and return only the CLI argv.
local function argv(capture)
  local out = {}
  for i = 2, #capture.cmd do
    table.insert(out, capture.cmd[i])
  end
  return out
end

-- Find a capture whose argv (after the binary) starts with the given prefix.
-- Useful when a single user action triggers multiple background commands —
-- we want the assertion to pin the specific subcommand.
local function find_capture(captures, prefix)
  for _, c in ipairs(captures) do
    local args = argv(c)
    local match = true
    for i, want in ipairs(prefix) do
      if args[i] ~= want then
        match = false
        break
      end
    end
    if match then
      return args
    end
  end
  return nil
end

describe("ezstack.cli — push opts", function()
  local cli, stub

  before_each(function()
    H.reload()
    cli = require("ezstack.cli")
    stub = H.stub_vim_system()
  end)
  after_each(function() stub.restore() end)

  it("push() emits no extra flags by default", function()
    cli.push({}, function() end)
    local args = argv(stub.captures[1])
    -- The base form is `-y push`. No extra flags expected.
    assert.same({ "-y", "push" }, args)
  end)

  it("push({verify=true}) adds --verify", function()
    cli.push({ verify = true }, function() end)
    local args = argv(stub.captures[1])
    assert.is_true(vim.tbl_contains(args, "--verify"))
  end)

  it("push({all_remotes=true}) adds --all-remotes", function()
    cli.push({ all_remotes = true }, function() end)
    local args = argv(stub.captures[1])
    assert.is_true(vim.tbl_contains(args, "--all-remotes"))
  end)

  it("push({force=true, verify=true, all_remotes=true}) emits all three", function()
    cli.push({ force = true, verify = true, all_remotes = true }, function() end)
    local args = argv(stub.captures[1])
    assert.is_true(vim.tbl_contains(args, "--force"))
    assert.is_true(vim.tbl_contains(args, "--verify"))
    assert.is_true(vim.tbl_contains(args, "--all-remotes"))
  end)

  it("push_stack({verify=true}) preserves -s and adds --verify", function()
    cli.push_stack({ verify = true }, function() end)
    local args = argv(stub.captures[1])
    assert.is_true(vim.tbl_contains(args, "-s"))
    assert.is_true(vim.tbl_contains(args, "--verify"))
  end)
end)

describe("ezstack.cli — delete opts", function()
  local cli, stub

  before_each(function()
    H.reload()
    cli = require("ezstack.cli")
    stub = H.stub_vim_system()
  end)
  after_each(function() stub.restore() end)

  it("delete_branch(name) — backwards-compat 2-arg form (name, callback)", function()
    -- Older callers passed (name, callback). The new signature is
    -- (name, opts, callback) but must still accept the 2-arg form.
    cli.delete_branch("feat-a", function() end)
    local args = argv(stub.captures[1])
    -- No --cascade, no --force.
    assert.is_false(vim.tbl_contains(args, "--cascade"))
    assert.is_false(vim.tbl_contains(args, "--force"))
    assert.is_true(vim.tbl_contains(args, "feat-a"))
  end)

  it("delete_branch(name, {cascade=true}) adds --cascade", function()
    cli.delete_branch("feat-a", { cascade = true }, function() end)
    local args = argv(stub.captures[1])
    assert.is_true(vim.tbl_contains(args, "--cascade"))
  end)

  it("delete_branch(name, {force=true, cascade=true}) emits both", function()
    cli.delete_branch("feat-a", { force = true, cascade = true }, function() end)
    local args = argv(stub.captures[1])
    assert.is_true(vim.tbl_contains(args, "--cascade"))
    assert.is_true(vim.tbl_contains(args, "--force"))
  end)

  it("delete_branch puts the branch name AFTER the flags", function()
    -- pflag is order-tolerant, but several callers (and `git branch -D`)
    -- read positional args strictly. Keeping `--flags name` matches the
    -- documented usage.
    cli.delete_branch("feat-a", { cascade = true }, function() end)
    local args = argv(stub.captures[1])
    -- The branch name should be the last element.
    assert.equals("feat-a", args[#args])
  end)
end)

describe("ezstack.cli — config and pr extras", function()
  local cli, stub

  before_each(function()
    H.reload()
    cli = require("ezstack.cli")
    stub = H.stub_vim_system()
  end)
  after_each(function() stub.restore() end)

  it("config_export emits 'config export <path>'", function()
    cli.config_export("/tmp/cfg.json", function() end)
    local args = argv(stub.captures[1])
    assert.same({ "config", "export", "/tmp/cfg.json" }, args)
  end)

  it("config_import emits '-y config import <path>' (skips overwrite confirmation)", function()
    cli.config_import("/tmp/cfg.json", function() end)
    local args = argv(stub.captures[1])
    assert.same({ "-y", "config", "import", "/tmp/cfg.json" }, args)
  end)

  it("pr_draft_all emits '-y pr --draft-all'", function()
    cli.pr_draft_all(function() end)
    local args = argv(stub.captures[1])
    assert.same({ "-y", "pr", "--draft-all" }, args)
  end)

  it("goto_search emits 'goto --search <query>' (no -y; goto is read-only)", function()
    cli.goto_search("auth", function() end)
    local args = argv(stub.captures[1])
    assert.same({ "goto", "--search", "auth" }, args)
  end)
end)

describe("ezstack.commands — completion surfaces new flags", function()
  local cmds

  before_each(function()
    H.reload()
    cmds = require("ezstack.commands")
  end)

  it("`:Ezs pr <tab>` includes draft-all", function()
    local out = cmds.complete("", ":Ezs pr ", 0)
    assert.is_true(vim.tbl_contains(out, "draft-all"))
  end)

  it("`:Ezs sync <tab>` includes --stats and --squash", function()
    local out = cmds.complete("", ":Ezs sync ", 0)
    assert.is_true(vim.tbl_contains(out, "--stats"))
    assert.is_true(vim.tbl_contains(out, "--squash"))
  end)

  it("`:Ezs push <tab>` includes --verify and --all-remotes", function()
    local out = cmds.complete("", ":Ezs push ", 0)
    assert.is_true(vim.tbl_contains(out, "--verify"))
    assert.is_true(vim.tbl_contains(out, "--all-remotes"))
  end)

  it("`:Ezs config <tab>` includes export and import", function()
    local out = cmds.complete("", ":Ezs config ", 0)
    assert.is_true(vim.tbl_contains(out, "export"))
    assert.is_true(vim.tbl_contains(out, "import"))
  end)

  it("`:Ezs <tab>` includes doctor", function()
    local out = cmds.complete("", ":Ezs ", 0)
    assert.is_true(vim.tbl_contains(out, "doctor"))
  end)

  it("doctor handler is registered (regression for the SUBCOMMAND_NAMES contract)", function()
    -- Invariant from commands_spec.lua: every name has a handler. doctor
    -- was added as part of the CLI bundle; this test pins it.
    assert.equals("function", type(cmds._subcommands["doctor"]))
    assert.is_true(vim.tbl_contains(cmds._subcommand_names, "doctor"))
  end)
end)

describe("ezstack.commands — goto --search arg parsing", function()
  local cmds, cli, stub

  before_each(function()
    H.reload()
    cmds = require("ezstack.commands")
    cli = require("ezstack.cli")
    stub = H.stub_vim_system()
    -- Stub list_stacks too so the goto handler doesn't try to read real
    -- ezstack state. Returns one match for "auth".
    cli.list_stacks = function(cb)
      cb(nil, {
        {
          name = "test", root = "main",
          branches = { { name = "authentication", worktree_path = "/tmp/auth-wt" } },
        },
      })
    end
  end)
  after_each(function() stub.restore() end)

  it("delete handler with --cascade flag passes opts.cascade=true through", function()
    -- We stub the confirmation prompt to auto-confirm "Yes".
    local orig_select = vim.ui.select
    vim.ui.select = function(_choices, _opts, fn) fn("Yes") end

    cmds._subcommands["delete"]({ "feat-a", "--cascade" }, "feat-a --cascade")
    vim.ui.select = orig_select

    local args = find_capture(stub.captures, { "-y", "delete", "--cascade" })
    assert.is_not_nil(args)
    assert.is_true(vim.tbl_contains(args, "feat-a"))
  end)

  it("delete handler treats --cascade BEFORE the branch name correctly", function()
    -- The CLI accepts flags in any position; the handler must too. Without
    -- the explicit positional separation, `--cascade feat-a` would have
    -- been treated as the branch name in the old code.
    local orig_select = vim.ui.select
    vim.ui.select = function(_choices, _opts, fn) fn("Yes") end

    cmds._subcommands["delete"]({ "--cascade", "feat-a" }, "--cascade feat-a")
    vim.ui.select = orig_select

    -- The captured argv should have feat-a as the branch (after --cascade).
    local args = find_capture(stub.captures, { "-y", "delete", "--cascade" })
    assert.is_not_nil(args)
    assert.is_true(vim.tbl_contains(args, "feat-a"))
  end)
end)
