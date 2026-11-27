-- Combate > Follow: the window and the classic panel (switch + Setup) of Follow, its own
-- entry since change 212. Only controls: the engine and every option stay in
-- vBot/combo_plus.lua, which dofiles this file (so Helper files these controls under
-- "follow_panel", not under Combo) and wires them right after.
HelperFollowPanel = {}
local P = HelperFollowPanel

-- FollowWindow reuses the ids of ComboPlusWindow: the same skin descriptor paints it.
pcall(function()
  local styles = HelperAppearance and HelperAppearance.metadata and HelperAppearance.metadata.styles
  if type(styles) == "table" and styles.FollowWindow == nil and type(styles.ComboPlusWindow) == "table" then
    styles.FollowWindow = styles.ComboPlusWindow
  end
end)

P.window = UI.createWindow("FollowWindow", g_ui.getRootWidget())
P.window:hide()
P.body = P.window.comboPage.body

-- Same text as the Combo Leader panel in combo_plus.lua (the skin finds inline panels by
-- their exact text); only the title changes afterwards.
P.ui = setupUI([[
Panel
  height: 19

  HelperThemePower
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Combo Leader')

  HelperThemeButton
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
P.ui.title:setText('Follow')

return P
