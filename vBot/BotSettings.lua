setDefaultTab("Main")

BotSettings = BotSettings or {}

local window = UI.createWindow("BotSettingsWindow", rootWidget)
window:hide()

BotSettings.window = window
BotSettings.sections = {
  cave = window.caveSection,
  basic = window.basicSection,
  pvp = window.pvpSection
}

local buttons = {
  cave = window.sectionTabs.cave,
  basic = window.sectionTabs.basic,
  pvp = window.sectionTabs.pvp
}

local activeSection = "cave"

window.caveSection.leftTitle:setText("Ajustes del CaveBot")
window.caveSection.rightTitle:setText("CaveBot y TargetBot")
window.basicSection.leftTitle:setText("Items y uso")
window.basicSection.rightTitle:setText("Cliente y utilidades")
window.pvpSection.leftTitle:setText("Runas y tiempos")
window.pvpSection.rightTitle:setText("Acciones PvP")

function BotSettings.showSection(name)
  if not BotSettings.sections[name] then return end

  activeSection = name
  for sectionName, section in pairs(BotSettings.sections) do
    local selected = sectionName == name
    section:setVisible(selected)
    buttons[sectionName]:setColor(selected and "#2de0d7" or "#dfdfdf")
  end
end

function BotSettings.getColumns(name)
  local section = BotSettings.sections[name]
  if not section then return nil, nil end
  return section.content.left, section.content.right
end

function BotSettings.open(name)
  BotSettings.showSection(name or activeSection)
  window:show()
  window:raise()
  window:focus()
end

for name, button in pairs(buttons) do
  button.onClick = function()
    BotSettings.showSection(name)
  end
end

window.closeButton.onClick = function()
  window:hide()
end

BotSettings.showSection(activeSection)

local openButton = UI.Button("Bot Settings", function()
  BotSettings.open()
end)
openButton:setColor("#ffffff")
openButton:setImageColor("#2de0d7")
openButton:setFont("verdana-11px-rounded")
