-- TacticaLoot.lua - Boss loot mode helper for "vanilla"-compliant versions of Wow
-- Created by Doite

-------------------------------------------------
-- Small helpers & settings
-------------------------------------------------
-- Compatibility: provide gmatch/match if missing
do
  if not string.gmatch and string.gfind then
    string.gmatch = function(s, p) return string.gfind(s, p) end
  end
  if not string.match then
    string.match = function(s, p, init)
      local _, _, cap1 = string.find(s, p, init)
      return cap1
    end
  end
end

local function tlen(t)
  if table and table.getn then return table.getn(t) end
  local n=0; for _ in pairs(t) do n=n+1 end; return n
end

local function InRaid()
  return UnitInRaid and UnitInRaid("player")
end

local function IsRL()
  return (IsRaidLeader and IsRaidLeader() == 1) or false
end

local function EnsureLootDefaults()
  TacticaDB = TacticaDB or {}
  TacticaDB.Settings = TacticaDB.Settings or {}
  TacticaDB.Settings.Loot = TacticaDB.Settings.Loot or {}
  if TacticaDB.Settings.Loot.AutoMasterLoot == nil then
    TacticaDB.Settings.Loot.AutoMasterLoot = true
  end
  if TacticaDB.Settings.Loot.AutoGroupPopup == nil then
    TacticaDB.Settings.Loot.AutoGroupPopup = true
  end
  if TacticaDB.Settings.LootPromptDefault == nil then
    TacticaDB.Settings.LootPromptDefault = "group"
  end
  -- persisted "skip for this raid" record
  if TacticaDB.LootSkip == nil then
    TacticaDB.LootSkip = { active = false, leader = "" }
  end
end

-------------------------------------------------
-- Boss detection (worldboss OR name from DefaultData)
-------------------------------------------------
local BossNameSet
local function BuildBossNameSet()
  if BossNameSet then return end
  BossNameSet = {}
  if Tactica and Tactica.DefaultData then
    for raidName, bosses in pairs(Tactica.DefaultData) do
      for bossName in pairs(bosses) do
        BossNameSet[string.lower(bossName)] = true
      end
    end
  end
end

local function IsBossTarget()
  if not UnitExists("target") then return false end
  if UnitClassification and UnitClassification("target") == "worldboss" then
    return true
  end
  BuildBossNameSet()
  local n = UnitName("target")
  return n and BossNameSet and BossNameSet[string.lower(n)] or false
end

-------------------------------------------------
-- Raid leader / master looter helpers
-------------------------------------------------
local function GetRaidLeaderName()
  if not InRaid() then return nil end
  for i=1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if rank == 2 then return name end
  end
  return nil
end

local function GetMasterLooterName()
  local method, mlPartyID, mlRaidID = GetLootMethod()
  if method ~= "master" then return nil end
  if InRaid() and mlRaidID then
    local name = GetRaidRosterInfo(mlRaidID)
    return name
  elseif not InRaid() and mlPartyID then
    local unit = (mlPartyID == 0) and "player" or ("party"..mlPartyID)
    return UnitName(unit)
  end
  return nil
end

local function IsSelfMasterLooter()
  local my = UnitName("player")
  local ml = GetMasterLooterName()
  return (my and ml and my == ml) or false
end

-------------------------------------------------
-- Raid-scoped "don't ask again"
-------------------------------------------------
local function LootSkip_IsActiveForCurrentRaid()
  if not (TacticaDB and TacticaDB.LootSkip and TacticaDB.LootSkip.active) then return false end
  if not InRaid() then return false end
  local leader = GetRaidLeaderName()
  return (leader and TacticaDB.LootSkip.leader == leader) or false
end

local function LootSkip_ActivateForCurrentRaid()
  if not InRaid() then return end
  local leader = GetRaidLeaderName()
  if not leader then return end
  TacticaDB.LootSkip.active = true
  TacticaDB.LootSkip.leader = leader
end

local function LootSkip_Clear()
  if not TacticaDB then return end
  TacticaDB.LootSkip = { active = false, leader = "" }
end

-------------------------------------------------
-- Addon message plumbing (ML -> RL)
-------------------------------------------------
local LOOT_PREFIX = "TACTICA"
local MSG_LOOT_EMPTY = "LOOT_EMPTY"

local function SendLootEmpty()
  if not InRaid() then return end
  SendAddonMessage(LOOT_PREFIX, MSG_LOOT_EMPTY, "RAID")
end

-------------------------------------------------
-- Popup UI
-------------------------------------------------
local LootFrame, LootDropdown, DontAskCB
local SelectedMethod = "group"
local LOOT_METHODS = {
  { text = "Group Loot",        value = "group" },
  { text = "Round Robin",       value = "roundrobin" },
  { text = "Free-For-All",      value = "freeforall" },
  { text = "Need Before Greed", value = "needbeforegreed" },
  { text = "Master Looter",     value = "master" },
}

local function CreateLootPopup()
  if LootFrame then return end

  local f = CreateFrame("Frame", "TacticaLootPopup", UIParent)
  f:SetWidth(235); f:SetHeight(135)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({
    bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile= "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  f:SetFrameStrata("DIALOG")
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText("Switch Loot Method")

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOP", f, "TOP", 0, -30)
  label:SetText("Do you want to switch to:")

  local dd = CreateFrame("Frame", "TacticaLootDropdown", f, "UIDropDownMenuTemplate")
  dd:SetPoint("TOP", f, "TOP", 15, -45)
  dd:SetWidth(200)
  LootDropdown = dd

  UIDropDownMenu_Initialize(dd, function()
    for i=1, tlen(LOOT_METHODS) do
      local opt = LOOT_METHODS[i]
      local info = {
        text = opt.text,
        func = function()
          SelectedMethod = opt.value
          UIDropDownMenu_SetText(opt.text, dd)
        end
      }
      UIDropDownMenu_AddButton(info)
    end
  end)

  -- “Don’t ask again this raid”
  local cb = CreateFrame("CheckButton", "TacticaLootDontAskCB", f, "UICheckButtonTemplate")
  cb:SetWidth(24); cb:SetHeight(24)
  cb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 35, 40)
  local cbText = getglobal("TacticaLootDontAskCBText")
  if cbText then cbText:SetText("Don't ask again this raid") end
  DontAskCB = cb

  -- Yes - Change
  local yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  yes:SetWidth(100); yes:SetHeight(24)
  yes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  yes:SetText("Yes - Change")
  yes:SetScript("OnClick", function()
    if not (InRaid() and IsRL()) then
      local cf = DEFAULT_CHAT_FRAME or ChatFrame1
      cf:AddMessage("|cffff5555Tactica:|r Only the raid leader can change loot method.")
      f:Hide()
      return
    end
    local method = SelectedMethod or "group"
    if method == "master" then
      local me = UnitName("player")
      SetLootMethod("master", me)
    else
      SetLootMethod(method)
    end
    if DontAskCB and DontAskCB:GetChecked() then
      LootSkip_ActivateForCurrentRaid()
    end
    f:Hide()
  end)

  -- No - Keep (green like your “Post to Self”)
  local keep = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  keep:SetWidth(100); keep:SetHeight(24)
  keep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
  keep:SetText("No - Keep")
  local fs = keep:GetFontString()
  if fs and fs.SetTextColor then fs:SetTextColor(0.2, 1.0, 0.2) end
  keep:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  local nt = keep:GetNormalTexture(); if nt then nt:SetVertexColor(0.2, 0.8, 0.2) end
  keep:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
  local pt = keep:GetPushedTexture(); if pt then pt:SetVertexColor(0.2, 0.8, 0.2) end
  keep:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
  local ht = keep:GetHighlightTexture(); if ht then ht:SetBlendMode("ADD"); ht:SetVertexColor(0.2, 1.0, 0.2) end
  keep:SetScript("OnClick", function()
    if DontAskCB and DontAskCB:GetChecked() then
      LootSkip_ActivateForCurrentRaid()
    end
    f:Hide()
  end)

  LootFrame = f
end

-- Public: manual popup (/tt_loot)
function TacticaLoot_ShowPopup()
  EnsureLootDefaults()
  CreateLootPopup()
  local def = (TacticaDB and TacticaDB.Settings and TacticaDB.Settings.LootPromptDefault) or "group"
  SelectedMethod = def
  local shown = "Group Loot"
  for i=1, tlen(LOOT_METHODS) do
    if LOOT_METHODS[i].value == def then shown = LOOT_METHODS[i].text end
  end
  if LootDropdown then UIDropDownMenu_SetText(shown, LootDropdown) end
  LootFrame:Show()
end

-------------------------------------------------
-- Events & flow
-------------------------------------------------
local TL_SawLootWindow = false
local TL_AwaitingLoot  = false
local TL_SlotsRemaining = nil
local TL_WasInRaid = false
local TL_AlreadyOnMsgShown = false

-- Core entry when boss is targeted (from Tactica.lua)
function TacticaLoot_OnBossTargeted()
  EnsureLootDefaults()
  if not (InRaid() and IsRL()) then return end
  if not (TacticaDB.Settings and TacticaDB.Settings.Loot and TacticaDB.Settings.Loot.AutoMasterLoot) then return end
  if not IsBossTarget() then return end

  local method = GetLootMethod and GetLootMethod()
  if method ~= "master" then
    TL_AlreadyOnMsgShown = false
  end
  if method == "master" then
    if not TL_AlreadyOnMsgShown then
      local cf = DEFAULT_CHAT_FRAME or ChatFrame1
      cf:AddMessage("|cff33ff99Tactica:|r Masterloot is already on. Change settings with /tt.")
      TL_AlreadyOnMsgShown = true
    end
    return
  end
  local me = UnitName("player")
  SetLootMethod("master", me)
  TL_AlreadyOnMsgShown = false
  local cf = DEFAULT_CHAT_FRAME or ChatFrame1
  cf:AddMessage("|cff33ff99Tactica:|r Enabled Masterloot. Change settings with /tt.")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("LOOT_SLOT_CLEARED")
f:RegisterEvent("LOOT_CLOSED")
f:RegisterEvent("CHAT_MSG_ADDON")

f:SetScript("OnEvent", function()
  EnsureLootDefaults()

  if event == "PLAYER_ENTERING_WORLD" then
    TL_WasInRaid = InRaid() and true or false

  elseif event == "RAID_ROSTER_UPDATE" then
    local now = InRaid() and true or false
    if TL_WasInRaid and not now then
      -- Left raid: clear raid-scoped skip
      LootSkip_Clear()
      TL_SawLootWindow, TL_AwaitingLoot, TL_SlotsRemaining = false, false, nil
    elseif now then
      -- still in raid: if RL changed, clear skip
      local leader = GetRaidLeaderName()
      if TacticaDB.LootSkip.active and leader and leader ~= TacticaDB.LootSkip.leader then
        LootSkip_Clear()
      end
    end
    TL_WasInRaid = now

  elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    local dead = string.match(arg1 or "", "^(.+) dies%.$")
    if dead then
      BuildBossNameSet()
      if BossNameSet and BossNameSet[string.lower(dead)] then
        TL_AwaitingLoot   = true
        TL_SlotsRemaining = nil
        TL_SawLootWindow  = false
      end
    end

  elseif event == "LOOT_OPENED" then
    if not TL_AwaitingLoot then return end
    TL_SawLootWindow = true
    local n = GetNumLootItems and GetNumLootItems() or 0
    TL_SlotsRemaining = n

  elseif event == "LOOT_SLOT_CLEARED" then
    if TL_SlotsRemaining and TL_SlotsRemaining > 0 then
      TL_SlotsRemaining = TL_SlotsRemaining - 1
    end

  elseif event == "LOOT_CLOSED" then
    if not TL_AwaitingLoot then return end
    TL_AwaitingLoot = false

    -- If I'm the ML, notify raid when corpse empties so RL can react
    local method = GetLootMethod and GetLootMethod()
    if method == "master" and TL_SawLootWindow and (TL_SlotsRemaining or 0) == 0 then
      if IsSelfMasterLooter() then
        SendLootEmpty()
      end
    end

    -- RL popup path (local detection)
    if not InRaid() then return end
    if not (TacticaDB.Settings and TacticaDB.Settings.Loot and TacticaDB.Settings.Loot.AutoGroupPopup) then return end
    if LootSkip_IsActiveForCurrentRaid() then return end
    if not IsRL() then
      local cf = DEFAULT_CHAT_FRAME or ChatFrame1
      cf:AddMessage("|cffffcc00Tactica:|r Boss loot empty. Ask the raid leader to change loot method if desired.")
      return
    end
    if method ~= "master" then return end
    if not TL_SawLootWindow then return end
    if (TL_SlotsRemaining or 0) == 0 then
      TacticaLoot_ShowPopup()
    end

  elseif event == "CHAT_MSG_ADDON" then
    local prefix = arg1
    local msg    = arg2
    local chan   = arg3
    local sender = arg4
    if prefix ~= LOOT_PREFIX then return end
    if msg ~= MSG_LOOT_EMPTY then return end

    -- RL only; also ensure not suppressed for this raid
    if not (InRaid() and IsRL()) then return end
    if LootSkip_IsActiveForCurrentRaid() then return end
    if not (TacticaDB.Settings and TacticaDB.Settings.Loot and TacticaDB.Settings.Loot.AutoGroupPopup) then return end

    local method = GetLootMethod and GetLootMethod()
    if method ~= "master" then return end

    -- Only trust the current ML as sender
    local ml = GetMasterLooterName()
    if not (ml and sender and sender == ml) then return end

    TacticaLoot_ShowPopup()
  end
end)
