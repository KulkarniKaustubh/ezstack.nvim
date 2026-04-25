-- Tests for `require("ezstack").setup()` side effects.

local H = require("tests.helpers")

describe("ezstack.setup", function()
  local ezstack

  before_each(function()
    ezstack = H.reload()
  end)

  it("runs without errors with no options", function()
    assert.has_no.errors(function()
      ezstack.setup({ welcome = false })
    end)
    assert.is_true(ezstack._setup_done())
  end)

  it("exposes defaults for new config keys", function()
    -- Read config *before* calling setup() so we see the shipped defaults.
    assert.equals("stack", ezstack.config.statusline_format)
    assert.equals(false, ezstack.config.default_keymaps)
    assert.equals(true, ezstack.config.welcome)
  end)

  it("registers :EzsActions user command", function()
    ezstack.setup({ welcome = false })
    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds.EzsActions)
  end)

  it("fires User EzstackSetup autocmd", function()
    local fired = false
    vim.api.nvim_create_autocmd("User", {
      pattern = "EzstackSetup",
      once = true,
      callback = function() fired = true end,
    })
    ezstack.setup({ welcome = false })
    assert.is_true(fired)
  end)

  -- Regression test: vim.system() throws synchronously with ENOENT when the
  -- target binary isn't on PATH (Neovim 0.10+ behavior). setup() calls
  -- cli.is_available() during initialization to warn the user when ezs is
  -- missing — that warn path must not itself crash the plugin. Without the
  -- pcall guard in cli.run_async, the spawn error propagates out of setup()
  -- and breaks the plugin (and the headless test suite) on any machine
  -- without `ezs` installed.
  it("does not crash when the ezs binary is missing", function()
    local cli = require("ezstack.cli")
    local orig_system = vim.system
    -- Simulate ENOENT: pretend the binary isn't on PATH. vim.system in
    -- Neovim 0.10+ throws this synchronously when libuv can't spawn.
    vim.system = function(_cmd, _opts, _on_exit)
      error("vim/_core/system.lua:0: ENOENT: no such file or directory (cmd): 'ezs'")
    end

    local setup_ok, setup_err = pcall(function()
      ezstack.setup({ welcome = false })
    end)

    -- is_available's callback contract must still hold under spawn failure:
    -- fire with `false` rather than throwing. Test it directly while the
    -- stub is still installed so we exercise the same crash path setup() hit.
    local got_callback = false
    local got_value
    cli.is_available(function(available)
      got_callback = true
      got_value = available
    end)
    -- run_async defers the failure callback via vim.schedule; pump the
    -- event loop briefly so the deferred fire actually runs.
    vim.wait(50, function() return got_callback end)

    -- Restore before final assertions so a failure here can't poison
    -- subsequent specs even if asserts blow up.
    vim.system = orig_system

    assert.is_true(setup_ok, "setup() must not propagate vim.system errors: " .. tostring(setup_err))
    assert.is_true(got_callback, "is_available callback must fire even on spawn failure")
    assert.is_false(got_value, "is_available should report false when spawn fails")
  end)

  describe("default_keymaps", function()
    before_each(function()
      pcall(vim.keymap.del, "n", "]s")
      pcall(vim.keymap.del, "n", "[s")
    end)

    it("is disabled by default", function()
      ezstack.setup({ welcome = false })
      -- `maparg("]s", "n")` returns "" when the key is unmapped (or bound
      -- to a built-in, which has no RHS). The important thing is that we
      -- did not set any Lua mapping.
      local m = vim.fn.maparg("]s", "n", false, true)
      -- Unmapped OR built-in — either way, rhs should not reference Ezs.
      if type(m) == "table" and m.rhs then
        assert.is_nil(m.rhs:find("Ezs"))
      end
    end)

    it("installs ]s and [s when enabled", function()
      ezstack.setup({ welcome = false, default_keymaps = true })
      local down = vim.fn.maparg("]s", "n", false, true)
      local up = vim.fn.maparg("[s", "n", false, true)
      assert.equals("table", type(down))
      assert.equals("table", type(up))
      assert.truthy(down.rhs:find("Ezs down"))
      assert.truthy(up.rhs:find("Ezs up"))
    end)

    it("does not clobber an existing user mapping", function()
      vim.keymap.set("n", "]s", "<cmd>echo 'user'<cr>", { desc = "user" })
      ezstack.setup({ welcome = false, default_keymaps = true })
      local m = vim.fn.maparg("]s", "n", false, true)
      assert.truthy(m.rhs:find("user"))
    end)
  end)

  describe("_first_run_welcome", function()
    it("is idempotent across multiple setup() calls", function()
      -- Redirect state to a temp dir so we don't touch the real one.
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      vim.env.XDG_STATE_HOME = tmp

      ezstack = H.reload()
      local calls = 0
      local orig_notify = vim.notify
      vim.notify = function(msg, ...)
        if type(msg) == "string" and msg:find("Welcome to ezstack") then
          calls = calls + 1
        end
      end

      ezstack.setup({}) -- welcome enabled
      vim.wait(50) -- let vim.schedule drain
      ezstack = H.reload()
      ezstack.setup({}) -- second setup: should NOT re-notify
      vim.wait(50)

      vim.notify = orig_notify
      assert.equals(1, calls, "welcome notification must fire exactly once")
    end)

    it("never writes to ~/.ezstack (that directory belongs to the CLI)", function()
      -- Guard against a regression where the plugin touches the CLI's
      -- config dir. We check that the marker path does not start with
      -- `$HOME/.ezstack/`.
      ezstack = H.reload()
      ezstack.setup({ welcome = false })
      local marker = ezstack._welcome_marker_path()
      assert.is_string(marker)
      local home = vim.env.HOME or ""
      if home ~= "" then
        assert.is_nil(
          marker:find("^" .. vim.pesc(home) .. "/%.ezstack/"),
          "welcome marker must not live under ~/.ezstack"
        )
      end
    end)
  end)
end)
