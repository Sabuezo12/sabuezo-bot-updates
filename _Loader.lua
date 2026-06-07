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

-- Files are grouped by the tab where their visible panel belongs.
-- Keep the relative order inside each group; that order defines the visual order in the bot.
local loaderSections = {
  {
    name = "Core",
    files = {
      ----"vbot/Inmortal",
      "vBot/items",
      "vBot/vlib",
      "vBot/ItemCounter",
      ----"vBot/exivalast", -- replaced by pvp_support + iconos
      "vBot/new_cavebot_lib",
      "vBot/configs", -- do not change this and above
    }
  },
  {
    name = "Main",
    files = {
      "vBot/main",
      "vBot/Updater",
      "vBot/extras",
      "vBot/extrasPvp",
      ----"vBot/BotServer", -- disabled from loader
      "vBot/combo_plus",
      ----"vBot/combo", -- replaced by combo_plus
      "vBot/TimerExecutor",
      ----"vBot/zzzz_ComboAttack", -- replaced by combo_plus
      "vBot/pushmax",
      ----"vBot/magicbag", -- disabled: automatic magic bag selling
      "vBot/BugMapMouse",
      "vBot/keepwall",
      "vBot/ingame_editor",
    }
  },
  {
    name = "Tools",
    files = {
      "vBot/playerlist",
      "vBot/buffguild",
      "vBot/alarms",
      "vBot/recoge",
      "vBot/pullitems",
      "vBot/antipush1",
      "vBot/FireBomb",
      "vBot/Ering",
      ----"vBot/Dropper",
      "zFreeScripts/z_Auto-Party",
      "vBot/ContainerManager",
      ----"vBot/quiver_manager",
      ----"vBot/quiver_label",
      "vBot/tools",
      "vBot/spy_level",
      "vBot/pvp_support",
      "vBot/dash",
    }
  },
  {
    name = "Cave",
    files = {
      "vBot/cave_target_settings",
      "vBot/cavebot",
      "vBot/exeta",
      "vBot/supplies",
      "vBot/depositer_config",
      "vBot/npc_talk",
      "vBot/cavebot_control_panel",
    }
  },
  {
    name = "Target",
    files = {
      "vBot/AttackBot",
    }
  },
  {
    name = "HP",
    files = {
      ----"vBot/superhealth",
      "vBot/Conditions",
      "vBot/Equipper",
      "vBot/friend_healer",
      ----"vBot/extrahealth",
      "zFreeScripts/zAutoBuff",
      "vBot/HealBot",
      -- "vBot/Heal-Old",
      ----"vBot/sio",
      ----"vBot/POT",
      "vBot/equip",
      "vBot/eat_food",
      "vBot/ManaTrainer",
    }
  },
  {
    name = "Final",
    files = {
      "vBot/analyzer",
      ----"vBot/xeno_menu", -- disabled: unused contextual menu
      "vBot/iconos",
      "zFreeScripts/CaveBotHUD",
    }
  }
}

for _, section in ipairs(loaderSections) do
  for _, file in ipairs(section.files) do
    loadScript(file)
  end
end

setDefaultTab("Main")
local label = UI.Label("Pruebas PbotWars:")
label:setColor('#9dd1ce')
label:setFont('verdana-11px-rounded')
UI.Separator()
