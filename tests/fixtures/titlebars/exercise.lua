-- Runs Familiar's generated configuration against the unmodified Core module.
local generated, core, style, scenario = table.unpack(arg)
local open = io.open
io.open = function(path, mode)
  if path == '/usr/lib/omarchy-hyprland-titlebars/titlebars.so' then return {close=function() end} end
  return open(path, mode)
end
o = { window = function() end }
local config, buttons, rules, loads = {}, {}, {}, {}
local function merge(to, from)
  for key, value in pairs(from) do
    if type(value) == 'table' then
      to[key] = to[key] or {}
      merge(to[key], value)
    else to[key] = value end
  end
end
local function add(button) buttons[#buttons + 1] = button end
hl = {
  plugin = { hyprbars = { add_button = add }, load = function(path) loads[#loads + 1] = path end },
  config = function(spec) merge(config, spec) end,
  get_config = function(path)
    local value = config
    for key in path:gmatch('[^.]+') do value = type(value) == 'table' and value[key] or nil end
    return value
  end,
  get_loaded_plugins = function()
    if scenario == 'conflict' then return {{name='hyprbars'}, {name='hyprbars'}} end
    return {{name='hyprbars'}}
  end,
  on = function() end,
  get_windows = function() return {} end,
  get_active_workspace = function() return nil end,
  window_rule = function(rule) rules[#rules + 1] = rule end,
  workspace_rule = function() end,
}
package.preload['default.hypr.helpers'] = function() return {} end
package.preload['default.hypr.paths'] = function() return {home='/nonexistent-familiar-test'} end
package.preload['default.hypr.workspace-modes'] = function() return dofile(core) end
local modes = require('default.hypr.workspace-modes')
local apply = modes.apply
if scenario == 'core-error' then modes.apply = function() apply(); error('core failure') end end
if scenario == 'changed-core' then modes.apply = function() apply(); hl.plugin.hyprbars.add_button({icon='new-core-button'}) end end
if scenario == 'late' then package.loaded['default.hypr.workspace-layouts'] = true end
if scenario == 'first-load' then hl.plugin.hyprbars = nil end
if scenario ~= 'tiled' then o.workspace_mode({default='floating'}) end
assert(loadfile(generated))()
local ok, err = pcall(modes.apply)
if scenario == 'first-load' then
  assert(ok and #loads == 1 and familiar_titlebars.state == 'ready')
  return
end
assert(hl.plugin.hyprbars.add_button == add, 'API must always be restored')
if scenario == 'core-error' then
  assert(not ok and tostring(err):find('core failure') and #buttons == 2)
  return
end
assert(ok, err)
if scenario == 'tiled' then
  assert(#loads == 0 and #buttons == 0 and familiar_titlebars.state == 'ready')
  return
end
assert(#loads == 1 and loads[1] == '/usr/lib/omarchy-hyprland-titlebars/titlebars.so')
assert(config.plugin.hyprbars.workspace_tag == 'omarchy-floating-workspace', 'scope must survive')
if scenario == 'old-source' then
  assert(familiar_titlebars == nil and #buttons == 2)
  assert(config.plugin.hyprbars.bar_height == 30)
  return
end
if scenario == 'changed-core' or scenario == 'late' or scenario == 'conflict' then
  assert(#buttons == (scenario == 'changed-core' and 3 or 2))
  assert(buttons[1].icon == '×' and buttons[2].icon == '□')
  assert(config.plugin.hyprbars.bar_height == 30, 'preserve Core appearance on mismatch')
  assert(familiar_titlebars.state == ({['changed-core']='unsupported-core',late='configuration-order',conflict='backend-conflict'})[scenario])
  return
end
assert(#buttons == 3, 'replace, never append to Core buttons')
assert(familiar_titlebars.state == 'active')
assert(config.plugin.hyprbars.bar_height == 44)
assert(config.plugin.hyprbars.bar_text_font == 'Test Font')
assert(config.plugin.hyprbars.bar_color == 'rgb(abcdef)')
assert(config.plugin.hyprbars['col.text'] == 'rgb(121212)')
assert(config.plugin.hyprbars.bar_buttons_alignment == (style == 'mac' and 'left' or 'right'))
assert(config.plugin.hyprbars.button_rounding == (style == 'mac' and -1 or 3))
assert(config.plugin.hyprbars.icon_on_hover == (style == 'mac'))
assert(#rules == 2, 'browser and explicit exclusions')
assert(buttons[1].action:find('action close --window', 1, true))
local minimize = style == 'mac' and 2 or 3
assert(buttons[minimize].icon == '−' and buttons[minimize].action:find('action minimize --window', 1, true))
for _, button in ipairs(buttons) do
  assert(button.size == 26)
  assert(button.action:find("--window '%WINDOW%'", 1, true))
  assert(not button.icon:find('familiar-', 1, true), 'stock renderer needs actual glyphs')
end
assert(config.plugin.hyprbars.on_double_click:find("--window '%WINDOW%'", 1, true))
-- A second accidental apply must not add another set or leave interception live.
assert(not pcall(modes.apply))
assert(#buttons == 3 and hl.plugin.hyprbars.add_button == add)
