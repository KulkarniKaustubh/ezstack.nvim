-- Test helpers shared across ezstack.nvim specs.
--
-- Every spec starts from a clean module state so config changes and
-- dispatch-table edits don't leak between tests.

local M = {}

--- Reload the plugin modules and return the main table. Call this in
--- `before_each` so each test sees a pristine `ezstack.config`.
---@return table
function M.reload()
  package.loaded["ezstack"] = nil
  package.loaded["ezstack.cli"] = nil
  package.loaded["ezstack.commands"] = nil
  package.loaded["ezstack.ui"] = nil
  package.loaded["ezstack.fugitive"] = nil
  package.loaded["ezstack.telescope"] = nil
  return require("ezstack")
end

--- Build a fake stack entry suitable for feeding into `ezstack.statusline`
--- or `ui._render_graph_lines`.
---@param opts table
---@return table
function M.fake_stack(opts)
  return vim.tbl_deep_extend("force", {
    name = "my-feat",
    hash = "a1b2c3d4e5f6",
    root = "main",
    branches = {},
  }, opts or {})
end

--- Stub `cli.list_stacks_sync` to return the given stacks for the duration
--- of one test. Returns a restore function.
---@param stacks table[]
---@return fun()
function M.stub_list_stacks_sync(stacks)
  local cli = require("ezstack.cli")
  local orig = cli.list_stacks_sync
  cli.list_stacks_sync = function() return stacks end
  return function() cli.list_stacks_sync = orig end
end

--- Stub `vim.system` to capture every command without running anything.
--- Each capture entry is `{ cmd = string[], opts = table }`. The stub
--- pretends every command exited 0 with empty stdout/stderr, and runs the
--- caller's completion callback synchronously (skipping vim.schedule) so
--- tests don't need to spin the event loop.
---
--- Returns `{ captures = {...}, restore = fun() }`. Call `restore()` in
--- after_each to put the real `vim.system` back.
---@return { captures: table[], restore: fun() }
function M.stub_vim_system()
  local captures = {}
  local orig_system = vim.system
  local orig_schedule = vim.schedule

  vim.system = function(cmd, opts, on_exit)
    table.insert(captures, { cmd = vim.deepcopy(cmd), opts = opts })
    if on_exit then
      on_exit({ code = 0, stdout = "", stderr = "" })
    end
    -- Return a stub handle so any caller that does `:wait()` still works.
    return setmetatable({}, {
      __index = {
        wait = function() return { code = 0, stdout = "", stderr = "" } end,
        kill = function() end,
      },
    })
  end

  -- run_async wraps the callback in vim.schedule. In a non-headless test
  -- the loop runs and the schedule fires; under PlenaryBustedDirectory it
  -- normally does too, but we run schedules inline so individual tests
  -- can assert synchronously without yielding.
  vim.schedule = function(fn) fn() end

  return {
    captures = captures,
    restore = function()
      vim.system = orig_system
      vim.schedule = orig_schedule
    end,
  }
end

return M
