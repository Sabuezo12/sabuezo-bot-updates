-- load all otui files, order doesn't matter
local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text

local configFiles = g_resources.listDirectoryFiles("/bot/" .. configName .. "/vBot", true, false)
for i, file in ipairs(configFiles) do
  local ext = file:split(".")
  if ext[#ext]:lower() == "ui" or ext[#ext]:lower() == "otui" then
    g_ui.importStyle(file)
  end
end

local function loadScript(name)
  return dofile("/" .. name .. ".lua")
end

-- Load order grouped by purpose. This test folder keeps shared scripts and
-- server-specific behavior, but follows the cleaner Torment Sabuezo layout.
local luaFiles = {
  -- Core libraries/config
  "vBot/main",
  ----"vbot/Inmortal",
  "vBot/items",
  "vBot/vlib",
  "vBot/ItemCounter",
  ----"vBot/exivalast", -- replaced by pvp_support + iconos in Pruebas
  "vBot/new_cavebot_lib",
  "vBot/configs", -- do not change this and above
  "vBot/Updater",

  -- Base panels and shared helpers
  "vBot/extras",
  "vBot/extrasPvp",
  "vBot/cave_target_settings",

  -- Main systems
  "vBot/cavebot",
  "vBot/playerlist",
  ---"vBot/buffguild",
  "vBot/alarms",
  "vBot/AttackBot", -- last of major modules in this vBot branch
  "vBot/BotServer",

  -- PvP / combat / support
  "vBot/combo_plus",
  ----"vBot/combo", -- replaced by combo_plus
  ----"vBot/superhealth",
  "vBot/Conditions",
  "vBot/Equipper",
  "vBot/friend_healer",
  ----"vBot/extrahealth",
  "zFreeScripts/zAutoBuff",
  "vBot/TimerExecutor",
  "vBot/HealBot",
  ----"vBot/zzzz_ComboAttack", -- replaced by combo_plus
  "vBot/pushmax",
  ----"vBot/sio",
  ----"vBot/POT",
  "vBot/recoge",
  "vBot/pullitems",
  -- "vBot/Heal-Old",
  "vBot/antipush1",
  "vBot/FireBomb",
  "vBot/Ering",
  ----"vBot/Dropper",

  -- Party / containers / inventory
  "zFreeScripts/z_Auto-Party",
  "vBot/ContainerManager",
  ----"vBot/quiver_manager",
  ----"vBot/quiver_label",
  "vBot/tools",
  "vBot/magicbag",
  -----"vBot/antiRs",
  -----"vBot/depot_withdraw",
  "vBot/equip",
  "vBot/eat_food",
  "vBot/ManaTrainer",
  "vBot/exeta",

  -- Analyzer / info / cave helpers
  "vBot/analyzer",
  "vBot/spy_level",
  "vBot/supplies",
  "vBot/depositer_config",
  "vBot/npc_talk",
  "vBot/xeno_menu",
  "vBot/BugMapMouse",
  "vBot/pvp_support",
  "vBot/keepwall",
  "vBot/dash",
  "vBot/iconos",
  "vBot/cavebot_control_panel",
  "zFreeScripts/SkillsHUD",
  "vBot/ingame_editor",
}

for i, file in ipairs(luaFiles) do
  loadScript(file)
end

setDefaultTab("Main")
local label = UI.Label("Pruebas PbotWars:")
label:setColor('#9dd1ce')
label:setFont('verdana-11px-rounded')
UI.Separator()
