-- Familiar's compatibility adapter for Core #14482 / titlebars v0.2.1.
-- Not a Core extension API: fail back to Core if its button contract changes.
-- This runs from looknfeel, before default.hypr.toggles applies workspace modes.
local status = { state = "waiting" }
_G.familiar_titlebars = status
if package.loaded["default.hypr.workspace-layouts"] then
  status.state = "configuration-order"
  return
end
local ok, modes = pcall(require, "default.hypr.workspace-modes")
if not ok or type(modes) ~= "table" or type(modes.apply) ~= "function" then
  status.state = "core-required"
  return
end
local apply = modes.apply
local applied = false
modes.apply = function(...)
  if applied then error("Familiar: workspace modes applied twice; reload configuration") end
  applied = true
  local api = hl.plugin.hyprbars
  -- Plugin loads are deferred until the config has finished. Core requests the
  -- load, and the plugin's next reload supplies its Lua API. Never load it here.
  if not api or type(api.add_button) ~= "function" then
    status.state = "ready"
    return apply(...)
  end
  local count = 0
  for _, plugin in ipairs(hl.get_loaded_plugins()) do
    if plugin.name == "hyprbars" then count = count + 1 end
  end
  if count ~= 1 then
    status.state = "backend-conflict"
    return apply(...)
  end
  local add = api.add_button
  local buttons = {}
  -- Capture only Core's synchronous apply call. Other callers retain the real
  -- API, including when Core raises an error. No lasting global interception.
  api.add_button = function(button) buttons[#buttons + 1] = button end
  local result = table.pack(pcall(apply, ...))
  api.add_button = add
  local function restore_buttons()
    for _, button in ipairs(buttons) do add(button) end
  end
  if not result[1] then
    restore_buttons()
    error(result[2])
  end
  if #buttons == 0 then
    status.state = "ready" -- no floating workspaces; preserve Core's load policy
    return table.unpack(result, 2, result.n)
  end
  local window = [[window = "address:%WINDOW%"]]
  if #buttons ~= 2
      or buttons[1].icon ~= "×"
      or buttons[1].action ~= "hyprctl dispatch 'hl.dsp.window.close({ " .. window .. " })'"
      or buttons[2].icon ~= "□"
      or buttons[2].action ~= "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\", " .. window .. " })'"
      or hl.get_config("plugin.hyprbars.workspace_tag") ~= "omarchy-floating-workspace" then
    restore_buttons()
    status.state = "unsupported-core"
    return table.unpack(result, 2, result.n)
  end
  -- Core still owns floating, tags, shadows, opacity and loading. Familiar
  -- supplies appearance/actions only, with the captured defaults replaced once.
  familiar_configure()
  status.state = "active"
  return table.unpack(result, 2, result.n)
end
