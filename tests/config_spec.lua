describe("albus-conflictius.config", function()
  local config

  before_each(function()
    package.loaded["albus-conflictius.config"] = nil
    config = require("albus-conflictius.config")
  end)

  it("returns defaults when setup() is never called", function()
    local resolved = config.get()
    assert.is_true(resolved.banner)
    assert.is_true(resolved.auto_stage)
  end)

  it("returns defaults when setup({}) is called", function()
    local resolved = config.setup({})
    assert.is_true(resolved.banner)
    assert.is_true(resolved.auto_stage)
  end)

  it("applies overrides", function()
    local resolved = config.setup({ banner = false, auto_stage = false })
    assert.is_false(resolved.banner)
    assert.is_false(resolved.auto_stage)
  end)

  it("rejects a non-boolean banner value", function()
    assert.has_error(function()
      config.setup({ banner = "yes" })
    end)
  end)

  it("rejects a non-boolean auto_stage value", function()
    assert.has_error(function()
      config.setup({ auto_stage = 1 })
    end)
  end)

  it("get() reflects the most recent setup() call", function()
    config.setup({ banner = false })
    assert.is_false(config.get().banner)
  end)
end)
