local M = {}

M.defaults = {
  banner = true,
  auto_stage = true,
  celebrate = true,
}

local resolved = nil

local function validate_boolean_opt(name, value)
  if type(value) ~= "boolean" then
    error("albus-conflictius: '" .. name .. "' must be a boolean")
  end
end

function M.setup(opts)
  opts = opts or {}

  if opts.banner ~= nil then
    validate_boolean_opt("banner", opts.banner)
  end
  if opts.auto_stage ~= nil then
    validate_boolean_opt("auto_stage", opts.auto_stage)
  end
  if opts.celebrate ~= nil then
    validate_boolean_opt("celebrate", opts.celebrate)
  end

  resolved = {
    banner = opts.banner,
    auto_stage = opts.auto_stage,
    celebrate = opts.celebrate,
  }
  if resolved.banner == nil then
    resolved.banner = M.defaults.banner
  end
  if resolved.auto_stage == nil then
    resolved.auto_stage = M.defaults.auto_stage
  end
  if resolved.celebrate == nil then
    resolved.celebrate = M.defaults.celebrate
  end

  return resolved
end

function M.get()
  if not resolved then
    return M.setup({})
  end
  return resolved
end

return M
