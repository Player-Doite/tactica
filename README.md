-- TacticaRaidRoles.lua - Boss raid setup helper for "vanilla"-compliant versions of Wow
-- Created by Doite

------------------------------------------------------------
-- SavedVariables guard
------------------------------------------------------------
local function EnsureDB()
  if not TacticaDB then
    TacticaDB = {
      version = 3,
      CustomTactics = {},
      Settings = {},
      Healers = {},
      DPS = {},
      Tanks = {},
      wasInRaid = false,
    }
  end
  if not TacticaDB.Healers then TacticaDB.Healers = {} end
  if not TacticaDB.DPS    then TacticaDB.DPS    = {} end
  if not TacticaDB.Tanks  then TacticaDB.Tanks  = {} end
  if TacticaDB.MasterLooter == nil then TacticaDB.MasterLooter = "" end
  if TacticaDB.wasInRaid == nil then TacticaDB.wasInRaid = false end
  if TacticaDB.RaidSignature ~= nil then TacticaDB.RaidSignature = nil end
end

-- Tell Raid Builder to refresh (safe if RB not loaded)
local function NotifyBuilder()
  if TacticaRaidBuilder and TacticaRaidBuilder.NotifyRoleAssignmentChanged then
    TacticaRaidBuilder.NotifyRoleAssignmentChanged()
  elseif TacticaRaidBuilder and TacticaRaidBuilder.RefreshPreview then
    -- fallback for older RB builds
    TacticaRaidBuilder.RefreshPreview()
  end
end

------------------------------------------------------------
-- pfUI + SuperWoW detection
------------------------------------------------------------
local Tactica_hasPfUI = false
local Tactica_hasSuperWoW = false
local Tactica_SuperWoWVersion = nil

local function Tactica_DetectPfUI()
  Tactica_hasPfUI = false
  if type(IsAddOnLoaded) == "function" then
    local ok = IsAddOnLoaded("pfUI")
    if ok == 1 or ok == true then Tactica_hasPfUI = true end
  end
  return Tactica_hasPfUI
end

-- SuperWoW detection
local function Tactica_DetectSuperWoW()
  Tactica_hasSuperWoW = false
  Tactica_SuperWoWVersion = nil
  if type(SUPERWOW_VERSION) == "string" and SUPERWOW_VERSION ~= "" then
    Tactica_hasSuperWoW = true
    Tactica_SuperWoWVersion = SUPERWOW_VERSION
  elseif type(SpellInfo) == "function" or type(SetAutoloot) == "function" or (type(superwow_active) ~= "nil") then
    Tactica_hasSuperWoW = true
    Tactica_SuperWoWVersion = "legacy/unknown"
  end
  return Tactica_hasSuperWoW, Tactica_SuperWoWVersion
end

-- Simple status slash: prints both pfUI + SuperWoW states
SLASH_TACTICAPFUI1 = "/tactica_pfui"
SlashCmdList["TACTICAPFUI"] = function()
  -- re-detect on demand (in case user toggled addons)
  Tactica_DetectPfUI()
  Tactica_DetectSuperWoW()
  local f = (DEFAULT_CHAT_FRAME or ChatFrame1)
  local pf = Tactica_hasPfUI and "|cff33ff99LOADED|r" or "|cffff5555NOT loaded|r"
  local sw = Tactica_hasSuperWoW and ("|cff33ff99present|r"..(Tactica_SuperWoWVersion and (" (v"..Tactica_SuperWoWVersion..")") or "")) or "|cffff5555not detected|r"
  f:AddMessage("|cff33ff99Tactica:|r pfUI: "..pf..",  SuperWoW: "..sw)
end

-- Debug: list/query pfUI tank flags
SLASH_TACTICAPFUITANKS1 = "/tactica_pfuitanks"
SlashCmdList["TACTICAPFUITANKS"] = function(msg)
  local f = DEFAULT_CHAT_FRAME or ChatFrame1
  local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
  if not (pfUI and pfUI.uf and pfUI.uf.raid) then
    f:AddMessage("|cff33ff99Tactica:|r pfUI not loaded or raid frames missing.")
    return
  end
  pfUI.uf.raid.tankrole = pfUI.uf.raid.tankrole or {}
  local t = pfUI.uf.raid.tankrole
  local who = trim(msg)
  if who ~= "" then
    f:AddMessage("|cff33ff99Tactica:|r pfUI "..who.." tank? "..tostring(t[who] and true or false)
      .."  |  TacticaDB "..who.." tank? "..tostring(TacticaDB and TacticaDB.Tanks and TacticaDB.Tanks[who] and true or false))
    return
  end
  local c = 0
  for n in pairs(t) do c = c + 1; f:AddMessage("pfUI tank: "..n) end
  if c == 0 then f:AddMessage("|cff33ff99Tactica:|r pfUI: none") end
end

-- Find pfUI's external Tank menu key by button text
local External_Tank_Key = nil
local function DetectExternalTankMenuKey()
  External_Tank_Key = nil
  if not UnitPopupButtons then return end
  for k, info in pairs(UnitPopupButtons) do
    if type(k) == "string" and info and info.text == "Toggle as Tank" and k ~= "TACTICA_TOGGLE_TANK" then
      External_Tank_Key = k; break
    end
  end
end

------------------------------------------------------------
-- pfUI bridge (drive pfUI.uf.raid.tankrole)
------------------------------------------------------------
local function Pfui_IsReady()
  return Tactica_hasPfUI and pfUI and pfUI.uf and pfUI.uf.raid
end

local function Pfui_GetTankTable()
  if not Pfui_IsReady() then return nil end
  pfUI.uf.raid.tankrole = pfUI.uf.raid.tankrole or {}
  return pfUI.uf.raid.tankrole
end

local function Pfui_RefreshRaid()
  if pfUI and pfUI.uf and pfUI.uf.raid and pfUI.uf.raid.Show then
    pfUI.uf.raid:Show()
  end
end

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local function lower(s) return string.lower(s or "") end

-- remove all keys that equal name (trimmed, case-insensitive)
local function Pfui_RemoveAllKeysFor(name)
  local t = Pfui_GetTankTable(); if not t then return end
  local tgt = lower(trim(name or ""))
  for k in pairs(t) do
    if lower(trim(k)) == tgt then t[k] = nil end
  end
end

-- Set/remove a single name in pfUI's tankrole table (with duplicate cleanup)
local function Pfui_SetTank(name, enabled)
  if not name or name == "" then return end
  local t = Pfui_GetTankTable(); if not t then return end
  Pfui_RemoveAllKeysFor(name)
  if enabled then t[name] = true end
  Pfui_RefreshRaid()
end

-- Reapply entire Tank list into pfUI
local function Pfui_ReapplyAllTanks()
  local t = Pfui_GetTankTable(); if not t then return end
  for k in pairs(t) do t[k] = nil end
  for name, v in pairs(TacticaDB.Tanks) do if v then t[name] = true end end
  Pfui_RefreshRaid()
end

------------------------------------------------------------
-- Menu keys & layout offsets
------------------------------------------------------------
local BUTTON_KEY_HEALER = "TACTICA_TOGGLE_HEALER"
local BUTTON_KEY_DPS    = "TACTICA_TOGGLE_DPS"
local BUTTON_KEY_TANK   = "TACTICA_TOGGLE_TANK" -- Tactica own Tank option (conditionally added)
local BUTTON_KEY_ML     = "TACTICA_PRESET_ML"
local IsSelfRaidLeader
local ML_TAG_OFFSET_AFTER_CLASS = -10

-- Tag sits just left of the name
local OFFSET_BEFORE_NAME_DEFAULT = 2
local OFFSET_BEFORE_NAME_PFUI    = 1
local OFFSET_BEFORE_NAME_ACTIVE  = 1

------------------------------------------------------------
-- Raid role helpers (exclusive)
------------------------------------------------------------
local function ClearAllRolesFor(name)
  if not name or name == "" then return end
  TacticaDB.Healers[name] = nil
  TacticaDB.DPS[name] = nil
  TacticaDB.Tanks[name] = nil
end

local function GetCurrentRole(name)
  if not name or name == "" then return nil end
  if TacticaDB.Tanks[name]  then return "T" end
  if TacticaDB.Healers[name] then return "H" end
  if TacticaDB.DPS[name]    then return "D" end
  return nil
end

local function SetMasterLooterPreset(nameOrEmpty)
  TacticaDB.MasterLooter = nameOrEmpty or ""
end

local function CurrentRaidLeaderName()
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  for i=1,n do
    local nm, rank = GetRaidRosterInfo(i)
    if rank == 2 then return nm end
  end
  return UnitName and UnitName("player") or nil
end

local function ApplyPresetMasterLooterNow(nameOrEmpty)
  if not (UnitInRaid("player") and IsSelfRaidLeader()) then return end
  local method = GetLootMethod and GetLootMethod() or nil
  if method ~= "master" then return end
  local target = nameOrEmpty
  if not target or target == "" then target = CurrentRaidLeaderName() end
  if target and target ~= "" then
    SetLootMethod("master", target)
  end
end

function TacticaRaidRoles_GetPresetMasterLooter()
  EnsureDB()
  return TacticaDB.MasterLooter or ""
end

function TacticaRaidRoles_SetPresetMasterLooter(nameOrEmpty)
  EnsureDB()
  if not UnitInRaid("player") then return false, "not in raid" end
  if not IsSelfRaidLeader() then return false, "only raid leader can set preset ML" end

  local name = nameOrEmpty or ""
  if name ~= "" then
    local found = false
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i=1,n do
      local r = GetRaidRosterInfo(i)
      if r == name then found = true; break end
    end
    if not found then return false, "player not found in raid" end
  end

  SetMasterLooterPreset(name)
  if UnitInRaid("player") and IsSelfRaidLeader() then
    SendAddonMessage("TACTICA", "M::" .. name, "RAID")
  end
  ApplyPresetMasterLooterNow(name)
  if name ~= "" then
    local me = UnitName and UnitName("player") or ""
    local whisperOn = (TacticaDB and TacticaDB.Settings and TacticaDB.Settings.RoleWhisperEnabled ~= false)
    if whisperOn and me ~= "" and name ~= me and UnitInRaid("player") and IsSelfRaidLeader() then
      SendChatMessage("[Tactica]: You have been selected as preset masterlooter. If masterloot is turned on, you will automatically receive the role.", "WHISPER", nil, name)
    end
  end
  if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
  if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
  NotifyBuilder()
  return true
end

local function FindUnitByName(name)
  if not name or name == "" then return nil end

  local me = UnitName and UnitName("player")
  if me == name then return "player" end

  local rn = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  if rn > 0 then
    for i=1,rn do
      local u = "raid"..i
      if UnitExists and UnitExists(u) then
        local nm = UnitName(u)
        if nm == name then return u end
      end
    end
  end

  local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  if pn > 0 then
    for i=1,pn do
      local u = "party"..i
      if UnitExists and UnitExists(u) then
        local nm = UnitName(u)
        if nm == name then return u end
      end
    end
  end

  return nil
end

local function IsUnitOnlineByName(name)
  local u = FindUnitByName(name)
  if not u then return false end
  if UnitIsConnected then return UnitIsConnected(u) and true or false end
  return true -- fallback
end

-- suppress pfUI writes when click originated from pfUI's own Tank option
local suppressPfuiWrite = false

-- Set exclusive; clicking the same role again clears it.
local function SetExclusiveRole(name, role)
  if not name or name == "" then return nil, nil end
  local current = GetCurrentRole(name)
  if current == role then
    ClearAllRolesFor(name)
    if role == "T" and not suppressPfuiWrite then Pfui_SetTank(name, false) end
	NotifyBuilder()
    return nil, (role == "H" and "not marked as Healer")
             or (role == "D" and "not marked as DPS")
             or (role == "T" and "not marked as Tank")
  else
    ClearAllRolesFor(name)
    if role == "H" then
      TacticaDB.Healers[name] = true
      if not suppressPfuiWrite then Pfui_SetTank(name, false) end
    elseif role == "D" then
      TacticaDB.DPS[name] = true
      if not suppressPfuiWrite then Pfui_SetTank(name, false) end
    elseif role == "T" then
      TacticaDB.Tanks[name] = true
      if not suppressPfuiWrite then Pfui_SetTank(name, true) end
    else
      return nil, nil
    end
	NotifyBuilder()
    return role, (role == "H" and "marked as Healer")
               or (role == "D" and "marked as DPS")
               or (role == "T" and "marked as Tank")
  end
end

-- Apply exactly as sent from network (idempotent; no toggle)
local function ApplyRoleFromNetwork(name, role)
  if not name or name == "" then return end
  ClearAllRolesFor(name)
  if role == "H" then
    TacticaDB.Healers[name] = true; Pfui_SetTank(name, false)
  elseif role == "D" then
    TacticaDB.DPS[name] = true;    Pfui_SetTank(name, false)
  elseif role == "T" then
    TacticaDB.Tanks[name] = true;  Pfui_SetTank(name, true)
  else
    Pfui_SetTank(name, false)
  end
  NotifyBuilder()
end

------------------------------------------------------------
-- Raid officer checks
------------------------------------------------------------
local function IsLeaderOrAssistByName(name)
  if not name or name == "" then return false end
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  for i = 1, n do
    local rname, rank = GetRaidRosterInfo(i)
    if rname and rname == name then
      return (rank and rank >= 1) and true or false
    end
  end
  return false
end

local function IsRaidLeaderByName(name)
  if not name or name == "" then return false end
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  for i = 1, n do
    local rname, rank = GetRaidRosterInfo(i)
    if rname and rname == name then
      return rank == 2
    end
  end
  return false
end

local function IsSelfLeaderOrAssist()
  if not UnitInRaid("player") then return false end
  local me = UnitName and UnitName("player") or nil
  return IsLeaderOrAssistByName(me)
end

IsSelfRaidLeader = function()
  return (IsRaidLeader and IsRaidLeader() == 1) or false
end

------------------------------------------------------------
-- Addon comms
------------------------------------------------------------
local ADDON_PREFIX = "TACTICA"
-- S:<role>:<name> | C::<name> | X::CLEARALL | Q::HELLO

local function Split3(msg)
  local a, b, c = nil, nil, nil
  if not msg then return a, b, c end
  local p1 = string.find(msg, ":", 1, true)
  if not p1 then a = msg; return a, b, c end
  a = string.sub(msg, 1, p1 - 1)
  local rest = string.sub(msg, p1 + 1)
  local q1 = string.find(rest, ":", 1, true)
  if not q1 then b = rest; return a, b, c end
  b = string.sub(rest, 1, q1 - 1)
  c = string.sub(rest, q1 + 1)
  return a, b, c
end

local function Broadcast_Set(name, role)
  if not name or name == "" or not role or role == "" then return end
  if not UnitInRaid("player") then return end
  if not IsSelfLeaderOrAssist() then return end
  SendAddonMessage(ADDON_PREFIX, "S:" .. role .. ":" .. name, "RAID")
end

local function Broadcast_Clear(name)
  if not name or name == "" then return end
  if not UnitInRaid("player") then return end
  if not IsSelfLeaderOrAssist() then return end
  SendAddonMessage(ADDON_PREFIX, "C::" .. name, "RAID")
end

local function Broadcast_ClearAll()
  if not UnitInRaid("player") then return end
  if not IsSelfLeaderOrAssist() then return end
  SendAddonMessage(ADDON_PREFIX, "X::CLEARALL", "RAID")
end

local function Broadcast_SetML(name)
  if not UnitInRaid("player") then return end
  if not IsSelfRaidLeader() then return end
  SendAddonMessage(ADDON_PREFIX, "M::" .. (name or ""), "RAID")
end

local function Broadcast_FullList()
  if not UnitInRaid("player") then return 0 end
  if not IsSelfLeaderOrAssist() then return 0 end
  local count = 0
  for name, v in pairs(TacticaDB.Healers) do if v then SendAddonMessage(ADDON_PREFIX, "S:H:"..name, "RAID"); count = count + 1 end end
  for name, v in pairs(TacticaDB.DPS)     do if v then SendAddonMessage(ADDON_PREFIX, "S:D:"..name, "RAID"); count = count + 1 end end
  for name, v in pairs(TacticaDB.Tanks)   do if v then SendAddonMessage(ADDON_PREFIX, "S:T:"..name, "RAID"); count = count + 1 end end
  SendAddonMessage(ADDON_PREFIX, "M::" .. (TacticaDB.MasterLooter or ""), "RAID")
  return count
end

local function SendHelloRequest()
  if not UnitInRaid("player") then return end
  SendAddonMessage(ADDON_PREFIX, "Q::HELLO", "RAID")
end

local function OnAddonMessage()
  -- Ignore version control messages from core
  if type(arg2)=="string" then
    local s = arg2
    if string.sub(s,1,4)=="VER:" or string.sub(s,1,12)=="TACTICA_VER:" or s=="TACTICA_WHO" or string.sub(s,1,11)=="TACTICA_ME:" then return end
  end
  -- Ignore version pings from core
  if type(arg2)=="string" and string.sub(arg2,1,4)=="VER:" then return end
  local prefix = arg1
  local text   = arg2
  local sender = arg4
  if prefix ~= ADDON_PREFIX then return end
  if not sender or sender == "" then return end

  -- Ignore own outbound
  local me = UnitName and UnitName("player") or ""
  if sender == me then return end

  local t, r, n = Split3(text)

  if t == "Q" and r == "" and n == "HELLO" then
    if IsSelfLeaderOrAssist() then Broadcast_FullList() end
    return
  end

  -- Only allow raid officers to drive state for others
  if not IsLeaderOrAssistByName(sender) then return end

  if t == "X" and r == "" and n == "CLEARALL" then
    TacticaDB.Healers = {}
    TacticaDB.DPS = {}
    TacticaDB.Tanks = {}
    TacticaDB.MasterLooter = ""
    Pfui_ReapplyAllTanks()
    if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
	NotifyBuilder();
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r Role tags cleared (cleared by officer).")
    return
  end

  if t == "M" and r == "" then
    if not IsRaidLeaderByName(sender) then return end
    SetMasterLooterPreset(n or "")
    if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
    NotifyBuilder()
    return
  end

  if t == "S" and r and r ~= "" and n and n ~= "" then
    local role = (r == "H" or r == "D" or r == "T") and r or nil
    if role then
      ApplyRoleFromNetwork(n, role)
      if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
	  NotifyBuilder()
    end
  elseif t == "C" and n and n ~= "" then
    ClearAllRolesFor(n); Pfui_SetTank(n, false)
    if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
	NotifyBuilder()
  end
end

-- Returns true if the named raid member is currently online
local function IsRaidMemberOnline(target)
  if not (UnitInRaid and UnitInRaid("player")) then return false end
  local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  for i = 1, n do
    local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
    if name == target then
      return online and true or false
    end
  end
  return false
end

------------------------------------------------------------
-- Context menu & click hook
------------------------------------------------------------
local menuInjected = false
local function AddMenuButton()
  if menuInjected then return end
  if not UnitPopupButtons or not UnitPopupMenus then return end
  if not UnitPopupMenus["RAID"] and not UnitPopupMenus["PARTY"] then return end

  -- buttons
  if not UnitPopupButtons[BUTTON_KEY_HEALER] then
    UnitPopupButtons[BUTTON_KEY_HEALER] = { text = "Toggle as Healer", dist = 0 }
  end
  if not UnitPopupButtons[BUTTON_KEY_DPS] then
    UnitPopupButtons[BUTTON_KEY_DPS] = { text = "Toggle as DPS", dist = 0 }
  end
  if not UnitPopupButtons[BUTTON_KEY_TANK] then
    UnitPopupButtons[BUTTON_KEY_TANK] = { text = "Toggle as Tank", dist = 0 }
  end
  if not UnitPopupButtons[BUTTON_KEY_ML] then
    UnitPopupButtons[BUTTON_KEY_ML] = { text = "Preset Masterlooter", dist = 0 }
  end

  -- Decides whether to HIDE Tactica Tank based on pfUI + SuperWoW
  -- Rule: only hide if BOTH pfUI and SuperWoW are present.
  local hideOurTank = (Tactica_hasPfUI and Tactica_hasSuperWoW)

  local function ensureItem(menu, key, insertIndex)
    if not menu then return end
    local exists = false
    local n = table.getn(menu)
    for i = 1, n do if menu[i] == key then exists = true; break end end
    if not exists then table.insert(menu, insertIndex or 3, key) end
  end

  -- Insert into RAID menu
  do
    local menu = UnitPopupMenus["RAID"]
    ensureItem(menu, BUTTON_KEY_HEALER, 3)
    ensureItem(menu, BUTTON_KEY_DPS,    4)
    if not hideOurTank then ensureItem(menu, BUTTON_KEY_TANK, 5) end
    ensureItem(menu, BUTTON_KEY_ML,      6)
  end

  -- Insert into PARTY menu (right-click party frames)
  do
    local menu = UnitPopupMenus["PARTY"]
    ensureItem(menu, BUTTON_KEY_HEALER, 3)
    ensureItem(menu, BUTTON_KEY_DPS,    4)
    if not hideOurTank then ensureItem(menu, BUTTON_KEY_TANK, 5) end
    ensureItem(menu, BUTTON_KEY_ML,      6)
  end
  
  -- Insert into PLAYER menu (generic other-player unit menu)
  do
    local menu = UnitPopupMenus["PLAYER"]
    ensureItem(menu, BUTTON_KEY_HEALER, 3)
    ensureItem(menu, BUTTON_KEY_DPS,    4)
    ensureItem(menu, BUTTON_KEY_TANK,   5)
    ensureItem(menu, BUTTON_KEY_ML,     6)
  end

  menuInjected = true
end

-- Handle buttons AND pfUI's Tank when present
local hookInstalled = false
local function HandleMenuClick()
  if not this or not this.value then return end
  EnsureDB()
  local inRaid  = UnitInRaid and UnitInRaid("player")
  local inParty = (GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0) and true or false
  if (not inRaid) and (not inParty) then return end

  local dropdownFrame = getglobal(UIDROPDOWNMENU_INIT_MENU or "")
  if not dropdownFrame then return end

  local name = dropdownFrame.name
  if (not name or name == "") and dropdownFrame.unit then name = UnitName(dropdownFrame.unit) end
  if not name or name == "" then return end

  local key = this.value
  local roleWanted = nil
  local isExternalPfuiTank = false

  if key == BUTTON_KEY_HEALER then roleWanted = "H"
  elseif key == BUTTON_KEY_DPS  then roleWanted = "D"
  elseif key == BUTTON_KEY_TANK then roleWanted = "T"
  elseif key == BUTTON_KEY_ML then
    if not UnitInRaid("player") then return end
    if not IsSelfRaidLeader() then
      (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffff5555Tactica:|r Only raid leader can preset master looter.")
      return
    end
    local current = TacticaDB.MasterLooter or ""
    local nextName = (current == name) and "" or name
    TacticaRaidRoles_SetPresetMasterLooter(nextName)
    if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
    NotifyBuilder()
    local msg = (nextName ~= "") and (nextName .. " preset as ML.") or "Preset ML cleared."
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r " .. msg)
    return
  elseif Tactica_hasPfUI and External_Tank_Key and key == External_Tank_Key then
    roleWanted = "T"; isExternalPfuiTank = true
  else
    local info = UnitPopupButtons and UnitPopupButtons[key]
    if Tactica_hasPfUI and info and info.text == "Toggle as Tank" then
      roleWanted = "T"; isExternalPfuiTank = true
    end
  end
  if not roleWanted then return end

  if isExternalPfuiTank then suppressPfuiWrite = true end
  local newRole, msg = SetExclusiveRole(name, roleWanted)
  suppressPfuiWrite = false

  if msg then
	  if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
	  if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
	  (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage(string.format("|cff33ff99Tactica:|r %s is now %s.", name, msg))

	  -- broadcast stays leader/assist only
	  if IsSelfLeaderOrAssist() then
		if newRole == nil then
		  Broadcast_Clear(name)
		else
		  Broadcast_Set(name, newRole)
		end
	  end

	  -- whisper MUST be leader-only (raid: leader/assist, party: party leader)
	  if not (TacticaDB and TacticaDB.Settings) then TacticaDB = TacticaDB or {}; TacticaDB.Settings = TacticaDB.Settings or {} end
	  if TacticaDB.Settings.RoleWhisperEnabled ~= false then
		local me = UnitName and UnitName("player") or nil
		if me and me ~= name and IsUnitOnlineByName(name) then
		  local inRaidNow = UnitInRaid and UnitInRaid("player")
		  local canWhisper = false
		  if inRaidNow then
			canWhisper = IsSelfLeaderOrAssist() and true or false
		  else
			canWhisper = (IsPartyLeader and IsPartyLeader()) and true or false
		  end

		  if canWhisper then
			local w
			if newRole == "H" then
			  w = "[Tactica]: You are marked as 'H' (Healer) on the raid roster."
			elseif newRole == "T" then
			  w = "[Tactica]: You are marked as 'T' (Tank) on the raid roster."
			elseif newRole == "D" then
			  w = "[Tactica]: You are marked as 'D' (DPS) on the raid roster."
			else
			  w = "[Tactica]: You are no longer marked on the raid roster."
			end
			if SendChatMessage then
			  SendChatMessage(w, "WHISPER", nil, name)
			end
		  end
		end
	  end
	end
end

local function MaybeWhisperRole(targetName, roleKeyOrNil)
    -- respect toggle
    if not (TacticaDB and TacticaDB.Settings and TacticaDB.Settings.RoleWhisperEnabled) then return end
    -- do not whisper self
    local me = UnitName and UnitName("player") or nil
    if not targetName or targetName == me then return end

    local msg
    if roleKeyOrNil == "H" then
        msg = "Tactica - You are marked as 'H' (Healer) on the raid roster."
    elseif roleKeyOrNil == "T" then
        msg = "Tactica - You are marked as 'T' (Tank) on the raid roster."
    elseif roleKeyOrNil == "D" then
        msg = "Tactica - You are marked as 'D' (DPS) on the raid roster."
    else
        msg = "Tactica - You are no longer marked on the raid roster."
    end

    if SendChatMessage then
        SendChatMessage(msg, "WHISPER", nil, targetName)
    end
end

local function InstallClickHook()
  if hookInstalled then return end
  if type(hooksecurefunc) == "function" then
    hooksecurefunc("UnitPopup_OnClick", HandleMenuClick)
  else
    local orig = UnitPopup_OnClick
    UnitPopup_OnClick = function() HandleMenuClick(); if orig then orig() end end
  end
  hookInstalled = true
end

------------------------------------------------------------
-- Roster decoration
------------------------------------------------------------
local function BuildRoleTag(name)
  if not name or name == "" then return "" end
  if TacticaDB.Healers[name] then return "H" end
  if TacticaDB.DPS[name]    then return "D" end
  if TacticaDB.Tanks[name]  then return "T" end
  return ""
end

------------------------------------------------------------
-- Party frame decoration (T/H/D)
------------------------------------------------------------
local function GetPartyNameFS(i)
  return getglobal("PartyMemberFrame"..i.."Name")
end

local function GetOrCreatePartyTag(frame)
  if not frame then return nil end
  if not frame.TacticaPartyRoleTag then
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.TacticaPartyRoleTag = fs
    frame.TacticaPartyRoleTag:SetTextColor(1,1,0)
    frame.TacticaPartyRoleTag:SetJustifyH("RIGHT")
    local fpath, fsize = frame.TacticaPartyRoleTag:GetFont()
    if fpath and fsize then frame.TacticaPartyRoleTag:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return frame.TacticaPartyRoleTag
end

local function GetOrCreatePlayerTag()
  if not PlayerFrame then return nil end
  if not PlayerFrame.TacticaPlayerRoleTag then
    local fs = PlayerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    PlayerFrame.TacticaPlayerRoleTag = fs
    PlayerFrame.TacticaPlayerRoleTag:SetTextColor(1,1,0)
    PlayerFrame.TacticaPlayerRoleTag:SetJustifyH("RIGHT")
    local fpath, fsize = fs:GetFont()
    if fpath and fsize then fs:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return PlayerFrame.TacticaPlayerRoleTag
end

local function GetOrCreateTag(btn)
  if not btn.TacticaRoleTag then
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.TacticaRoleTag = fs
    btn.TacticaRoleTag:SetTextColor(1,1,0)
    btn.TacticaRoleTag:SetJustifyH("RIGHT")
    local fpath, fsize = btn.TacticaRoleTag:GetFont()
    if fpath and fsize then btn.TacticaRoleTag:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return btn.TacticaRoleTag
end

local function GetOrCreateMLTag(btn)
  if not btn.TacticaMLTag then
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.TacticaMLTag = fs
    btn.TacticaMLTag:SetTextColor(1, 0.82, 0)
    btn.TacticaMLTag:SetJustifyH("LEFT")
    local fpath, fsize = btn.TacticaMLTag:GetFont()
    if fpath and fsize then btn.TacticaMLTag:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return btn.TacticaMLTag
end

local function GetListNameFS(i) return getglobal("RaidGroupButton"..i.."Name") end
local function GetListClassFS(i) return getglobal("RaidGroupButton"..i.."Class") end

local function GetGridNameFS(btn, name)
  local base = btn:GetName()
  if base then
    local fs = getglobal(base.."Name")
    if fs and fs.GetText then return fs end
  end
  if btn.GetFontString then
    local fs2 = btn:GetFontString()
    if fs2 and fs2.GetText then return fs2 end
  end
  if btn.GetRegions and name and name ~= "" then
    local regs = { btn:GetRegions() }
    local m = table.getn(regs)
    for i = 1, m do
      local r = regs[i]
      if r and r.GetObjectType and r:GetObjectType()=="FontString" and r.GetText then
        if r:GetText() == name then return r end
      end
    end
  end
  return nil
end

local function GetGridClassFS(btn)
  local base = btn and btn:GetName()
  if base then
    local fs = getglobal(base.."Class")
    if fs and fs.GetText then return fs end
  end
  return nil
end

local function Decorate_ListButtons()
  local any = false
  for i = 1, 40 do
    local btn = getglobal("RaidGroupButton"..i)
    if btn and btn:IsShown() then
      any = true
      local name = nil
      if GetRaidRosterInfo then name = GetRaidRosterInfo(i) end
      if (not name or name == "") and btn.unit then name = UnitName(btn.unit) end
      if (not name or name == "") and btn.name then name = btn.name end

      local nameFS = GetListNameFS(i)
      local classFS = GetListClassFS(i)
      local tagFS = GetOrCreateTag(btn)
      local mlFS = GetOrCreateMLTag(btn)
      tagFS:ClearAllPoints()
      mlFS:ClearAllPoints()
      if nameFS and nameFS:IsShown() then
        tagFS:SetPoint("RIGHT", nameFS, "LEFT", OFFSET_BEFORE_NAME_ACTIVE, 0)
        local tag = BuildRoleTag(name)
        if tag ~= "" then tagFS:SetText(tag); tagFS:Show() else tagFS:SetText(""); tagFS:Hide() end
        local anchorFS = classFS and classFS:IsShown() and classFS or nameFS
        mlFS:SetPoint("LEFT", anchorFS, "RIGHT", ML_TAG_OFFSET_AFTER_CLASS, 0)
        if name and TacticaDB.MasterLooter and name == TacticaDB.MasterLooter then
          mlFS:SetText("ML"); mlFS:Show()
        else
          mlFS:SetText(""); mlFS:Hide()
        end
      else
        tagFS:SetText(""); tagFS:Hide()
        mlFS:SetText(""); mlFS:Hide()
      end
    end
  end
  return any
end

local function Decorate_GroupGrid()
  local any = false
  for g = 1, 8 do
    for s = 1, 5 do
      local btn = getglobal("RaidGroup"..g.."Slot"..s)
      if btn and btn:IsShown() then
        any = true
        local name = btn.name
        if (not name or name == "") and btn.unit then name = UnitName(btn.unit) end

        local nameFS = GetGridNameFS(btn, name)
        local classFS = GetGridClassFS(btn)
        local tagFS = GetOrCreateTag(btn)
        local mlFS = GetOrCreateMLTag(btn)
        tagFS:ClearAllPoints()
        mlFS:ClearAllPoints()
        if nameFS then
          tagFS:SetPoint("RIGHT", nameFS, "LEFT", OFFSET_BEFORE_NAME_ACTIVE, 0)
          local tag = BuildRoleTag(name)
          if tag ~= "" then tagFS:SetText(tag); tagFS:Show() else tagFS:SetText(""); tagFS:Hide() end
          local anchorFS = classFS and classFS:IsShown() and classFS or nameFS
          mlFS:SetPoint("LEFT", anchorFS, "RIGHT", ML_TAG_OFFSET_AFTER_CLASS, 0)
          if name and TacticaDB.MasterLooter and name == TacticaDB.MasterLooter then
            mlFS:SetText("ML"); mlFS:Show()
          else
            mlFS:SetText(""); mlFS:Hide()
          end
        else
          tagFS:SetText(""); tagFS:Hide()
          mlFS:SetText(""); mlFS:Hide()
        end
      end
    end
  end
  return any
end

function Tactica_DecorateRaidRoster()
  EnsureDB()
  local ok = Decorate_ListButtons()
  if not ok then Decorate_GroupGrid() end
end

local function InstallRosterHooks()
  if type(hooksecurefunc) == "function" and type(RaidFrame_Update) == "function" then
    hooksecurefunc("RaidFrame_Update", function() Tactica_DecorateRaidRoster() end)
  elseif type(RaidFrame_Update) == "function" then
    local o = RaidFrame_Update; RaidFrame_Update = function() if o then o() end; Tactica_DecorateRaidRoster() end
  end
  if type(hooksecurefunc) == "function" and type(RaidGroupFrame_Update) == "function" then
    hooksecurefunc("RaidGroupFrame_Update", function() Tactica_DecorateRaidRoster() end)
  elseif type(RaidGroupFrame_Update) == "function" then
    local o2 = RaidGroupFrame_Update; RaidGroupFrame_Update = function() if o2 then o2() end; Tactica_DecorateRaidRoster() end
  end
end

local function InstallPartyHooks()
  if type(PartyMemberFrame_UpdateMember) == "function" then
    if type(hooksecurefunc) == "function" then
      hooksecurefunc("PartyMemberFrame_UpdateMember", function()
        if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
        if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end
      end)
    else
      local o = PartyMemberFrame_UpdateMember
      PartyMemberFrame_UpdateMember = function(...)
        if o then o(unpack(arg)) end
        if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
        if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end
      end
    end
  end

  if type(PartyMemberFrame_Update) == "function" then
    if type(hooksecurefunc) == "function" then
      hooksecurefunc("PartyMemberFrame_Update", function()
        if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
        if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end
      end)
    else
      local o2 = PartyMemberFrame_Update
      PartyMemberFrame_Update = function(...)
        if o2 then o2(unpack(arg)) end
        if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
        if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end
      end
    end
  end

  -- PlayerFrame updates (keeps SELF tag fresh)
  if type(PlayerFrame_Update) == "function" then
    if type(hooksecurefunc) == "function" then
      hooksecurefunc("PlayerFrame_Update", function()
        if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end
      end)
    else
      local op = PlayerFrame_Update
      PlayerFrame_Update = function(...)
        if op then op(unpack(arg)) end
        if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end
      end
    end
  end
end

InstallRosterHooks()

------------------------------------------------------------
-- Roster change detection & misc
------------------------------------------------------------
local lastRosterSig = ""
local lastFullBroadcast = 0
local justJoinedAt = 0 -- debounce broadcasts after player (re)join

local function BuildRosterSignature()
  local names = {}
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  for i = 1, n do
    local nm = GetRaidRosterInfo(i)
    if nm and nm ~= "" then table.insert(names, nm) end
  end
  if table.sort then table.sort(names, function(a, b) return a < b end) end
  local sig = ""
  local m = table.getn(names)
  for i = 1, m do sig = sig .. names[i] .. "|" end
  return sig
end

local function MaybeBroadcastFullList()
  if not IsSelfLeaderOrAssist() then return end
  local now = GetTime and GetTime() or 0
  if lastFullBroadcast ~= 0 and now - lastFullBroadcast < 2 then return end
  local count = Broadcast_FullList()
  lastFullBroadcast = now
end

-- small delay helper
local function RunLater(delay, fn)
  if not fn or delay <= 0 then fn(); return end
  local t, f = 0, CreateFrame("Frame")
  f:SetScript("OnUpdate", function()
    t = t + (arg1 or 0)
    if t >= delay then f:SetScript("OnUpdate", nil); fn() end
  end)
end

-- Coalesced delayed broadcast so role assignments updated by other modules (eg. auto-invite) have a chance to be applied before pushing a full list.
local pendingFullBroadcast = false
local function QueueBroadcastFullList()
  if pendingFullBroadcast then return end
  pendingFullBroadcast = true
  RunLater(0.5, function()
    pendingFullBroadcast = false
    MaybeBroadcastFullList()
  end)
end

------------------------------------------------------------
-- Manual push & clear-all (exported) + slash
------------------------------------------------------------
function TacticaRaidRoles_PushRoles(silent)
  EnsureDB()
  if not UnitInRaid("player") then
    if not silent and (DEFAULT_CHAT_FRAME or ChatFrame1) then (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r You must be in a raid to push roles.") end
    return
  end
  if not IsSelfLeaderOrAssist() then
    if not silent and (DEFAULT_CHAT_FRAME or ChatFrame1) then (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r Only raid leader/assist can push roles.") end
    return
  end
  local count = Broadcast_FullList()
  if not silent and (DEFAULT_CHAT_FRAME or ChatFrame1) then
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage(string.format("|cff33ff99Tactica:|r Pushed %d role assignment(s) to raid.", count or 0))
  end
end

local function WipeRoles(reason)
  EnsureDB()
  TacticaDB.Healers = {}
  TacticaDB.DPS = {}
  TacticaDB.Tanks = {}
  TacticaDB.MasterLooter = ""
  Pfui_ReapplyAllTanks() -- mutate keys only
  if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
  if (DEFAULT_CHAT_FRAME or ChatFrame1) then
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r Role tags cleared" .. (reason and (" ("..reason..")") or "") .. ".")
  end
end

function TacticaRaidRoles_ClearAllRoles(silent)
  EnsureDB()
  WipeRoles("manual clear")
  if IsSelfLeaderOrAssist() then Broadcast_ClearAll() end
end

-- Push slashes
SLASH_TACTICAPUSH1 = "/tactica_pushroles"
SLASH_TACTICAPUSH2 = "/ttpush"
SlashCmdList["TACTICAPUSH"] = function() TacticaRaidRoles_PushRoles(false) end

-- Clear-all slashes
SLASH_TACTICACLEAR1 = "/tactica_clearroles"
SLASH_TACTICACLEAR2 = "/ttclear"
SlashCmdList["TACTICACLEAR"] = function() TacticaRaidRoles_ClearAllRoles(false) end

------------------------------------------------------------
-- Init & Events
------------------------------------------------------------

-- forward-declare because AddMenuAndHooks calls these (Lua 5.0 local scope rules)
local UpdateSelfMenuVisibility
local InstallShowMenuHook

-- one-time install guard (functions are not tables in Lua 5.0)
local showMenuHookInstalled = false

-- ensure SELF menu shows our items only while in PARTY (and NOT in raid)
local function MenuHasKey(menu, key)
  if not menu then return false end
  for i=1, table.getn(menu) do
    if menu[i] == key then return true end
  end
  return false
end

local function MenuRemoveKey(menu, key)
  if not menu then return end
  local i=1
  while i <= table.getn(menu) do
    if menu[i] == key then
      table.remove(menu, i)
    else
      i = i + 1
    end
  end
end

local function MenuEnsureKey(menu, key, insertIndex)
  if not menu then return end
  if not MenuHasKey(menu, key) then
    table.insert(menu, insertIndex or 3, key)
  end
end

UpdateSelfMenuVisibility = function()
  if not UnitPopupMenus then return end
  local menu = UnitPopupMenus["SELF"]
  if not menu then return end

  local inRaid  = UnitInRaid and UnitInRaid("player")
  local inParty = (GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0) and true or false

  if inParty and not inRaid then
    -- ensure present in party (player frame)
    MenuEnsureKey(menu, BUTTON_KEY_HEALER, 3)
    MenuEnsureKey(menu, BUTTON_KEY_DPS,    4)
    MenuEnsureKey(menu, BUTTON_KEY_TANK,   5)
  else
    -- remove when solo or in raid
    MenuRemoveKey(menu, BUTTON_KEY_HEALER)
    MenuRemoveKey(menu, BUTTON_KEY_DPS)
    MenuRemoveKey(menu, BUTTON_KEY_TANK)
  end
end

-- hook menu show so SELF menu visibility is correct per-context
InstallShowMenuHook = function()
  if showMenuHookInstalled then return end
  showMenuHookInstalled = true

  local orig = UnitPopup_ShowMenu
  UnitPopup_ShowMenu = function(...)
    -- Update entries right before menu is shown
    UpdateSelfMenuVisibility()
    if orig then
      return orig(unpack(arg))
    end
  end
end

local function AddMenuAndHooks()
  EnsureDB()
  Tactica_DetectPfUI()
  Tactica_DetectSuperWoW()
  DetectExternalTankMenuKey()
  OFFSET_BEFORE_NAME_ACTIVE = Tactica_hasPfUI and OFFSET_BEFORE_NAME_PFUI or OFFSET_BEFORE_NAME_DEFAULT
  AddMenuButton()
  InstallClickHook()
  UpdateSelfMenuVisibility()
  InstallShowMenuHook()
  Tactica_DecorateRaidRoster()
  Pfui_ReapplyAllTanks()
end

local selfWasInRaid = false

local f = CreateFrame("Frame")
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("PARTY_LEADER_CHANGED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    OnAddonMessage(); return
  end

  if event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_LEADER_CHANGED" then
    -- Party state changed: make sure SELF menu entries are correct now
    EnsureDB()
    UpdateSelfMenuVisibility()

    -- If we're NOT in a raid, keep party-only role state clean so nothing "sticks"
    local inRaidNow  = UnitInRaid and UnitInRaid("player")
    if not inRaidNow then
      local pn = (GetNumPartyMembers and (GetNumPartyMembers() or 0)) or 0
      local inPartyNow = (pn > 0) and true or false

      if not inPartyNow then
        -- Party ended (or we were kicked) -> clear everything so no stale roles remain
        WipeRoles("left party")
      else
        -- Still in party: purge roles for anyone not currently in the party
        local present = {}
        local me = UnitName and UnitName("player")
        if me and me ~= "" then present[me] = true end
        for i=1,pn do
          local u = "party"..i
          if UnitExists and UnitExists(u) then
            local nm = UnitName(u)
            if nm and nm ~= "" then present[nm] = true end
          end
        end

        for n in pairs(TacticaDB.Healers) do if not present[n] then TacticaDB.Healers[n] = nil end end
        for n in pairs(TacticaDB.DPS)     do if not present[n] then TacticaDB.DPS[n]     = nil end end
        for n in pairs(TacticaDB.Tanks)   do if not present[n] then TacticaDB.Tanks[n]   = nil end end
        if TacticaDB.MasterLooter and TacticaDB.MasterLooter ~= "" and not present[TacticaDB.MasterLooter] then
          TacticaDB.MasterLooter = ""
        end

        -- Keep pfUI tank flags aligned with the cleaned DB
        Pfui_ReapplyAllTanks()

        -- Refresh visuals
        if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
        if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end
      end
    end

    -- IMPORTANT: party changes should refresh Raid Builder preview
    NotifyBuilder()
    return
  end

  if event == "RAID_ROSTER_UPDATE" then
    local inRaid = UnitInRaid("player")
    if inRaid and not selfWasInRaid then
      justJoinedAt = GetTime and GetTime() or 0
      RunLater(0.5, function() SendHelloRequest() end)
    elseif (not inRaid) and selfWasInRaid then
      WipeRoles("left raid")
    end
    selfWasInRaid = inRaid and true or false

    local sig = BuildRosterSignature()
    if sig ~= lastRosterSig then
      lastRosterSig = sig
      local now = GetTime and GetTime() or 0
      if not justJoinedAt or (now - justJoinedAt) >= 3 then
        QueueBroadcastFullList()
      end
    end

  elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" or event == "VARIABLES_LOADED" then
    AddMenuAndHooks()
    selfWasInRaid = UnitInRaid("player") and true or false
    if selfWasInRaid then RunLater(0.8, function() SendHelloRequest() end) end
    local sig2 = BuildRosterSignature()
    if sig2 ~= "" then lastRosterSig = sig2 end
  end
end)
