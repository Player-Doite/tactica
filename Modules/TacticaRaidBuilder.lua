-- TacticaRaidBuilder.lua - Raid/LFM Builder with Auto-Announcer for "vanilla"-compliant versions of Wow
-- Created by Doite

-------------------------------------------------
-- Compat shims
-------------------------------------------------
do
  if not string.gmatch and string.gfind then
    string.gmatch = function(s, p) return string.gfind(s, p) end
  end
  if not string.match then
    string.match = function(s, p, init)
      local _, _, g1 = string.find(s, p, init)
      return g1
    end
  end
end

-------------------------------------------------
-- Module & saved state
-------------------------------------------------
local RB = TacticaRaidBuilder or {}
TacticaRaidBuilder = RB

local function EnsureDB()
  if not TacticaDB then TacticaDB = {} end
  if not TacticaDB.Builder then TacticaDB.Builder = {} end
  if not TacticaDB.BuilderFrame then TacticaDB.BuilderFrame = {} end
  if not TacticaDB.Tanks   then TacticaDB.Tanks   = {} end
  if not TacticaDB.Healers then TacticaDB.Healers = {} end
  if not TacticaDB.DPS     then TacticaDB.DPS     = {} end
end
local function Saved() EnsureDB(); return TacticaDB.Builder end
local function RB_Print(msg) local cf=DEFAULT_CHAT_FRAME or ChatFrame1; if cf then cf:AddMessage(msg) end end

-- Presets DB
local function PresetsDB()
  EnsureDB()
  if not TacticaDB.BuilderPresets then TacticaDB.BuilderPresets = {} end
  return TacticaDB.BuilderPresets
end

local function RB_Trim(s)
  s = s or ""
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

local function RB_SnapshotForPreset()
  return {
    raid      = RB.state.raid,
    worldBoss = RB.state.worldBoss,
    esMode    = RB.state.esMode,
    customRaidText = RB.state.customRaidText or "",
    size      = RB.state.size,
    size_selected = RB.state.size_selected and true or false,
    tanks     = RB.state.tanks,
    healers   = RB.state.healers,
    srs       = RB.state.srs,
    hr        = RB.state.hr,
    free      = RB.state.free,
    canSum    = RB.state.canSum and true or false,
    hideNeed  = RB.state.hideNeed and true or false,
    chWorld   = RB.state.chWorld and true or false,
    chLFG     = RB.state.chLFG   and true or false,
    chYell    = RB.state.chYell  and true or false,
    interval  = RB.state.interval,
    gearScale = RB.state.gearScale,
    autoGear  = RB.state.autoGear and true or false,
	aiAutoRoles  = RB.state.aiAutoRoles and true or false,
    aiAutoInvite = RB.state.aiAutoInvite and true or false,
    discordLink = RB.state.discordLink or "",
  }
end

local function RB_PresetNamesSorted()
  local t = {}
  for name,_ in pairs(PresetsDB()) do table.insert(t, name) end
  table.sort(t, function(a,b) return string.lower(a)<string.lower(b) end)
  return t
end

-------------------------------------------------
-- Allowed sizes per raid
-------------------------------------------------
local ALL_SIZES = { 10, 12, 15, 20, 25, 30, 35, 40 }
local AllowedSizes = {
  ["Molten Core"]          = { 20, 25, 30, 35, 40 },
  ["Blackwing Lair"]       = { 20, 25, 30, 35, 40 },
  ["Zul'Gurub"]            = { 12, 15, 20 },
  ["Ruins of Ahn'Qiraj"]   = { 12, 15, 20 },
  ["Temple of Ahn'Qiraj"]  = { 20, 25, 30, 35, 40 },
  ["Onyxia's Lair"]        = { 12, 15, 20, 25, 30, 35, 40 },
  ["Naxxramas"]            = { 30, 35, 40 },
  ["Lower Karazhan Halls"] = { 10 },
  ["Upper Karazhan Halls"] = { 35, 40 },
  ["Emerald Sanctum"]      = { 30, 35, 40 },
  ["World Bosses"]         = ALL_SIZES,
}

-------------------------------------------------
-- Defaults & suggested composition
-------------------------------------------------
local BuilderDefaults = {
  ["Molten Core"] = {
    size=40, tanks=3, healers=8, srs=2,
    notes={ dispel=6, cleanse=0, decurse=6, tranq=2, purge=0, sheep=2, banish=2, shackle=0, sleep=0, fear=4 }
  },
  ["Blackwing Lair"] = {
    size=40, tanks=3, healers=8, srs=2,
    notes={ dispel=4, cleanse=4, decurse=4, tranq=2, purge=0, sheep=0, banish=0, shackle=0, sleep=2, fear=4 }
  },
  ["Zul'Gurub"] = {
    size=20, tanks=2, healers=4, srs=2,
    notes={ dispel=2, cleanse=2, decurse=4, tranq=0, purge=0, sheep=2, banish=0, shackle=0, sleep=0, fear=2 }
  },
  ["Ruins of Ahn'Qiraj"] = {
    size=20, tanks=2, healers=4, srs=2,
    notes={ dispel=2, cleanse=2, decurse=2, tranq=1, purge=0, sheep=0, banish=0, shackle=0, sleep=0, fear=0 }
  },
  ["Temple of Ahn'Qiraj"] = {
    size=40, tanks=4, healers=8, srs=2,
    notes={ dispel=6, cleanse=6, decurse=0, tranq=0, purge=0, sheep=2, banish=0, shackle=0, sleep=0, fear=6 }
  },
  ["Onyxia's Lair"] = {
    size=40, tanks=1, healers=8, srs=1,
    notes={ dispel=0, cleanse=0, decurse=0, tranq=0, purge=0, sheep=0, banish=0, sleep=0, fear=4 }
  },
  ["Naxxramas"] = {
    size=40, tanks=4, healers=10, srs=2,
    notes={ dispel=6, cleanse=6, decurse=6, tranq=2, purge=0, sheep=0, banish=0, shackle=3, sleep=0, fear=4 }
  },
  ["Lower Karazhan Halls"] = {
    size=10, tanks=2, healers=2, srs=1,
    notes={ dispel=1, cleanse=2, decurse=2, tranq=0, purge=0, sheep=0, banish=0, sleep=0, fear=0 }
  },
  ["Upper Karazhan Halls"] = {
    size=40, tanks=4, healers=10, srs=2,
    notes={ dispel=6, cleanse=6, decurse=6, tranq=1, purge=0, sheep=0, banish=2, shackle=3, sleep=0, fear=6 }
  },
  ["Emerald Sanctum"] = {
    size=40, tanks=3, healers = { Normal = 8, HM = 10 }, srs=1,
    notes={ dispel=6, cleanse=6, decurse=6, tranq=0, purge=0, sheep=0, banish=0, shackle=0, sleep=0, fear=0 }
  },
  ["World Bosses"] = {
    size=40, tanks=1, healers=8, srs=1,
    notes={ dispel=1, cleanse=1, decurse=1, tranq=1, purge=1, sheep=1, banish=1, shackle=1, sleep=1, fear=1 }
  },
}

local function SuggestGearScale(raid, esMode, worldBoss)
  if not raid then return nil end
  if raid == "Molten Core"          then return 1 end
  if raid == "Blackwing Lair"       then return 1 end
  if raid == "Zul'Gurub"            then return 0 end
  if raid == "Ruins of Ahn'Qiraj"   then return 0 end
  if raid == "Temple of Ahn'Qiraj"  then return 2 end
  if raid == "Onyxia's Lair"        then return 0 end
  if raid == "Naxxramas"            then return 3 end
  if raid == "Lower Karazhan Halls" then return 1 end
  if raid == "Upper Karazhan Halls" then return 4 end
  if raid == "Emerald Sanctum"      then return 1 end
  if raid == "World Bosses" then
    if worldBoss and worldBoss ~= "" then
      return 1
    end
    return nil
  end
  return nil
end

local function Scale(val, size, base)
  local num = (val * size) / base
  local r   = math.floor(num + 0.5)
  if r < 1 then r = 1 end
  if r > 10 then r = 10 end
  return r
end

local function ComputeDefaults(raidName, raidSize, esMode)
  local b = BuilderDefaults[raidName]
  if not b then return { tanks=2, healers=5, srs=1 } end

  local tanksFixed = b.tanks
  local baseHealers = b.healers
  if raidName == "Emerald Sanctum" and type(b.healers) == "table" then
    local key = (esMode == "HM" or esMode == "Hard Mode") and "HM" or "Normal"
    baseHealers = b.healers[key] or b.healers.Normal or b.healers.HM or 8
  end

  local healersScaled = Scale(baseHealers, raidSize, b.size)
  local srsFixed = b.srs
  return { tanks=tanksFixed, healers=healersScaled, srs=srsFixed }
end

-------------------------------------------------
-- Suggested composition text (X/Y)
-------------------------------------------------
local SCALE_KEYS = { dispel=true, cleanse=true, decurse=true, fear=true }
local LABELS = {
  dispel  = "Dispel", cleanse = "Cleanse", decurse = "Decurse",
  tranq   = "Tranq/Kite", purge = "Purge", sheep = "Sheep",
  banish  = "Banish", shackle = "Shackle", sleep = "Sleep",
  fear    = "Fearward/Tremor",
}
local CLASSSETS = {
  dispel  = { Priest=true, Paladin=true },
  cleanse = { Shaman=true, Druid=true, Paladin=true },
  decurse = { Mage=true, Druid=true },
  purge   = { Priest=true, Shaman=true },
  tranq   = { Hunter=true },
  sheep   = { Mage=true },
  banish  = { Warlock=true },
  shackle = { Priest=true },
  sleep   = { Druid=true },
  fear    = { Priest=true, Shaman=true },
}

local function RB_CountUtility(utilKey)
  local classset = CLASSSETS[utilKey]
  if not classset then return 0 end
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  if n <= 0 then return 0 end
  local count = 0
  local i
  for i=1,n do
    local name, _, _, _, classLoc = GetRaidRosterInfo(i)
    if name and classLoc and classset[classLoc] then
      local isTank = TacticaDB and TacticaDB.Tanks and TacticaDB.Tanks[name] == true
      if (utilKey == "dispel" or utilKey == "cleanse" or utilKey == "decurse")
         and isTank and (classLoc == "Druid" or classLoc == "Paladin") then
      else
        count = count + 1
      end
    end
  end
  return count
end

local function CompositionText(raidName, raidSize)
  if not raidName or not BuilderDefaults[raidName] then return "" end
  local base = BuilderDefaults[raidName].notes or {}
  local suggested = {}
  for k,_ in pairs(LABELS) do
    local basev = base[k] or 0
    if SCALE_KEYS[k] then
      suggested[k] = (raidSize and basev and basev > 0)
        and Scale(basev, raidSize, BuilderDefaults[raidName].size)
        or basev
    else
      suggested[k] = basev
    end
  end
  local parts = {}
  local order = { "dispel","cleanse","decurse","tranq","purge","sheep","banish","shackle","sleep","fear" }
  local i
  for i=1,table.getn(order) do
    local key = order[i]
    local Y = suggested[key] or 0
    if Y > 0 then
      local X = RB_CountUtility(key)
      table.insert(parts, LABELS[key] .. " " .. X .. "/" .. Y)
    end
  end
  if table.getn(parts) == 0 then return "" end
  return table.concat(parts, ", ")
end

-------------------------------------------------
-- Short raid label
-------------------------------------------------
local function ShortRaidLabel(full)
  if not full or not Tactica or not Tactica.Aliases then return full end
  local nicify = { ony="Ony", kara10="Kara10", kara40="Kara40", world="World", es="ES" }
  for short, long in pairs(Tactica.Aliases) do
    if long == full then return nicify[short] or string.upper(short) end
  end
  return full
end

-------------------------------------------------
-- State & widgets
-------------------------------------------------
RB.state = RB.state or {
  raid=nil, worldBoss=nil, esMode=nil,
  customRaidText=nil,
  size=nil, size_selected=false,
  tanks=nil, healers=nil, srs=0,
  hr="", free="", canSum=false, hideNeed=false,
  chWorld=false, chLFG=false, chYell=false,
  auto=false, interval=120, running=false,
  gearScale=nil, autoGear=false,
  aiAutoRoles=false,
  aiAutoInvite=false,
  srLink="",           -- session-only
  discordLink="",
}
RB.frame = RB.frame or nil
RB.ddRaid, RB.ddWBoss, RB.ddESMode, RB.ddSize = nil, nil, nil, nil
RB.ddTanks, RB.ddHealers, RB.ddSRs = nil, nil, nil
RB.cbWorld, RB.cbLFG, RB.cbYell, RB.cbAuto, RB.cbCanSum, RB.cbHideNeed = nil, nil, nil, nil, nil, nil
RB.ddInterval = nil
RB.editHR, RB.editFree = nil, nil
RB.lblNotes, RB.lblPreview, RB.lblHint = nil, nil, nil
RB.btnAnnounce, RB.btnSelf, RB.btnRaid, RB.btnClear, RB.btnClose = nil, nil, nil, nil, nil
RB.lockButton = nil
RB._warnOk, RB._confirm = false, nil
RB._lastManual = 0

-- SR/Discord UI
RB.editSRLink, RB.editDiscordLink, RB.btnSRDPost = nil, nil, nil
RB.titleSRD, RB.sepSRD = nil, nil

-- Auto-Invite controls (RB-driven; not saved)
RB.cbAutoInvite = nil
RB._aiEnabledLast = false
RB._aiAutoRolesLast = false

-------------------------------------------------
-- Timers (for small delays)
-------------------------------------------------
RB._timers = RB._timers or {}
local function RB_After(sec, fn)
  if not sec or sec <= 0 then fn(); return end
  table.insert(RB._timers, { t=(GetTime and GetTime() or 0)+sec, fn=fn })
end
RB._tick = RB._tick or CreateFrame("Frame")
RB._tick:SetScript("OnUpdate", function()
  if not RB._timers or table.getn(RB._timers)==0 then return end
  local now = GetTime and GetTime() or 0
  local i = 1
  while i <= table.getn(RB._timers) do
    local it = RB._timers[i]
    if it and it.t <= now then
      local fn = it.fn
      table.remove(RB._timers, i)
      if fn then fn() end
    else
      i = i + 1
    end
  end
end)

-------------------------------------------------
-- Raid roster helpers
-------------------------------------------------
function RB_RaidRosterSet()
  local set = {}

  local rn = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  if rn and rn > 0 then
    local i
    for i = 1, rn do
      local name = GetRaidRosterInfo(i)
      if name and name ~= "" then set[name] = true end
    end
    return set, rn
  end

  -- party mode (includes player + party1..4)
  local count = 0

  local me = UnitName and UnitName("player")
  if me and me ~= "" then
    set[me] = true
    count = count + 1
  end

  local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  local i
  for i = 1, pn do
    local u = "party"..i
    if UnitExists and UnitExists(u) then
      local nm = UnitName(u)
      if nm and nm ~= "" then
        if not set[nm] then
          set[nm] = true
          count = count + 1
        end
      end
    end
  end

  return set, count
end

-- Public notifier: call from the Roles module after updating TacticaDB.Tanks/Healers/DPS
function TacticaRaidBuilder.NotifyRoleAssignmentChanged()
  RB._dirty = true
  RB.RefreshPreview()
end

function TacticaRaidBuilder.AutoRolesEnabled()
  return RB and RB.cbRoleAssign and RB.cbRoleAssign:GetChecked() and true or false
end

-- Passive change detector (also catches changes without explicit notifier)
RB._roleSig = ""
RB._rolesWatch = RB._rolesWatch or CreateFrame("Frame")
do
  local accum = 0
  RB._rolesWatch:SetScript("OnUpdate", function(_, elapsed)
    accum = (accum or 0) + (elapsed or 0)
    if accum < 0.5 then return end
    accum = 0

    local rosterSet = RB_RaidRosterSet()
    local excl = RB._exclude or {}

    local T = (TacticaDB and TacticaDB.Tanks) or {}
    local H = (TacticaDB and TacticaDB.Healers) or {}
    local D = (TacticaDB and TacticaDB.DPS) or {}

    local ct, ch, cd = 0,0,0
    local name
    for name,_ in pairs(rosterSet) do
      if not excl[name] then
        if     T[name] then ct=ct+1
        elseif H[name] then ch=ch+1
        elseif D[name] then cd=cd+1
        end
      end
    end

    local sig = ct..":"..ch..":"..cd
    if sig ~= RB._roleSig then
      RB._roleSig = sig
      RB._dirty = true
      RB.RefreshPreview()
    end
  end)
end

-------------------------------------------------
-- Channels + announce helpers
-------------------------------------------------
local function BuildNeedString(raidSize, tanksWant, healersWant, hideNeed)
  local rosterSet, _ = RB_RaidRosterSet()

  -- apply Exclude List to totals and roles
  local excl = RB._exclude or {}

  -- total (LFxM headcount)
  local inRaidEff = 0
  local name
  for name,_ in pairs(rosterSet) do if not excl[name] then inRaidEff = inRaidEff + 1 end end
  local needM = raidSize and (raidSize - inRaidEff) or 0
  if needM < 0 then needM = 0 end

  local T = (TacticaDB and TacticaDB.Tanks)   or {}
  local H = (TacticaDB and TacticaDB.Healers) or {}
  local D = (TacticaDB and TacticaDB.DPS)     or {}

  local ct, ch, cd = 0, 0, 0
  for name,_ in pairs(rosterSet) do
    if not excl[name] then
      if     T[name] then ct = ct + 1
      elseif H[name] then ch = ch + 1
      elseif D[name] then cd = cd + 1
      end
    end
  end

  local needT = (tanksWant   or 0) - ct; if needT < 0 then needT = 0 end
  local needH = (healersWant or 0) - ch; if needH < 0 then needH = 0 end
  local dBudget = (raidSize or 0) - (tanksWant or 0) - (healersWant or 0); if dBudget < 0 then dBudget = 0 end
  local needD = dBudget - cd; if needD < 0 then needD = 0 end

  -- If player "over-invite" tanks/healers, total remaining slots (needM) shrinks. Clamp role requests so player never ask for more people than can actually fit.
  local slotsLeft = needM
  if slotsLeft < 0 then slotsLeft = 0 end
  if needT > slotsLeft then needT = slotsLeft end
  slotsLeft = slotsLeft - needT
  if needH > slotsLeft then needH = slotsLeft end
  slotsLeft = slotsLeft - needH
  if needD > slotsLeft then needD = slotsLeft end

  local parts = {}
  if needT > 0 then table.insert(parts, hideNeed and "Tank"   or (needT .. "xTanks"))   end
  if needH > 0 then table.insert(parts, hideNeed and "Healer" or (needH .. "xHealers")) end
  if needD > 0 then table.insert(parts, hideNeed and "DPS"    or (needD .. "xDPS"))     end

  local needStr = ""
  if table.getn(parts) > 0 then
    needStr = " - Need: " .. table.concat(parts, ", ")
  end

  return needM, needStr
end


local function EffectiveRaidNameAndLabel()
  if RB.state.raid == "-CUSTOM-" then
    local txt = RB_Trim(RB.state.customRaidText or "")
    if txt == "" then
      return nil, nil
    end
    -- Use the user's text as the raid "label" in LFM + Preview
    return txt, txt
  end

  if RB.state.raid == "World Bosses" then
    if RB.state.worldBoss and RB.state.worldBoss ~= "" then
      return RB.state.worldBoss, RB.state.worldBoss
    else
      return nil, nil
    end
  elseif RB.state.raid == "Emerald Sanctum" then
    if not RB.state.esMode then return nil, nil end
    local short = ShortRaidLabel("Emerald Sanctum")
    local mode  = (RB.state.esMode == "Normal") and " (Normal)" or " (HM)"
    return "Emerald Sanctum", short .. mode
  else
    local full = RB.state.raid
    if not full then return nil, nil end
    return full, ShortRaidLabel(full)
  end
end

local function BuildLFM(raidLabelForMsg, raidSize, tanksWant, healersWant, srsWant, hrText, canSum, freeText, hideNeed)
  local needM, needStr = BuildNeedString(raidSize, tanksWant, healersWant, hideNeed)

  local srTxt  = (srsWant and srsWant > 0) and (srsWant .. "xSR") or "No SR"
  local hrTxt  = (hrText and hrText ~= "") and (" (HR " .. hrText .. ")") or ""
  local sumTxt = canSum and " - Can Sum" or ""
  local freeTxt= (freeText and freeText ~= "") and (" - " .. freeText) or ""

  local head
-- If hideNeed OR needM==0, show plain "LFM"
	if hideNeed or needM == 0 then
	  head = "LFM for " .. raidLabelForMsg .. sumTxt
	else
	  head = "LF" .. needM .. "M for " .. raidLabelForMsg .. sumTxt
	end

  local msg = head .. " - " .. srTxt .. " > MS > OS" .. hrTxt .. needStr .. freeTxt
  if string.len(msg) <= 255 then return msg end

  local shortHead = (hideNeed or needM == 0)
	  and ("LFM@" .. raidLabelForMsg .. sumTxt)
	  or  ("LF" .. needM .. "M@" .. raidLabelForMsg .. sumTxt)
  local msg2  = shortHead .. " - " .. srTxt .. ">MS>OS" .. hrTxt .. needStr .. freeTxt
  if string.len(msg2) <= 255 then return msg2 end
  local msg3  = shortHead .. " " .. srTxt .. hrTxt .. needStr .. freeTxt
  if string.len(msg3) <= 255 then return msg3 end
  return string.sub(shortHead .. needStr .. freeTxt, 1, 255)
end

local function Announce(msg, dryRun, chWorld, chLFG, chYell)
  if dryRun then RB_Print("|cff33ff99[Tactica]:|r " .. msg); return end
  if (not chWorld and not chLFG and not chYell) then
    RB_Print("|cffff6666[Tactica]:|r No channel selected (World/LFG/Yell). Printing here instead:\n|cff33ff99[Tactica]:|r "..msg)
    return
  end

  local function FindChanByName(...)
    local a = arg
    local i
    for i=1, table.getn(a) do
      local nm = a[i]
      if nm and nm ~= "" then
        local id = GetChannelName and GetChannelName(nm) or 0
        if id and id > 0 then return id end
      end
    end
  end
  local function FallbackFind(pred)
    local list = { GetChannelList() }
    local i
    for i=1, table.getn(list), 2 do
      local id, name = list[i], list[i+1]
      if type(name)=="string" and pred(string.lower(name)) then return id end
    end
  end

  local worldId, lfgId
  if chWorld then
    worldId = FindChanByName("world","World","WORLD") or
              FallbackFind(function(n) return n=="world" end)
    if not worldId then
      RB_Print("|cffff6666[Tactica]:|r You are not in |cffffff00World|r. Use |cffffff00/join world|r.")
    end
  end
  if chLFG then
    lfgId = FindChanByName("LookingForGroup","lookingforgroup","LFG","lfg") or
            FallbackFind(function(n) return n=="lfg" or n=="lookingforgroup" or n=="looking for group" end)
    if not lfgId then
      RB_Print("|cffff6666[Tactica]:|r You are not in |cffffff00LookingForGroup|r. Use |cffffff00/join LookingForGroup|r.")
    end
  end

  local sent = false
  if worldId then SendChatMessage(msg, "CHANNEL", nil, worldId); sent = true end
  if lfgId   then SendChatMessage(msg, "CHANNEL", nil, lfgId);   sent = true end
  if chYell  then SendChatMessage(msg, "YELL");                  sent = true end
  if not sent then RB_Print("|cff33ff99[Tactica]:|r " .. msg) end
end

-------------------------------------------------
-- Unassigned detection + delayed nudge
-------------------------------------------------
local function RB_RaidCount()
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  return n
end

local function RB_GetUnassignedCount()
  local rosterSet, inRaid = RB_RaidRosterSet()
  if inRaid <= 0 then return 0 end

  local T = (TacticaDB and TacticaDB.Tanks)   or {}
  local H = (TacticaDB and TacticaDB.Healers) or {}
  local D = (TacticaDB and TacticaDB.DPS)     or {}

  local assigned = 0
  local name
  for name,_ in pairs(rosterSet) do
    if T[name] or H[name] or D[name] then assigned = assigned + 1 end
  end

  local unassigned = inRaid - assigned
  if unassigned < 0 then unassigned = 0 end
  return unassigned
end

local function RB_NudgeAssignRoles(unassigned)
  if not unassigned or unassigned <= 0 then return end
  local msg = "|cffffd100[Tactica]:|r You have |cffffff00" .. unassigned ..
              "|r unassigned group members. Assign Tank/Healer/DPS in the Raid Roster (Right-click a player to Set Role)."
  RB_After(1, function() RB_Print(msg) end)
end

-------------------------------------------------
-- Save/restore frame position
-------------------------------------------------
local function SaveFramePosition()
  if not RB.frame then return end
  EnsureDB()
  local point, _, relativePoint, x, y = RB.frame:GetPoint()
  TacticaDB.BuilderFrame.position = {
    point = point, relativeTo = "UIParent", relativePoint = relativePoint, x = x, y = y,
  }
  TacticaDB.BuilderFrame.locked = RB.frame.locked and true or false
end
local function ApplyLockIcon()
  if not RB.lockButton then return end
  if RB.frame and RB.frame.locked then
    RB.lockButton:SetNormalTexture("Interface\\AddOns\\Tactica\\Media\\tactica-lock")
  else
    RB.lockButton:SetNormalTexture("Interface\\AddOns\\Tactica\\Media\\tactica-unlock")
  end
end
local function RestoreFramePosition()
  if not RB.frame then return end
  EnsureDB()
  local st = TacticaDB.BuilderFrame or {}
  local p  = st.position or {}
  RB.frame:ClearAllPoints()
  if p.point then
    RB.frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
  else
    RB.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  RB.frame.locked = (st.locked == true)
  ApplyLockIcon()
end

-------------------------------------------------
-- State load/save & preview
-------------------------------------------------
function RB.ApplySaved()
  EnsureDB()
  local S  = TacticaDB.Builder
  RB.state = RB.state or {}

  RB.state.raid        = S.raid        or nil
  RB.state.worldBoss   = S.worldBoss   or nil
  RB.state.esMode      = S.esMode      or nil
  RB.state.customRaidText = S.customRaidText or ""
  RB.state.size        = S.size        or nil
  RB.state.size_selected = (RB.state.size ~= nil)
  RB.state.gearScale = S.gearScale
  RB.state.autoGear  = S.autoGear and true or false

  local d = {}
  if RB.state.raid and RB.state.size then
    d = ComputeDefaults(RB.state.raid, RB.state.size, RB.state.esMode) or {}
  end

  if S.tanks ~= nil then RB.state.tanks = S.tanks
  elseif RB.state.size_selected then RB.state.tanks = d.tanks else RB.state.tanks = nil end

  if S.healers ~= nil then RB.state.healers = S.healers
  elseif RB.state.size_selected then RB.state.healers = d.healers else RB.state.healers = nil end

  RB.state.srs      = (S.srs ~= nil) and S.srs or (d.srs or 0)
  RB.state.hr       = S.hr    or ""
  RB.state.free     = S.free  or ""
  RB.state.canSum   = S.canSum and true or false
  RB.state.hideNeed = S.hideNeed and true or false

  RB.state.chWorld  = S.chWorld and true or false
  RB.state.chLFG    = S.chLFG   and true or false
  RB.state.chYell  = S.chYell  and true or false
  RB.state.aiAutoRoles  = S.aiAutoRoles  and true or false
  RB.state.aiAutoInvite = S.aiAutoInvite and true or false
  RB.state.interval = (S.interval == 60 or S.interval == 120 or S.interval == 300) and S.interval or 120

  RB.state.auto     = false
  RB.state.running  = false
  RB._warnOk        = false
  RB._nextSend      = nil

  -- SR link is session-only; Discord link is not saved in Builder (only in presets)
  RB.state.srLink = ""
  RB.state.discordLink = RB.state.discordLink or ""
end

function RB.SaveState()
  local S = Saved()
  local st = RB.state
  S.raid, S.worldBoss, S.esMode = st.raid, st.worldBoss, st.esMode
  S.customRaidText = st.customRaidText or ""
  S.size = st.size
  S.tanks, S.healers, S.srs = st.tanks, st.healers, st.srs
  S.hr, S.free = st.hr, st.free
  S.canSum = st.canSum
  S.hideNeed = st.hideNeed
  S.chWorld, S.chLFG, S.chYell = st.chWorld, st.chLFG, st.chYell
  S.auto, S.interval = st.auto, st.interval
  S.gearScale = st.gearScale
  S.autoGear  = st.autoGear
  S.aiAutoRoles  = st.aiAutoRoles  and true or false
  S.aiAutoInvite = st.aiAutoInvite and true or false
end

local function RequirementsComplete()
  local full, _ = EffectiveRaidNameAndLabel()
  if not full then return false end
  if not RB.state.size_selected then return false end
  if not RB.state.tanks or not RB.state.healers then return false end
  return true
end

function RB.RefreshPreview()
  if not RB.lblPreview then return end
  local canAnnounce = RequirementsComplete()
  if RB.btnAnnounce then
    if canAnnounce then RB.btnAnnounce:Enable(); RB.btnAnnounce:SetAlpha(1.0)
    else RB.btnAnnounce:Disable(); RB.btnAnnounce:SetAlpha(0.5) end
    if not canAnnounce and not RB.state.running then RB.btnAnnounce:SetText("Announce") end
  end
  if not canAnnounce then
    RB.lblPreview:SetText("|cff33ff99Preview:|r ")
  else
    local _, shortForMsg = EffectiveRaidNameAndLabel()
    local msg = BuildLFM(shortForMsg, RB.state.size, RB.state.tanks, RB.state.healers, RB.state.srs, RB.state.hr, RB.state.canSum, RB.state.free, RB.state.hideNeed)
    RB.lblPreview:SetText("|cff33ff99Preview:|r " .. msg .. " |cff999999(" .. string.len(msg) .. "/255)|r")
  end

  if RB.lblNotes then
    if RB.state.raid and RB.state.size_selected then
      local body = CompositionText(RB.state.raid, RB.state.size)
      if body ~= "" then
        RB.lblNotes:SetText("|cffffd100Suggested raid composition:|r |cff999999" .. body .. "|r")
        RB.lblNotes:Show()
      else
        RB.lblNotes:SetText(""); RB.lblNotes:Hide()
      end
    else
      RB.lblNotes:SetText(""); RB.lblNotes:Hide()
    end
  end
end

function RB.UpdateButtonsForRunning()
  if RB.state.running then
    if RB.btnAnnounce then RB.btnAnnounce:SetText("Stop") end
    if RB.btnClose then RB.btnClose:Disable(); RB.btnClose:SetAlpha(0.5) end
  else
    if RB.btnAnnounce then RB.btnAnnounce:SetText("Announce") end
    if RB.btnClose then RB.btnClose:Enable();  RB.btnClose:SetAlpha(1.0) end
    RB._nextSend = nil
  end
end

-------------------------------------------------
-- Auto-Invite wiring (RB -> TacticaInvite)
-------------------------------------------------
local function RB_SetInvitePlaceholder(on)
  RB._invPlaceholder = on and true or false
  if not RB.editInviteKW then return end
  if on then
    RB.editInviteKW:SetText("Keyword")
    if RB.editInviteKW.SetTextColor then RB.editInviteKW:SetTextColor(0.7,0.7,0.7) end
  else
    if RB.editInviteKW:GetText()=="Keyword" then RB.editInviteKW:SetText("") end
    if RB.editInviteKW.SetTextColor then RB.editInviteKW:SetTextColor(1,1,1) end
  end
end

local function RB_AutoInviteUpdateFromUI(source)
  local enabled   = RB.cbAutoInvite and RB.cbAutoInvite:GetChecked() and true or false
  local autoRoles = RB.cbRoleAssign and RB.cbRoleAssign:GetChecked() and true or false

  -- sync to invite module (RB intent mode, no keyword)
  if TacticaInvite and TacticaInvite.SetFromRB then
    TacticaInvite.SetFromRB(enabled, "", autoRoles)
  end

  -- self-messages: only for the one that changed
  local cf = DEFAULT_CHAT_FRAME or ChatFrame1
  if cf then
    if (enabled ~= RB._aiEnabledLast) and (source == "autoInvite" or source == nil) then
      cf:AddMessage("|cff33ff99[Tactica]:|r Auto-Invite " ..
        (enabled and "|cff00ff00ENABLED|r" or "|cffff5555DISABLED|r") .. " (Raid Builder).")
    end
    if (autoRoles ~= RB._aiAutoRolesLast) and (source == "autoRoles" or source == nil) then
      cf:AddMessage("|cff33ff99[Tactica]:|r Auto-Assign roles " ..
        (autoRoles and "|cff00ff00ENABLED|r" or "|cffff5555DISABLED|r") .. " (Raid Builder).")
    end
  end

  RB._aiEnabledLast     = enabled and true or false
  RB._aiAutoRolesLast   = autoRoles and true or false
end

local function RB_SyncInviteExtras()
  if TacticaInvite and TacticaInvite.SetGearcheckFromRB then
    TacticaInvite.SetGearcheckFromRB(RB.state.autoGear and true or false, RB.state.gearScale)
  end
end

-------------------------------------------------
-- Dropdowns
-------------------------------------------------
local function InitNumberDropdown(drop, label, fromN, toN, assign)
  UIDropDownMenu_Initialize(drop, function()
    if not RB.state.size_selected or not RB.state.raid then
      UIDropDownMenu_AddButton({ text="Select Size first", notClickable=1, isTitle=1 })
      return
    end
    local d = ComputeDefaults(RB.state.raid, RB.state.size, RB.state.esMode)
    local sug = (label=="Tanks" and d.tanks) or (label=="Healers" and d.healers) or d.srs
    UIDropDownMenu_AddButton({ text="Suggested: "..sug, notClickable=1, isTitle=1 })
    local n
    for n=fromN,toN do
      local info = {}
      info.text=tostring(n); info.value=n
      info.func=function()
        local picked = this and this.value or n
        assign(picked)
        UIDropDownMenu_SetText(picked .. " " .. label, drop)
        RB.SaveState(); RB.RefreshPreview(); CloseDropDownMenus()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
end

function RB.InitRaidDropdown()
  UIDropDownMenu_Initialize(RB.ddRaid, function()
    local raids = {}
    local rn
    for rn,_ in pairs(Tactica and Tactica.DefaultData or {}) do table.insert(raids, rn) end
    table.sort(raids)

    -- Always put "-CUSTOM-" at the top (all caps)
    table.insert(raids, 1, "-CUSTOM-")

    local i
    for i=1,table.getn(raids) do
      local raidName = raids[i]
      local info = {}
      info.text = raidName; info.value = raidName
      info.func = function()
        local picked = this and this.value or raidName
        RB.state.raid = picked
        RB.state.worldBoss = nil
        RB.state.esMode = nil

        -- Reset selection state
        RB.state.size = nil; RB.state.size_selected = false
        RB.state.tanks, RB.state.healers = nil, nil

        -- For CUSTOM: do not default SR either
        if picked == "-CUSTOM-" then
          RB.state.srs = nil
          -- keep customRaidText as-is; user can type / edit
        else
          RB.state.srs = 0
        end

        -- Show/hide side dropdowns and custom editbox
        if picked == "World Bosses" then
          RB.ddWBoss:Show(); RB.ddESMode:Hide()
          if RB.editCustomRaid then RB.editCustomRaid:Hide() end
          if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Hide() end
        elseif picked == "Emerald Sanctum" then
          RB.ddESMode:Show(); RB.ddWBoss:Hide()
          if RB.editCustomRaid then RB.editCustomRaid:Hide() end
          if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Hide() end
        elseif picked == "-CUSTOM-" then
          RB.ddWBoss:Hide(); RB.ddESMode:Hide()
          if RB.editCustomRaid then RB.editCustomRaid:Show() end
          if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Show() end
        else
          RB.ddWBoss:Hide(); RB.ddESMode:Hide()
          if RB.editCustomRaid then RB.editCustomRaid:Hide() end
          if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Hide() end
        end

        UIDropDownMenu_SetSelectedValue(RB.ddRaid, picked)
        UIDropDownMenu_SetText(picked, RB.ddRaid)

        UIDropDownMenu_SetText("Select Size", RB.ddSize); if RB.editCustomSize then RB.editCustomSize:Hide() end
        UIDropDownMenu_SetText("Pick Size first", RB.ddTanks)
        UIDropDownMenu_SetText("Pick Size first", RB.ddHealers)
        UIDropDownMenu_SetText("Pick Size first", RB.ddSRs)

        RB.SaveState(); RB.RefreshPreview(); CloseDropDownMenus()
        RB.InitSizeDropdown()
        RB.InitGearScaleDropdown()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)

  if RB.state.raid then
    UIDropDownMenu_SetSelectedValue(RB.ddRaid, RB.state.raid)
    UIDropDownMenu_SetText(RB.state.raid, RB.ddRaid)
  else
    UIDropDownMenu_SetText("Select Raid", RB.ddRaid)
  end
end

function RB.InitWBossDropdown()
  UIDropDownMenu_Initialize(RB.ddWBoss, function()
    local bosses, wb = {}, Tactica and Tactica.DefaultData and Tactica.DefaultData["World Bosses"]
    if wb then
      local bossName
      for bossName,_ in pairs(wb) do table.insert(bosses, bossName) end
      table.sort(bosses)
    end
    local i
    for i=1,table.getn(bosses) do
      local nm = bosses[i]
      local info = {}
      info.text=nm; info.value=nm
      info.func=function()
        local picked = this and this.value or nm
        RB.state.worldBoss = picked
        UIDropDownMenu_SetSelectedValue(RB.ddWBoss, picked)
        UIDropDownMenu_SetText(picked, RB.ddWBoss)
        RB.SaveState(); RB.RefreshPreview(); CloseDropDownMenus()
        RB.InitGearScaleDropdown()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  if RB.state.worldBoss then
    UIDropDownMenu_SetSelectedValue(RB.ddWBoss, RB.state.worldBoss)
    UIDropDownMenu_SetText(RB.state.worldBoss, RB.ddWBoss)
  else
    UIDropDownMenu_SetText("Pick Boss", RB.ddWBoss)
  end
end

function RB.InitESModeDropdown()
  UIDropDownMenu_Initialize(RB.ddESMode, function()
    local function add(label, val)
      local info = {}
      info.text  = label
      info.value = val
      info.func  = function()
        local picked = this and this.value or val
        RB.state.esMode = picked
        UIDropDownMenu_SetSelectedValue(RB.ddESMode, picked)
        UIDropDownMenu_SetText(picked, RB.ddESMode)

        if RB.state.size_selected and RB.state.raid then
          local d = ComputeDefaults(RB.state.raid, RB.state.size, RB.state.esMode)
          RB.state.tanks   = d.tanks
          RB.state.healers = d.healers
          RB.state.srs     = d.srs
          UIDropDownMenu_SetText(RB.state.tanks   .. " Tanks",   RB.ddTanks)
          UIDropDownMenu_SetText(RB.state.healers .. " Healers", RB.ddHealers)
          UIDropDownMenu_SetText(RB.state.srs     .. " SR",      RB.ddSRs)
        end
        RB.SaveState(); RB.RefreshPreview(); CloseDropDownMenus()
        RB.InitGearScaleDropdown()
      end
      UIDropDownMenu_AddButton(info)
    end
    add("Normal", "Normal")
    add("Hard Mode", "HM")
  end)
  if RB.state.esMode then
    UIDropDownMenu_SetSelectedValue(RB.ddESMode, RB.state.esMode)
    UIDropDownMenu_SetText(RB.state.esMode, RB.ddESMode)
    if RB.state.size_selected and RB.state.raid then
      local d = ComputeDefaults(RB.state.raid, RB.state.size, RB.state.esMode)
      RB.state.tanks   = d.tanks
      RB.state.healers = d.healers
      RB.state.srs     = d.srs
      UIDropDownMenu_SetText(RB.state.tanks   .. " Tanks",   RB.ddTanks)
      UIDropDownMenu_SetText(RB.state.healers .. " Healers", RB.ddHealers)
      UIDropDownMenu_SetText(RB.state.srs     .. " SR",      RB.ddSRs)
    end
  else
    UIDropDownMenu_SetText("Select Mode", RB.ddESMode)
  end
end

function RB.InitSizeDropdown()
  UIDropDownMenu_Initialize(RB.ddSize, function()
    if not RB.state.raid then
      UIDropDownMenu_AddButton({ text="Select Raid first", notClickable=1, isTitle=1 })
      return
    end

    -- CUSTOM raid: allow ALL sizes regardless of AllowedSizes
    local list
    if RB.state.raid == "-CUSTOM-" then
      list = ALL_SIZES
    else
      list = AllowedSizes[RB.state.raid] or ALL_SIZES
    end

    local i
    for i=1,table.getn(list) do
      local n = list[i]
      local info = {}
      info.text=tostring(n); info.value=n
      info.func=function()
        local picked = this and this.value or n
        RB.state.size = picked; RB.state.size_selected = true

        if RB.state.raid == "-CUSTOM-" then
          -- Do NOT default-select tanks/healers/SRs for custom raids
          RB.state.tanks, RB.state.healers, RB.state.srs = nil, nil, nil
          UIDropDownMenu_SetSelectedValue(RB.ddSize, picked)
          UIDropDownMenu_SetText(tostring(RB.state.size), RB.ddSize)
          UIDropDownMenu_SetText("Pick Tanks", RB.ddTanks)
          UIDropDownMenu_SetText("Pick Healers", RB.ddHealers)
          UIDropDownMenu_SetText("Pick SR", RB.ddSRs)
        else
          local d = ComputeDefaults(RB.state.raid, RB.state.size, RB.state.esMode)
          RB.state.tanks, RB.state.healers, RB.state.srs = d.tanks, d.healers, d.srs
          UIDropDownMenu_SetSelectedValue(RB.ddSize, picked)
          UIDropDownMenu_SetText(tostring(RB.state.size), RB.ddSize)
          UIDropDownMenu_SetText(RB.state.tanks .. " Tanks", RB.ddTanks)
          UIDropDownMenu_SetText(RB.state.healers .. " Healers", RB.ddHealers)
          UIDropDownMenu_SetText(RB.state.srs .. " SR", RB.ddSRs)
        end

        if RB.editCustomSize then RB.editCustomSize:Hide() end
        RB.SaveState(); RB.RefreshPreview(); CloseDropDownMenus()
      end
      UIDropDownMenu_AddButton(info)
    end

    UIDropDownMenu_AddButton({
      text = "Custom size",
      value = "custom",
      func = function()
        UIDropDownMenu_SetSelectedValue(RB.ddSize, "custom")
        UIDropDownMenu_SetText("Custom size", RB.ddSize)
        CloseDropDownMenus()
        if RB.editCustomSize then
          RB.editCustomSize:SetText("")
          RB.editCustomSize:Show()
          RB.editCustomSize:SetFocus()
        end
      end
    })
  end)

  if RB.state.size_selected and RB.state.size then
    local list
    if RB.state.raid == "-CUSTOM-" then
      list = ALL_SIZES
    else
      list = AllowedSizes[RB.state.raid] or ALL_SIZES
    end
    local isAllowed = false
    local i
    for i=1,table.getn(list) do if list[i] == RB.state.size then isAllowed = true; break end end
    UIDropDownMenu_SetSelectedValue(RB.ddSize, isAllowed and RB.state.size or "custom")
    UIDropDownMenu_SetText(tostring(RB.state.size), RB.ddSize)
  else
    UIDropDownMenu_SetText("Select Size", RB.ddSize)
    if RB.editCustomSize then RB.editCustomSize:Hide() end
  end
end

-------------------------------------------------
-- Auto announce loop & roster changes
-------------------------------------------------
local function RB_CheckAndStopIfFull()
  if not RB.state or not RB.state.running then return false end
  local target = RB.state.size
  if not target or target <= 0 then return false end

  local needM = 0
  do
    local headNeed = BuildNeedString(RB.state.size, RB.state.tanks, RB.state.healers, RB.state.hideNeed)
    if type(headNeed) == "table" then
      needM = headNeed[1] or 0
    else
      needM = headNeed or 0
    end
  end

  if needM <= 0 then
    RB.state.running = false
    RB.state.auto    = false
    RB._warnOk       = false
    RB._nextSend     = nil
    if RB.cbAuto then RB.cbAuto:SetChecked(false) end
    RB.SaveState()
    RB.UpdateButtonsForRunning()
    local inRaid = RB_RaidCount()
    RB_Print("|cff33ff99[Tactica]:|r Auto-announce disabled: raid is full ("..inRaid.."/"..(target or "?")..") based on current needs. Assign roles in the Raid Roster for accuracy.")
    return true
  end
  return false
end

RB._dirty, RB._lastSend, RB._nextSend = false, 0, nil
RB._poll = RB._poll or CreateFrame("Frame")
RB._poll:SetScript("OnUpdate", function()
  if RB_CheckAndStopIfFull() then return end
  if not RB.state.running then return end
  local now = GetTime and GetTime() or 0
  local gap = RB.state.interval or 120

  if RB._nudgeAt and now >= RB._nudgeAt then
    RB._nudgeAt = nil
    local ua = RB_GetUnassignedCount()
    if ua > 0 then RB_NudgeAssignRoles(ua) end
  end

  if not RB._nextSend then
    RB._nextSend = now + gap
  end

  if now >= RB._nextSend then
    local _, short = EffectiveRaidNameAndLabel()
    if short then
      local msg = BuildLFM(short, RB.state.size, RB.state.tanks, RB.state.healers, RB.state.srs, RB.state.hr, RB.state.canSum, RB.state.free, RB.state.hideNeed)
      Announce(msg, false, RB.state.chWorld, RB.state.chLFG, RB.state.chYell)
      RB._lastSend = now
      RB._nextSend = now + gap
    end
  end
end)

RB._evt = RB._evt or CreateFrame("Frame")
RB._evt:RegisterEvent("RAID_ROSTER_UPDATE")
RB._evt:RegisterEvent("GROUP_ROSTER_UPDATE")
RB._evt:RegisterEvent("PLAYER_ENTERING_WORLD")
RB._evt:SetScript("OnEvent", function()
  local ev = event
  if ev == "PLAYER_ENTERING_WORLD" then
    RB.state.running = false; RB._warnOk = false; RB._nextSend = nil; RB.UpdateButtonsForRunning()
  else
    if RB_CheckAndStopIfFull() then return end
    RB._dirty = true
    RB.RefreshPreview()

    if RB.UpdateSRDPostState then RB.UpdateSRDPostState() end

    if (ev == "RAID_ROSTER_UPDATE" or ev == "GROUP_ROSTER_UPDATE") and RB.state.auto and RB.state.running then
      local inRaid = RB_RaidCount()
      if inRaid > (RB._lastRaidCount or 0) then
        RB._nudgeAt = (GetTime and GetTime() or 0) + 10
      end
      RB._lastRaidCount = inRaid
    end
  end
end)

-------------------------------------------------
-- Confirmation popup (Auto-Announce)
-------------------------------------------------
local function ShowAutoConfirm()
  if RB._confirm then RB._confirm:Show(); return end
  local parent = RB.frame or UIParent
  local wf = CreateFrame("Frame", "TacticaRBAutoConfirm", parent)
  RB._confirm = wf
  wf:SetWidth(360); wf:SetHeight(140)
  wf:SetPoint("CENTER", parent, "CENTER", 0, 0)
  wf:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left=11, right=12, top=12, bottom=11 }
  })
  wf:SetBackdropColor(0, 0, 0, 1)
  wf:SetBackdropBorderColor(1, 1, 1, 1)
  wf:SetFrameStrata("FULLSCREEN_DIALOG")
  wf:EnableMouse(true)

  local h = wf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetPoint("TOP", wf, "TOP", 0, -12)
  h:SetText("|cffff2020Warning:|r")

  local b = wf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b:SetPoint("TOPLEFT", wf, "TOPLEFT", 18, -36)
  b:SetWidth(320); b:SetJustifyH("LEFT")
  b:SetText("You have selected to auto-announce. Therefore, you can not close the Tactica Raid Builder window, until you stop auto-announcing. USE RESPECTFULLY!")

  local btnAgree = CreateFrame("Button", nil, wf, "UIPanelButtonTemplate")
  btnAgree:SetWidth(100); btnAgree:SetHeight(22)
  btnAgree:SetPoint("BOTTOMRIGHT", wf, "BOTTOMRIGHT", -14, 12)
  btnAgree:SetText("I agree")
  btnAgree:SetScript("OnClick", function()
    RB._warnOk = true
    wf:Hide()
    RB.state.running = true
    RB.SaveState()
    RB.UpdateButtonsForRunning()

    local _, short = EffectiveRaidNameAndLabel()
    if short then
      local msg = BuildLFM(short, RB.state.size, RB.state.tanks, RB.state.healers, RB.state.srs, RB.state.hr, RB.state.canSum, RB.state.free, RB.state.hideNeed)
      Announce(msg, false, RB.state.chWorld, RB.state.chLFG, RB.state.chYell)
      local now = GetTime and GetTime() or 0
      RB._lastSend = now
      RB._nextSend = now + (RB.state.interval or 120)
      local ua = RB_GetUnassignedCount()
      if ua > 0 then RB_NudgeAssignRoles(ua) end
    end
  end)

  local btnNo = CreateFrame("Button", nil, wf, "UIPanelButtonTemplate")
  btnNo:SetWidth(120); btnNo:SetHeight(22)
  btnNo:SetPoint("BOTTOMLEFT", wf, "BOTTOMLEFT", 14, 12)
  btnNo:SetText("I don't agree")
  btnNo:SetScript("OnClick", function()
    wf:Hide()
    RB.state.auto = false
    if RB.cbAuto then RB.cbAuto:SetChecked(false) end
    RB._warnOk = false
    RB.state.running = false
    RB._nextSend = nil
    RB.SaveState()
    RB.UpdateButtonsForRunning()
  end)
end

-------------------------------------------------
-- Button handlers
-------------------------------------------------
local function OnCloseClick()
  if RB.state.running then RB_Print("|cffff6666[Tactica]:|r Stop auto-announce before closing."); return end
  RB.frame:Hide()
end

local function OnLockClick()
  RB.frame.locked = not RB.frame.locked
  ApplyLockIcon()
  if GameTooltip and GetMouseFocus and GetMouseFocus()==RB.lockButton then
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(RB.lockButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine(RB.frame.locked and "Locked" or "Unlocked", 1,1,1)
    GameTooltip:AddLine("Click to toggle", 0.9,0.9,0.9)
    GameTooltip:Show()
  end
  SaveFramePosition()
end

local function OnEditHRChanged()   RB.state.hr   = this:GetText() or ""; RB.SaveState(); RB.RefreshPreview() end
local function OnEditFreeChanged() RB.state.free = this:GetText() or ""; RB.SaveState(); RB.RefreshPreview() end
local function OnCanSumClick()     RB.state.canSum = this:GetChecked() and true or false; RB.SaveState(); RB.RefreshPreview() end
local function OnHideNeedClick()   RB.state.hideNeed = this:GetChecked() and true or false; RB.SaveState(); RB.RefreshPreview() end
local function OnAutoClick()       RB.state.auto   = this:GetChecked() and true or false; RB._warnOk=false; RB.SaveState(); RB.UpdateButtonsForRunning() end

local function OnAnnounceClick()
  if RB.state.running then
    RB.state.running = false
    RB._nextSend = nil
    RB.SaveState()
    RB.UpdateButtonsForRunning()
    return
  end
  if not RequirementsComplete() then
    RB_Print("|cffff6666[Tactica]:|r Pick raid (and World Boss / ES mode), size, tanks and healers first.")
    return
  end

  if RB.state.auto then
    if not RB._warnOk then ShowAutoConfirm(); return end
    RB.state.running = true
    RB.SaveState()
    RB.UpdateButtonsForRunning()
    local _, short = EffectiveRaidNameAndLabel()
    if short then
      local msg = BuildLFM(short, RB.state.size, RB.state.tanks, RB.state.healers, RB.state.srs, RB.state.hr, RB.state.canSum, RB.state.free, RB.state.hideNeed)
      Announce(msg, false, RB.state.chWorld, RB.state.chLFG, RB.state.chYell)
      local now = GetTime and GetTime() or 0
      RB._lastSend = now
      RB._nextSend = now + (RB.state.interval or 120)
      local ua = RB_GetUnassignedCount()
      if ua > 0 then RB_NudgeAssignRoles(ua) end
    end
    return
  end

  local now = GetTime and GetTime() or 0
  local elapsed = now - (RB._lastManual or 0)
  local COOLDOWN = 30
  if elapsed < COOLDOWN then
    local left = math.floor(COOLDOWN - elapsed + 0.5)
    RB_Print("|cffff6666[Tactica]:|r Announce is on cooldown ("..left.."s).")
    return
  end

  local _, short = EffectiveRaidNameAndLabel()
  local msg = BuildLFM(short, RB.state.size, RB.state.tanks, RB.state.healers, RB.state.srs, RB.state.hr, RB.state.canSum, RB.state.free, RB.state.hideNeed)
  Announce(msg, false, RB.state.chWorld, RB.state.chLFG, RB.state.chYell)
  RB._lastManual = now

  local ua = RB_GetUnassignedCount()
  if ua > 0 then RB_NudgeAssignRoles(ua) end
end

-------------------------------------------------
-- Slash: /ttlfm -> post once (30s cooldown)
-------------------------------------------------
function TacticaRaidBuilder.AnnounceOnce()
  local RBm = TacticaRaidBuilder
  if not RBm then return end
  if RBm.ApplySaved then RBm.ApplySaved() end

  local function ReqOK()
    local full,_ = EffectiveRaidNameAndLabel()
    if not full then return false end
    if not RBm.state or not RBm.state.size_selected then return false end
    if not RBm.state.tanks or not RBm.state.healers then return false end
    return true
  end

  if not ReqOK() then
    local cf = DEFAULT_CHAT_FRAME or ChatFrame1
    if cf then cf:AddMessage("|cffff6666[Tactica]:|r Pick raid (and World Boss / ES mode), size, tanks and healers first.") end
    return
  end

  local now = GetTime and GetTime() or 0
  local elapsed = now - (RBm._lastManual or 0)
  local COOLDOWN = 30
  if elapsed < COOLDOWN then
    local left = math.floor(COOLDOWN - elapsed + 0.5)
    local cf = DEFAULT_CHAT_FRAME or ChatFrame1
    if cf then cf:AddMessage("|cffff6666[Tactica]:|r Announce is on cooldown ("..left.."s).") end
    return
  end

  local _, short = EffectiveRaidNameAndLabel()
  if not short then return end
  local msg = BuildLFM(short, RBm.state.size, RBm.state.tanks, RBm.state.healers, RBm.state.srs, RBm.state.hr, RBm.state.canSum, RBm.state.free, RBm.state.hideNeed)
  Announce(msg, false, RBm.state.chWorld, RBm.state.chLFG, RBm.state.chYell)
  RBm._lastManual = now

  local ua = RB_GetUnassignedCount()
  if ua > 0 then RB_NudgeAssignRoles(ua) end
end

-------------------------------------------------
-- Self-preview & Clear
-------------------------------------------------
local function OnSelfClick()
  local label
  local _, short = EffectiveRaidNameAndLabel()
  if RequirementsComplete() then label = short else label = RB.state.raid or "Select Raid" end
  local msg = BuildLFM(label, RB.state.size or 40, RB.state.tanks or 0, RB.state.healers or 0, RB.state.srs or 0, RB.state.hr, RB.state.canSum, RB.state.free, RB.state.hideNeed)
  Announce(msg, true, false, false, false)
end

local function OnClearClick()
  TacticaDB.Builder = {}
  RB.ApplySaved()

  RB.state.customRaidText = ""
  if RB.editCustomRaid then
    RB.editCustomRaid:SetText("")
    RB.editCustomRaid:Hide()
  end
  if RB.lblCustomRaidHint then
    RB.lblCustomRaidHint:Hide()
  end
  if RB.ddWBoss then RB.ddWBoss:Hide() end
  if RB.ddESMode then RB.ddESMode:Hide() end

  UIDropDownMenu_SetText(RB.state.raid or "Select Raid", RB.ddRaid)
  UIDropDownMenu_SetText("Select Size", RB.ddSize); if RB.editCustomSize then RB.editCustomSize:Hide() end
  UIDropDownMenu_SetText("Pick Size first", RB.ddTanks)
  UIDropDownMenu_SetText("Pick Size first", RB.ddHealers)
  UIDropDownMenu_SetText("0 SR", RB.ddSRs)
  UIDropDownMenu_SetText(RB.state.worldBoss or "Pick Boss", RB.ddWBoss)
  UIDropDownMenu_SetText(RB.state.esMode or "Select Mode", RB.ddESMode)

  RB.cbWorld:SetChecked(RB.state.chWorld)
  RB.cbLFG:SetChecked(RB.state.chLFG)
  RB.cbYell:SetChecked(RB.state.chYell)

  -- STOP AUTO-ANNOUNCE (must keep this)
  if RB.cbAuto then RB.cbAuto:SetChecked(false) end
  RB.state.auto = false
  RB.state.running = false
  RB._warnOk = false
  RB._nextSend = nil
  RB.UpdateButtonsForRunning()

  -- STOP AUTO-INVITE and AUTO-ASSIGN ROLES
  if RB.cbAutoInvite then RB.cbAutoInvite:SetChecked(false) end
  if RB.cbRoleAssign then RB.cbRoleAssign:SetChecked(false) end
  RB.state.aiAutoRoles  = false
  RB.state.aiAutoInvite = false
  RB_AutoInviteUpdateFromUI("clear")

  RB.cbCanSum:SetChecked(RB.state.canSum)
  if RB.cbHideNeed then RB.cbHideNeed:SetChecked(RB.state.hideNeed) end
  RB.editHR:SetText(RB.state.hr or "")
  RB.editFree:SetText(RB.state.free or "")

  -- Reset Gearcheck UI and state
  RB.state.gearScale = nil
  RB.state.autoGear = false
  if RB.cbGear then RB.cbGear:SetChecked(false) end
  if RB.ddGearScale then UIDropDownMenu_SetText("Required Gear", RB.ddGearScale) end
  if RB.InitGearScaleDropdown then RB.InitGearScaleDropdown() end

  -- Clear SR & Discord fields (session)
  RB.state.srLink = ""
  RB.state.discordLink = ""
  if RB.editSRLink then RB.editSRLink:SetText("") end
  if RB.editDiscordLink then RB.editDiscordLink:SetText("") end
  if RB.UpdateSRDPostState then RB.UpdateSRDPostState() end

  RB.SaveState()
  RB.RefreshPreview()
  RB_SyncInviteExtras()
end

-------------------------------------------------
-- Open UI
-------------------------------------------------
local function RaidRosterHotkey()
  if not GetBindingKey then return "unbound" end
  local actions = { "TOGGLERAIDTAB", "TOGGLERAIDPANEL", "TOGGLERAIDFRAME" }
  local i
  for i=1,table.getn(actions) do
    local k1, k2 = GetBindingKey(actions[i])
    local key = k1 or k2
    if key and key ~= "" then
      if GetBindingText then return GetBindingText(key, "KEY_") else return key end
    end
  end
  return "unbound"
end

local function OpenRaidPanel()
  if LoadAddOn and not IsAddOnLoaded("Blizzard_RaidUI") then LoadAddOn("Blizzard_RaidUI") end
  if ToggleFriendsFrame then
    ToggleFriendsFrame()
    if FriendsFrame_ShowSubFrame then FriendsFrame_ShowSubFrame("RaidFrame") end
  elseif RaidFrame then
    ShowUIPanel(RaidFrame)
  end
end

-- Leader/assist check for SR/Discord Post
local function RB_IsLeaderOrAssist()
  if IsRaidLeader and IsRaidLeader() then return true end
  if IsRaidOfficer and IsRaidOfficer() then return true end
  if IsRaidAssistant and IsRaidAssistant() then return true end
  if IsPartyLeader and IsPartyLeader() then return true end
  return false
end

function RB.Open()
  if RB.frame then RB.frame:Show(); ApplyLockIcon(); RB.RefreshPreview(); RB_SyncInviteExtras(); if RB.UpdateSRDPostState then RB.UpdateSRDPostState() end; return end
  RB.ApplySaved()

  local f = CreateFrame("Frame", "TacticaRaidBuilderFrame", UIParent)
  RB.frame = f
  f:SetWidth(480); f:SetHeight(580)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left=11, right=12, top=12, bottom=11 }
  })
  f:SetBackdropColor(0, 0, 0, 1)
  f:SetBackdropBorderColor(1, 1, 1, 1)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f.locked = false
  f:SetScript("OnDragStart", function() if not f.locked then f:StartMoving() end end)
  f:SetScript("OnDragStop",  function() f:StopMovingOrSizing(); SaveFramePosition() end)
  f:SetScript("OnHide", function()
    RB.state.running=false; RB._warnOk=false; RB._nextSend=nil; RB.UpdateButtonsForRunning()
    if TacticaInvite and TacticaInvite.ResetSessionIgnores then TacticaInvite.ResetSessionIgnores() end
    RB_SyncInviteExtras()
  end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -14)
  title:SetText("|cff33ff99Tactica Raid Builder|r")
  title:SetFontObject(GameFontNormalLarge)

  RB.btnClose = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  RB.btnClose:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
  RB.btnClose:SetScript("OnClick", OnCloseClick)

  RB.lockButton = CreateFrame("Button", "TacticaRBlock", f)
  RB.lockButton:SetWidth(20); RB.lockButton:SetHeight(20)
  RB.lockButton:SetPoint("TOPRIGHT", RB.btnClose, "TOPLEFT", 0, -6)
  RB.lockButton:SetScript("OnClick", OnLockClick)
  RB.lockButton:SetScript("OnEnter", function()
    if GameTooltip then
      GameTooltip:SetOwner(RB.lockButton, "ANCHOR_RIGHT")
      GameTooltip:AddLine(f.locked and "Locked" or "Unlocked", 1,1,1)
      GameTooltip:AddLine("Click to toggle", 0.9,0.9,0.9)
      GameTooltip:Show()
    end
  end)
  RB.lockButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  local lblPreset = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lblPreset:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -42)
  lblPreset:SetText("Preset:")

  RB.editPresetName = CreateFrame("EditBox", "TacticaRBPresetName", f, "InputBoxTemplate")
  RB.editPresetName:SetPoint("LEFT", lblPreset, "RIGHT", 10, 0)
  RB.editPresetName:SetAutoFocus(false); RB.editPresetName:SetWidth(100); RB.editPresetName:SetHeight(18)
  RB.editPresetName:SetMaxLetters(24)

  RB.ddPresetLoad = CreateFrame("Frame", "TacticaRBPresetLoad", f, "UIDropDownMenuTemplate")
  RB.ddPresetLoad:SetPoint("LEFT", RB.editPresetName, "RIGHT", -13, -3)
  UIDropDownMenu_SetWidth(70, RB.ddPresetLoad)

  RB.ddPresetRemove = CreateFrame("Frame", "TacticaRBPresetRemove", f, "UIDropDownMenuTemplate")
  RB.ddPresetRemove:SetPoint("LEFT", RB.ddPresetLoad, "RIGHT", -26, 0)
  UIDropDownMenu_SetWidth(70, RB.ddPresetRemove)

  RB.btnPresetAction = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  RB.btnPresetAction:SetWidth(64); RB.btnPresetAction:SetHeight(20)
  RB.btnPresetAction:SetPoint("LEFT", RB.ddPresetRemove, "RIGHT", -13, 2)

  RB._presetLoadSel, RB._presetRemoveSel = nil, nil

  local function RB_UpdatePresetButtonText()
    local hasName = RB_Trim(RB.editPresetName:GetText() or "") ~= ""
    local list = RB_PresetNamesSorted()
    local any = table.getn(list) > 0
    RB.btnPresetAction:SetText((hasName or not any) and "Save" or "Submit")
  end

  local function InitPresetLoadDD()
    UIDropDownMenu_Initialize(RB.ddPresetLoad, function()
      local names = RB_PresetNamesSorted()
      if table.getn(names) == 0 then
        UIDropDownMenu_AddButton({ text="No presets", notClickable=1, isTitle=1 })
        return
      end
      local i
      for i=1, table.getn(names) do
        local nm = names[i]
        UIDropDownMenu_AddButton({
          text = nm, value = nm,
          func = function()
            RB._presetLoadSel = nm
            RB._presetRemoveSel = nil
            UIDropDownMenu_SetText(nm, RB.ddPresetLoad)
            UIDropDownMenu_SetText("Remove", RB.ddPresetRemove)
            RB.editPresetName:SetText("")
            RB_UpdatePresetButtonText()
            CloseDropDownMenus()
          end
        })
      end
    end)
    UIDropDownMenu_SetText("Load", RB.ddPresetLoad)
  end

  local function InitPresetRemoveDD()
    UIDropDownMenu_Initialize(RB.ddPresetRemove, function()
      local names = RB_PresetNamesSorted()
      if table.getn(names) == 0 then
        UIDropDownMenu_AddButton({ text="No presets", notClickable=1, isTitle=1 })
        return
      end
      local i
      for i=1, table.getn(names) do
        local nm = names[i]
        UIDropDownMenu_AddButton({
          text = nm, value = nm,
          func = function()
            RB._presetRemoveSel = nm
            RB._presetLoadSel = nil
            UIDropDownMenu_SetText(nm, RB.ddPresetRemove)
            UIDropDownMenu_SetText("Load", RB.ddPresetLoad)
            RB.editPresetName:SetText("")
            RB_UpdatePresetButtonText()
            CloseDropDownMenus()
          end
        })
      end
    end)
    UIDropDownMenu_SetText("Remove", RB.ddPresetRemove)
  end

  RB.InitPresetDropdowns = function()
    InitPresetLoadDD()
    InitPresetRemoveDD()
    RB_UpdatePresetButtonText()
  end

  RB.btnPresetAction:SetScript("OnClick", function()
    local name = RB_Trim(RB.editPresetName:GetText() or "")
    if name ~= "" then
      RB.SavePreset(name)
      RB.InitPresetDropdowns()
      return
    end
    if RB._presetLoadSel then
      RB.LoadPreset(RB._presetLoadSel)
      RB._presetLoadSel = nil
      UIDropDownMenu_SetText("Load", RB.ddPresetLoad)
      RB_UpdatePresetButtonText()
      return
    end
    if RB._presetRemoveSel then
      RB.RemovePreset(RB._presetRemoveSel)
      RB._presetRemoveSel = nil
      RB.InitPresetDropdowns()
      return
    end
    RB_Print("|cffff6666[Tactica]:|r Enter a name to Save, or pick a preset to Load/Remove.")
  end)

  RB.editPresetName:SetScript("OnTextChanged", RB_UpdatePresetButtonText)
  RB.editPresetName:SetScript("OnEnterPressed", function() RB.btnPresetAction:Click() end)
  RB.editPresetName:SetScript("OnEscapePressed", function() this:ClearFocus() end)

  -- Section 1 title (green)
  RB.titleRaid = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  RB.titleRaid:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -75)
  RB.titleRaid:SetText("|cff33ff99RAID SETUP|r")

  local sep1 = f:CreateTexture(nil, "ARTWORK")
  sep1:SetHeight(1)
  sep1:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -90)
  sep1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -90)
  sep1:SetTexture(1,1,1); if sep1.SetVertexColor then sep1:SetVertexColor(1,1,1,0.25) end

  local lblRaid = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblRaid:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -101); lblRaid:SetText("Raid:")

  RB.ddRaid = CreateFrame("Frame", "TacticaRBRaid", f, "UIDropDownMenuTemplate")
  RB.ddRaid:SetPoint("TOPLEFT", f, "TOPLEFT", 70, -95); RB.ddRaid:SetWidth(180)
  
  RB.ddWBoss  = CreateFrame("Frame", "TacticaRBWorldBoss", f, "UIDropDownMenuTemplate")
  RB.ddWBoss:SetPoint("LEFT", RB.ddRaid, "RIGHT", -28, 0); RB.ddWBoss:SetWidth(160)
  
  RB.ddESMode = CreateFrame("Frame", "TacticaRBESMode", f, "UIDropDownMenuTemplate")
  RB.ddESMode:SetPoint("LEFT", RB.ddRaid, "RIGHT", -28, 0); RB.ddESMode:SetWidth(160)

  RB.editCustomRaid = CreateFrame("EditBox", "TacticaRBCustomRaidText", f, "InputBoxTemplate")
  RB.editCustomRaid:SetPoint("LEFT", RB.ddRaid, "RIGHT", -10, 3)
  RB.editCustomRaid:SetAutoFocus(false)
  RB.editCustomRaid:SetWidth(120)
  RB.editCustomRaid:SetHeight(20)
  RB.editCustomRaid:SetMaxLetters(40)
  RB.editCustomRaid:SetText(RB.state.customRaidText or "")
  RB.editCustomRaid:Hide()
  
  RB.lblCustomRaidHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RB.lblCustomRaidHint:SetPoint("LEFT", RB.editCustomRaid, "RIGHT", 6, 0)
  RB.lblCustomRaidHint:SetText("(max 40 char)")
  RB.lblCustomRaidHint:Hide()
  
  RB.editCustomRaid:SetScript("OnTextChanged", function()
    RB.state.customRaidText = this:GetText() or ""
    RB.SaveState()
    RB.RefreshPreview()
  end)
  RB.editCustomRaid:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  RB.editCustomRaid:SetScript("OnEnterPressed", function() this:ClearFocus() end)


  local lblSize = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblSize:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -135); lblSize:SetText("Size:")

  RB.ddSize = CreateFrame("Frame", "TacticaRBSize", f, "UIDropDownMenuTemplate")

  RB.editCustomSize = CreateFrame("EditBox", "TacticaRBCustomSize", f, "InputBoxTemplate")
  RB.editCustomSize:SetPoint("LEFT", RB.ddSize, "RIGHT", 85, 3)
  RB.editCustomSize:SetAutoFocus(true); RB.editCustomSize:SetWidth(100); RB.editCustomSize:SetHeight(20)
  if RB.editCustomSize.SetNumeric then RB.editCustomSize:SetNumeric(true) end
  RB.editCustomSize:Hide()
  RB.editCustomSize:SetScript("OnEscapePressed", function() this:ClearFocus(); this:Hide() end)
  RB.editCustomSize:SetScript("OnEnterPressed", function()
    local txt = this:GetText() or ""
    local n = tonumber(txt)
    if n then
      if n < 2 then n = 2 end; if n > 40 then n = 40 end
      RB.state.size = n; RB.state.size_selected = true
      local d = ComputeDefaults(RB.state.raid, RB.state.size, RB.state.esMode)
      RB.state.tanks, RB.state.healers, RB.state.srs = d.tanks, d.healers, d.srs
      UIDropDownMenu_SetSelectedValue(RB.ddSize, "custom")
      UIDropDownMenu_SetText(tostring(RB.state.size), RB.ddSize)
      UIDropDownMenu_SetText(RB.state.tanks .. " Tanks", RB.ddTanks)
      UIDropDownMenu_SetText(RB.state.healers .. " Healers", RB.ddHealers)
      UIDropDownMenu_SetText(RB.state.srs .. " SR", RB.ddSRs)
      RB.SaveState(); RB.RefreshPreview(); this:Hide(); this:ClearFocus()
    end
  end)
  RB.ddSize:SetPoint("TOPLEFT", f, "TOPLEFT", 70, -129); RB.ddSize:SetWidth(90)

  local lblT = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblT:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -167); lblT:SetText("Tanks:")

  RB.ddTanks = CreateFrame("Frame", "TacticaRBTanks", f, "UIDropDownMenuTemplate")
  RB.ddTanks:SetPoint("TOPLEFT", f, "TOPLEFT", 70, -161); RB.ddTanks:SetWidth(90)

  local lblH = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblH:SetPoint("TOPLEFT", f, "TOPLEFT", 240, -167); lblH:SetText("Healers:")

  RB.ddHealers = CreateFrame("Frame", "TacticaRBHealers", f, "UIDropDownMenuTemplate")
  RB.ddHealers:SetPoint("TOPLEFT", f, "TOPLEFT", 300, -161); RB.ddHealers:SetWidth(90)

  local lblSR = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblSR:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -199); lblSR:SetText("SR:")

  RB.ddSRs = CreateFrame("Frame", "TacticaRBSRs", f, "UIDropDownMenuTemplate")
  RB.ddSRs:SetPoint("TOPLEFT", f, "TOPLEFT", 70, -193); RB.ddSRs:SetWidth(90)

  local lblHR = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblHR:SetPoint("TOPLEFT", f, "TOPLEFT", 240, -199); lblHR:SetText("HR (max 65 char):")

  RB.editHR = CreateFrame("EditBox", "TacticaRBHR", f, "InputBoxTemplate")
  RB.editHR:SetPoint("TOPLEFT", f, "TOPLEFT", 350, -195)
  RB.editHR:SetAutoFocus(false); RB.editHR:SetWidth(100); RB.editHR:SetHeight(20)
  RB.editHR:SetMaxLetters(65); RB.editHR:SetText(RB.state.hr or "")
  RB.editHR:SetScript("OnTextChanged", OnEditHRChanged)

  local lblFree = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblFree:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -230); lblFree:SetText("Free text (max 65 char):")

  RB.editFree = CreateFrame("EditBox", "TacticaRBFree", f, "InputBoxTemplate")
  RB.editFree:SetPoint("TOPLEFT", f, "TOPLEFT", 165, -226)
  RB.editFree:SetAutoFocus(false); RB.editFree:SetWidth(100); RB.editFree:SetHeight(20)
  RB.editFree:SetMaxLetters(65); RB.editFree:SetText(RB.state.free or "")
  RB.editFree:SetScript("OnTextChanged", OnEditFreeChanged)

  RB.titleAnn = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  RB.titleAnn:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -260)
  RB.titleAnn:SetText("|cff33ff99ANNOUNCEMENT SETUP|r")

  local sep2 = f:CreateTexture(nil, "ARTWORK")
  sep2:SetHeight(1)
  sep2:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -275)
  sep2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -275)
  sep2:SetTexture(1,1,1); if sep2.SetVertexColor then sep2:SetVertexColor(1,1,1,0.25) end

  RB.cbCanSum = CreateFrame("CheckButton", "TacticaRBCanSum", f, "UICheckButtonTemplate")
  RB.cbCanSum:SetWidth(20); RB.cbCanSum:SetHeight(20); RB.cbCanSum:SetPoint("LEFT", RB.editFree, "RIGHT", 15, 0)
  getglobal("TacticaRBCanSumText"):SetText("Can summon")
  RB.cbCanSum:SetChecked(RB.state.canSum); RB.cbCanSum:SetScript("OnClick", OnCanSumClick)

  RB.cbHideNeed = CreateFrame("CheckButton", "TacticaRBHideNeed", f, "UICheckButtonTemplate")
  RB.cbHideNeed:SetWidth(20); RB.cbHideNeed:SetHeight(20); RB.cbHideNeed:SetPoint("LEFT", RB.cbCanSum, "RIGHT", 75, 0)
  getglobal("TacticaRBHideNeedText"):SetText("Hide #")
  RB.cbHideNeed:SetChecked(RB.state.hideNeed); RB.cbHideNeed:SetScript("OnClick", OnHideNeedClick)

  RB.cbWorld = CreateFrame("CheckButton", "TacticaRBWorld", f, "UICheckButtonTemplate")
  RB.cbWorld:SetWidth(20); RB.cbWorld:SetHeight(20); RB.cbWorld:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -282)
  getglobal("TacticaRBWorldText"):SetText("World")
  RB.cbWorld:SetChecked(RB.state.chWorld); RB.cbWorld:SetScript("OnClick", function() RB.state.chWorld = this:GetChecked() and true or false; RB.SaveState() end)

  RB.cbLFG = CreateFrame("CheckButton", "TacticaRBLFG", f, "UICheckButtonTemplate")
  RB.cbLFG:SetWidth(20); RB.cbLFG:SetHeight(20); RB.cbLFG:SetPoint("LEFT", RB.cbWorld, "RIGHT", 40, 0)
  getglobal("TacticaRBLFGText"):SetText("LFG")
  RB.cbLFG:SetChecked(RB.state.chLFG); RB.cbLFG:SetScript("OnClick", function() RB.state.chLFG = this:GetChecked() and true or false; RB.SaveState() end)

  RB.cbYell = CreateFrame("CheckButton", "TacticaRBYell", f, "UICheckButtonTemplate")
  RB.cbYell:SetWidth(20); RB.cbYell:SetHeight(20); RB.cbYell:SetPoint("LEFT", RB.cbLFG, "RIGHT", 30, 0)
  getglobal("TacticaRBYellText"):SetText("Yell")
  RB.cbYell:SetChecked(RB.state.chYell); RB.cbYell:SetScript("OnClick", function() RB.state.chYell = this:GetChecked() and true or false; RB.SaveState() end)

  RB.cbAuto = CreateFrame("CheckButton", "TacticaRBAuto", f, "UICheckButtonTemplate")
  RB.cbAuto:SetWidth(20); RB.cbAuto:SetHeight(20); RB.cbAuto:SetPoint("LEFT", RB.cbYell, "RIGHT", 30, 0)
  getglobal("TacticaRBAutoText"):SetText("Auto-Announce")
  RB.cbAuto:SetChecked(RB.state.auto); RB.cbAuto:SetScript("OnClick", OnAutoClick)

  RB.ddInterval = CreateFrame("Frame", "TacticaRBInterval", f, "UIDropDownMenuTemplate")
  RB.ddInterval:SetPoint("LEFT", RB.cbAuto, "RIGHT", 75, -3)
  UIDropDownMenu_Initialize(RB.ddInterval, function()
    local function add(sec, title)
      local info = {}; info.text = title; info.value = sec
      info.func = function()
        local picked = this and this.value or sec
        RB.state.interval = picked; RB.SaveState()
        UIDropDownMenu_SetSelectedValue(RB.ddInterval, picked)
        UIDropDownMenu_SetText(title, RB.ddInterval)
        if RB.state.running then
          RB._nextSend = (GetTime and GetTime() or 0) + picked
        end
        CloseDropDownMenus()
      end
      UIDropDownMenu_AddButton(info)
    end
    add(60,"1"); add(120,"2"); add(300,"5")
  end)
  UIDropDownMenu_SetSelectedValue(RB.ddInterval, RB.state.interval)
  UIDropDownMenu_SetText((RB.state.interval==60) and "1" or (RB.state.interval==300 and "5" or "2"), RB.ddInterval)
  UIDropDownMenu_SetWidth(50, RB.ddInterval)

  RB.lblInt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RB.lblInt:SetPoint("LEFT", RB.ddInterval, "RIGHT", -13, 2)
  RB.lblInt:SetWidth(450); RB.lblInt:SetJustifyH("LEFT"); RB.lblInt:SetText("")
  RB.lblInt:SetText("|cffffd100Auto Interval (min)|r")

  RB.titleInvite = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  RB.titleInvite:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -315)
  RB.titleInvite:SetText("|cff33ff99INVITE & GEAR SETUP|r")

  local sep3 = f:CreateTexture(nil, "ARTWORK")
  sep3:SetHeight(1)
  sep3:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -330)
  sep3:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -330)
  sep3:SetTexture(1,1,1); if sep3.SetVertexColor then sep3:SetVertexColor(1,1,1,0.25) end

-- Auto-Assign
RB.cbRoleAssign = CreateFrame("CheckButton", "TacticaRBRoleAssign", f, "UICheckButtonTemplate")
RB.cbRoleAssign:SetWidth(20); RB.cbRoleAssign:SetHeight(20)
RB.cbRoleAssign:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -340)
getglobal("TacticaRBRoleAssignText"):SetText("Auto-Assign")
RB.cbRoleAssign:SetChecked(RB.state.aiAutoRoles and true or false)
RB.cbRoleAssign:SetScript("OnClick", function()
  RB.state.aiAutoRoles = this:GetChecked() and true or false
  RB.SaveState()
  RB_AutoInviteUpdateFromUI("autoRoles")
end)

-- Auto-Invite
RB.cbAutoInvite = CreateFrame("CheckButton", "TacticaRBAutoInvite", f, "UICheckButtonTemplate")
RB.cbAutoInvite:SetWidth(20); RB.cbAutoInvite:SetHeight(20)
RB.cbAutoInvite:SetPoint("LEFT", RB.cbRoleAssign, "RIGHT", 70, 0)
getglobal("TacticaRBAutoInviteText"):SetText("Auto-Invite")
RB.cbAutoInvite:SetChecked(RB.state.aiAutoInvite and true or false)

RB.cbAutoInvite:SetScript("OnClick", function()
  RB.state.aiAutoInvite = this:GetChecked() and true or false
  RB.SaveState()
  RB_AutoInviteUpdateFromUI("autoInvite")
end)

  -- Gear Scale dropdown (right of Auto-Invite)
  RB.ddGearScale = CreateFrame("Frame", "TacticaRBGearScale", f, "UIDropDownMenuTemplate")
  RB.ddGearScale:SetPoint("LEFT", RB.cbAutoInvite, "RIGHT", 60, -3)
  UIDropDownMenu_SetWidth(120, RB.ddGearScale)

  local function GearTextFor(n)
    if n==0 then return "0 – Starter" end
    if n==1 then return "1 – ZG/AQ20/MC" end
    if n==2 then return "2 – BWL/ES/Kara10" end
    if n==3 then return "3 – AQ40/T2.5" end
    if n==4 then return "4 – Naxx/T3" end
    if n==5 then return "5 – Kara40/T3.5" end
    return "Select Minimum Gear Scale"
  end

  RB.InitGearScaleDropdown = function()
    UIDropDownMenu_Initialize(RB.ddGearScale, function()
      local suggested = SuggestGearScale(RB.state.raid, RB.state.esMode, RB.state.worldBoss)
      if suggested ~= nil then
        UIDropDownMenu_AddButton({ text="Suggested: "..GearTextFor(suggested), notClickable=1, isTitle=1 })
      else
        UIDropDownMenu_AddButton({ text="Suggested: Pick raid/boss", notClickable=1, isTitle=1 })
      end
      local i
      for i=0,5 do
        local info = {}
        info.text = GearTextFor(i); info.value = i
        info.func = function()
          local picked = this and this.value or i
          RB.state.gearScale = picked
          UIDropDownMenu_SetText("Scale "..picked, RB.ddGearScale)
          RB.SaveState()
          RB_SyncInviteExtras()
          CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info)
      end
    end)
    if RB.state.gearScale ~= nil then
      UIDropDownMenu_SetText("Scale "..RB.state.gearScale, RB.ddGearScale)
    else
      UIDropDownMenu_SetText("Required Gear", RB.ddGearScale)
    end
  end
  RB.InitGearScaleDropdown()

  -- Auto-Gearcheck checkbox + label
  RB.cbGear = CreateFrame("CheckButton", "TacticaRBGear", f, "UICheckButtonTemplate")
  RB.cbGear:SetWidth(20); RB.cbGear:SetHeight(20)
  RB.cbGear:SetPoint("LEFT", RB.ddGearScale, "RIGHT", -13, 2)
  RB.cbGear:SetChecked(RB.state.autoGear and true or false)

  RB.lblGear = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RB.lblGear:SetPoint("LEFT", RB.cbGear, "RIGHT", -2, 0)
  RB.lblGear:SetWidth(200); RB.lblGear:SetJustifyH("LEFT")
  RB.lblGear:SetText("|cffffd100Auto-Gearcheck|r")

  -- How-it-works + list (no "enabled" line here)
  local function PrintGearHowItWorks()
    RB_Print("|cff33ff99[Tactica]:|r Players will be asked to grade their gear from 0 to 5. They may reply with a number (e.g. '2') or a range (e.g. '2-3'). Ranges use the average; 1-3 = 2 while 1-2 = 1 (0.5 rounds down).")
    RB_Print("|cff33ff99[Tactica]:|r Grade Gear Scale:")
    RB_Print("|cff33ff99[Tactica]:|r 0 – Starter / Dungeon blues")
    RB_Print("|cff33ff99[Tactica]:|r 1 – ZG / AQ20 / MC")
    RB_Print("|cff33ff99[Tactica]:|r 2 – BWL / ES / Kara10")
    RB_Print("|cff33ff99[Tactica]:|r 3 – AQ40 / T2.5")
    RB_Print("|cff33ff99[Tactica]:|r 4 – Naxx / T3")
    RB_Print("|cff33ff99[Tactica]:|r 5 – Kara40 / T3.5")
  end
  -- Final full-green enabled line
  local function PrintGearEnabled()
    RB_Print("|cff33ff99[Tactica]:|r Auto-Gearcheck |cff00ff00ENABLED|r.")
  end

RB.cbGear:SetScript("OnClick", function()
  local prev = RB.state.autoGear and true or false
  local want = this:GetChecked() and true or false

  if want and RB.state.gearScale == nil then
    this:SetChecked(false)
    RB.state.autoGear = false
    RB.SaveState()
    RB_SyncInviteExtras()
    PrintGearHowItWorks()
    RB_Print("|cffff6666[Tactica]:|r You need to select |cffffff00Required Gear|r (minimum gear scale) before enabling Auto-Gearcheck.")
    return
  end

  RB.state.autoGear = want
  RB.SaveState()
  RB_SyncInviteExtras()

  if want and not prev then
    PrintGearHowItWorks()
    PrintGearEnabled()
  elseif (not want) and prev then
    RB_Print("|cff33ff99[Tactica]:|r Auto-Gearcheck |cffff5555DISABLED|r.")
  end
end)

  -- Grey note explaining Auto-Assign vs Auto-Invite
  RB.lblAIExplain = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RB.lblAIExplain:SetPoint("BOTTOMLEFT", RB.cbRoleAssign, "BOTTOMLEFT", 0, -20)
  RB.lblAIExplain:SetWidth(450); RB.lblAIExplain:SetJustifyH("LEFT")
  if RB.lblAIExplain.SetTextColor then RB.lblAIExplain:SetTextColor(0.7,0.7,0.7) end
  RB.lblAIExplain:SetText("Note: Auto-Assign will auto-set roles in raid roster. Auto-Invite will invite on intent.")
 

  -- SR & DISCORD SECTION
  RB.titleSRD = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  RB.titleSRD:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -395)
  RB.titleSRD:SetText("|cff33ff99SR & DISCORD|r")

  RB.sepSRD = f:CreateTexture(nil, "ARTWORK")
  RB.sepSRD:SetHeight(1)
  RB.sepSRD:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -410)
  RB.sepSRD:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -410)
  RB.sepSRD:SetTexture(1, 1, 1); if RB.sepSRD.SetVertexColor then RB.sepSRD:SetVertexColor(1, 1, 1, 0.25) end

  local lblSRLink = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblSRLink:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -420)
  lblSRLink:SetText("SR link:")

  RB.editSRLink = CreateFrame("EditBox", "TacticaRBSRLink", f, "InputBoxTemplate")
  RB.editSRLink:SetPoint("LEFT", lblSRLink, "RIGHT", 6, 0)
  RB.editSRLink:SetAutoFocus(false); RB.editSRLink:SetWidth(100); RB.editSRLink:SetHeight(20)
  RB.editSRLink:SetMaxLetters(200)
  RB.editSRLink:SetText(RB.state.srLink or "")
  RB.editSRLink:SetScript("OnTextChanged", function()
    RB.state.srLink = this:GetText() or ""
    if RB.UpdateSRDPostState then RB.UpdateSRDPostState() end
  end)

  local lblDiscord = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lblDiscord:SetPoint("LEFT", RB.editSRLink, "RIGHT", 10, 0)
  lblDiscord:SetText("Discord link:")

  RB.editDiscordLink = CreateFrame("EditBox", "TacticaRBDcLink", f, "InputBoxTemplate")
  RB.editDiscordLink:SetPoint("LEFT", lblDiscord, "RIGHT", 6, 0)
  RB.editDiscordLink:SetAutoFocus(false); RB.editDiscordLink:SetWidth(100); RB.editDiscordLink:SetHeight(20)
  RB.editDiscordLink:SetMaxLetters(200)
  RB.editDiscordLink:SetText(RB.state.discordLink or "")
  RB.editDiscordLink:SetScript("OnTextChanged", function()
    RB.state.discordLink = this:GetText() or ""
    if RB.UpdateSRDPostState then RB.UpdateSRDPostState() end
  end)

  RB.btnSRDPost = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  RB.btnSRDPost:SetWidth(50); RB.btnSRDPost:SetHeight(20)
  RB.btnSRDPost:SetPoint("LEFT", RB.editDiscordLink, "RIGHT", 8, 0)
  RB.btnSRDPost:SetText("Post")

  local function RB_PostSRDiscord()
    local sr = RB_Trim(RB.state.srLink or "")
    local dc = RB_Trim(RB.state.discordLink or "")
    if sr == "" and dc == "" then return end
    if not RB_IsLeaderOrAssist() then
      RB_Print("|cffff6666[Tactica]:|r You must be raid leader or assist to post raid warnings.")
      return
    end
    if sr ~= "" then
      SendChatMessage("[Tactica] - SR link: " .. sr, "RAID_WARNING")
    end
    if dc ~= "" then
      SendChatMessage("[Tactica] - Join Discord: " .. dc, "RAID_WARNING")
    end
  end
  RB.btnSRDPost:SetScript("OnClick", RB_PostSRDiscord)

  function RB.UpdateSRDPostState()
    if not RB.btnSRDPost then return end
    local sr = RB_Trim(RB.state.srLink or "")
    local dc = RB_Trim(RB.state.discordLink or "")
    local hasAny = (sr ~= "" or dc ~= "")
    local can = RB_IsLeaderOrAssist()
    if hasAny and can then
      RB.btnSRDPost:Enable(); RB.btnSRDPost:SetAlpha(1.0)
    else
      RB.btnSRDPost:Disable(); RB.btnSRDPost:SetAlpha(0.5)
    end
  end

  local sep4 = f:CreateTexture(nil, "ARTWORK")
  sep4:SetHeight(1)
  sep4:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -445)
  sep4:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -445)
  sep4:SetTexture(1, 1, 1); if sep4.SetVertexColor then sep4:SetVertexColor(1, 1, 1, 0.25) end

  -- END SR & DISCORD SECTION 

  RB.lblNotes = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RB.lblNotes:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -455)
  RB.lblNotes:SetWidth(450); RB.lblNotes:SetJustifyH("LEFT"); RB.lblNotes:SetText("")

  RB.lblPreview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RB.lblPreview:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -480)
  RB.lblPreview:SetWidth(450); RB.lblPreview:SetJustifyH("LEFT"); RB.lblPreview:SetText("|cff33ff99Preview:|r ")

  RB.lblHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  RB.lblHint:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -515)
  RB.lblHint:SetWidth(450); RB.lblHint:SetJustifyH("LEFT")
  RB.lblHint:SetText("|cffffd100Note:|r |cff999999Assign roles (Tank / Healer / DPS) to players in the Raid Roster (hotkey: "
    .. (RaidRosterHotkey() or "unbound") .. ") to auto-adjust the LFM announcement.|r")

  RB.btnAnnounce = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  RB.btnAnnounce:SetWidth(90); RB.btnAnnounce:SetHeight(22)
  RB.btnAnnounce:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 15)
  RB.btnAnnounce:SetText("Announce")
  RB.btnAnnounce:SetScript("OnClick", OnAnnounceClick)

  RB.btnSelf = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  RB.btnSelf:SetWidth(90); RB.btnSelf:SetHeight(22)
  RB.btnSelf:SetPoint("LEFT", RB.btnAnnounce, "RIGHT", 6, 0)
  RB.btnSelf:SetText("Self Post")
  RB.btnSelf:SetScript("OnClick", OnSelfClick)
  local fs = RB.btnSelf:GetFontString()
  if fs and fs.SetTextColor then fs:SetTextColor(0.2, 1.0, 0.2) end
  RB.btnSelf:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  local nt = RB.btnSelf:GetNormalTexture(); if nt then nt:SetVertexColor(0.2, 0.8, 0.2) end
  RB.btnSelf:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
  local pt = RB.btnSelf:GetPushedTexture(); if pt then pt:SetVertexColor(0.2, 0.8, 0.2) end
  RB.btnSelf:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
  local ht = RB.btnSelf:GetHighlightTexture()
  if ht then ht:SetBlendMode("ADD"); ht:SetVertexColor(0.2, 1.0, 0.2) end

  RB.btnRaid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  RB.btnRaid:SetWidth(90); RB.btnRaid:SetHeight(22)
  RB.btnRaid:SetPoint("LEFT", RB.btnSelf, "RIGHT", 6, 0)
  RB.btnRaid:SetText("Raid Roster")
  RB.btnRaid:SetScript("OnClick", OpenRaidPanel)

  -- Exclude List button (between Raid Roster and Clear)
  RB.btnExclude = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  RB.btnExclude:SetWidth(90); RB.btnExclude:SetHeight(22)
  RB.btnExclude:SetPoint("LEFT", RB.btnRaid, "RIGHT", 6, 0)
  RB.btnExclude:SetText("Exclude List")
  RB.btnExclude:SetScript("OnClick", function() RB_OpenExcludeList() end)

  RB.btnClear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  RB.btnClear:SetWidth(70); RB.btnClear:SetHeight(22)
  RB.btnClear:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 15)
  RB.btnClear:SetText("Clear"); RB.btnClear:SetScript("OnClick", OnClearClick)

  RB.InitRaidDropdown(); RB.InitWBossDropdown(); RB.InitESModeDropdown()
  if RB.state.raid == "World Bosses" then RB.ddWBoss:Show() else RB.ddWBoss:Hide() end
  if RB.state.raid == "Emerald Sanctum" then RB.ddESMode:Show() else RB.ddESMode:Hide() end
  if RB.state.raid == "-CUSTOM-" then
    if RB.editCustomRaid then
      RB.editCustomRaid:SetText(RB.state.customRaidText or "")
      RB.editCustomRaid:Show()
    end
    if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Show() end
  else
    if RB.editCustomRaid then RB.editCustomRaid:Hide() end
    if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Hide() end
  end
  RB.InitSizeDropdown()
  local function setN(drop, label, fromN, toN, setter) InitNumberDropdown(drop, label, fromN, toN, setter) end
  setN(RB.ddTanks,  "Tanks",   1, 10, function(n) RB.state.tanks = n end)
  setN(RB.ddHealers,"Healers", 1, 10, function(n) RB.state.healers = n end)
  setN(RB.ddSRs,    "SR",      0,  3, function(n) RB.state.srs = n end)
  RB.InitPresetDropdowns()

  if not RB.state.size_selected then
    UIDropDownMenu_SetText("Pick Size first", RB.ddTanks)
    UIDropDownMenu_SetText("Pick Size first", RB.ddHealers)
  end
  if RB.state.size_selected and RB.state.tanks then
    UIDropDownMenu_SetText(RB.state.tanks .. " Tanks", RB.ddTanks)
  end
  if RB.state.size_selected and RB.state.healers then
    UIDropDownMenu_SetText(RB.state.healers .. " Healers", RB.ddHealers)
  end
  if RB.state.srs then
    UIDropDownMenu_SetText(RB.state.srs .. " SR", RB.ddSRs)
  end

  RestoreFramePosition()
  RB.RefreshPreview()
  RB.UpdateButtonsForRunning()
  ApplyLockIcon()
  RB_SyncInviteExtras()
  RB_AutoInviteUpdateFromUI()
  f:Show()
end

-------------------------------------------------
-- Preset management
-------------------------------------------------
function RB.SavePreset(name)
  name = RB_Trim(name)
  if name == "" then RB_Print("|cffff6666[Tactica]:|r Enter a preset name to save."); return end
  local db = PresetsDB()
  db[name] = RB_SnapshotForPreset()
  RB_Print("|cff33ff99[Tactica]:|r Preset saved: |cffffff00"..name.."|r.")
end

function RB.LoadPreset(name)
  local p = PresetsDB()[name]
  if not p then RB_Print("|cffff6666[Tactica]:|r Preset not found: "..tostring(name)); return end

  RB.state.raid        = p.raid
  RB.state.worldBoss   = p.worldBoss
  RB.state.esMode      = p.esMode
  RB.state.customRaidText = p.customRaidText or ""
  RB.state.size        = p.size
  RB.state.size_selected = p.size_selected and true or false
  RB.state.tanks       = p.tanks
  RB.state.healers     = p.healers
  RB.state.srs         = p.srs
  RB.state.hr          = p.hr or ""
  RB.state.free        = p.free or ""
  RB.state.canSum      = p.canSum and true or false
  RB.state.hideNeed    = p.hideNeed and true or false
  RB.state.chWorld     = p.chWorld and true or false
  RB.state.chLFG       = p.chLFG   and true or false
  RB.state.chYell      = p.chYell  and true or false
  RB.state.interval    = (p.interval == 60 or p.interval == 120 or p.interval == 300) and p.interval or 120
  RB.state.gearScale   = p.gearScale
  RB.state.autoGear    = p.autoGear and true or false
  RB.state.discordLink = p.discordLink or ""
  
  if p.aiAutoRoles ~= nil then
    RB.state.aiAutoRoles = p.aiAutoRoles and true or false
  end
  if p.aiAutoInvite ~= nil then
    RB.state.aiAutoInvite = p.aiAutoInvite and true or false
  end

  if RB.state.raid == "World Bosses" then
    RB.ddWBoss:Show(); RB.ddESMode:Hide()
    if RB.editCustomRaid then RB.editCustomRaid:Hide() end
    if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Hide() end
  elseif RB.state.raid == "Emerald Sanctum" then
    RB.ddESMode:Show(); RB.ddWBoss:Hide()
    if RB.editCustomRaid then RB.editCustomRaid:Hide() end
    if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Hide() end
  elseif RB.state.raid == "-CUSTOM-" then
    RB.ddWBoss:Hide(); RB.ddESMode:Hide()
    if RB.editCustomRaid then
      RB.editCustomRaid:SetText(RB.state.customRaidText or "")
      RB.editCustomRaid:Show()
    end
    if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Show() end
  else
    RB.ddWBoss:Hide(); RB.ddESMode:Hide()
    if RB.editCustomRaid then RB.editCustomRaid:Hide() end
    if RB.lblCustomRaidHint then RB.lblCustomRaidHint:Hide() end
  end 
  
  if RB.editCustomRaid then
    RB.editCustomRaid:SetText(RB.state.customRaidText or "")
  end

  UIDropDownMenu_SetText(RB.state.raid or "Select Raid", RB.ddRaid)
  UIDropDownMenu_SetText(RB.state.worldBoss or "Pick Boss", RB.ddWBoss)
  UIDropDownMenu_SetText(RB.state.esMode or "Select Mode", RB.ddESMode)

  if RB.state.size_selected and RB.state.size then
    UIDropDownMenu_SetText(tostring(RB.state.size), RB.ddSize)
    if RB.state.tanks then   UIDropDownMenu_SetText(RB.state.tanks   .. " Tanks",   RB.ddTanks)   end
    if RB.state.healers then UIDropDownMenu_SetText(RB.state.healers .. " Healers", RB.ddHealers) end
    UIDropDownMenu_SetText((RB.state.srs or 0) .. " SR", RB.ddSRs)
  else
    UIDropDownMenu_SetText("Select Size", RB.ddSize); if RB.editCustomSize then RB.editCustomSize:Hide() end
    UIDropDownMenu_SetText("Pick Size first", RB.ddTanks)
    UIDropDownMenu_SetText("Pick Size first", RB.ddHealers)
    UIDropDownMenu_SetText("0 SR", RB.ddSRs)
  end

  UIDropDownMenu_SetText((RB.state.interval==60) and "1" or (RB.state.interval==300 and "5" or "2"), RB.ddInterval)
  if RB.cbWorld then RB.cbWorld:SetChecked(RB.state.chWorld) end
  if RB.cbLFG   then RB.cbLFG:SetChecked(RB.state.chLFG)   end
  if RB.cbYell  then RB.cbYell:SetChecked(RB.state.chYell) end
  if RB.cbCanSum then RB.cbCanSum:SetChecked(RB.state.canSum) end
  if RB.cbHideNeed then RB.cbHideNeed:SetChecked(RB.state.hideNeed) end
  if RB.editHR  then RB.editHR:SetText(RB.state.hr or "") end
  if RB.editFree then RB.editFree:SetText(RB.state.free or "") end
  if RB.editDiscordLink then RB.editDiscordLink:SetText(RB.state.discordLink or "") end
  if RB.cbGear then RB.cbGear:SetChecked(RB.state.autoGear and true or false) end

  if RB.cbRoleAssign then
    RB.cbRoleAssign:SetChecked(RB.state.aiAutoRoles and true or false)
  end
  if RB.cbAutoInvite then
    RB.cbAutoInvite:SetChecked(RB.state.aiAutoInvite and true or false)
  end

  if RB.UpdateSRDPostState then RB.UpdateSRDPostState() end
  RB.InitGearScaleDropdown()

  RB.SaveState()
  RB.RefreshPreview()
  RB_SyncInviteExtras()
  RB_AutoInviteUpdateFromUI()
  RB_Print("|cff33ff99[Tactica]:|r Preset loaded: |cffffff00"..name.."|r.")
end

function RB.RemovePreset(name)
  local db = PresetsDB()
  if not db[name] then RB_Print("|cffff6666[Tactica]:|r Preset not found: "..tostring(name)); return end
  db[name] = nil
  RB_Print("|cff33ff99[Tactica]:|r Preset removed: |cffffff00"..name.."|r.")
end

-------------------------------------------------
-- Extra slash shortcut
-- Use: /ttlfm
-------------------------------------------------
SLASH_TACTICARBLFM1 = "/ttlfm"
SlashCmdList["TACTICARBLFM"] = function(msg)
  TacticaRaidBuilder.AnnounceOnce()
end

-------------------------------------------------
-- Leader detection popup with per-raid "don't show again"
-------------------------------------------------
local RB_leaderEvt = CreateFrame("Frame")
RB_leaderEvt:RegisterEvent("RAID_ROSTER_UPDATE")
RB_leaderEvt:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ensure SavedVariable exists
TacticaDB = TacticaDB or {}
TacticaDB.disablePopupThisRaid = TacticaDB.disablePopupThisRaid or false

local selfWasInRaid = false
local popupShownThisRaid = false

local function RB_LeaderNameForNoneLabel()
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i=1,n do
      local nm, rank = GetRaidRosterInfo(i)
      if rank == 2 then return nm or "raidlead" end
    end
    return "raidlead"
end

local function RB_RaidNamesInOrder()
    local names = {}
    local leader = RB_LeaderNameForNoneLabel()
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i=1,n do
      local nm = GetRaidRosterInfo(i)
      if nm and nm ~= "" and nm ~= leader then table.insert(names, nm) end
    end
    return names
end

local function RB_SetDropdownEnabled(dd, enabled)
    if not dd then return end
    if dd.EnableMouse then dd:EnableMouse(enabled and true or false) end
    dd:SetAlpha(enabled and 1.0 or 0.55)
    local btn = dd.GetName and getglobal(dd:GetName().."Button") or nil
    if btn then
      if enabled and btn.Enable then btn:Enable()
      elseif (not enabled) and btn.Disable then btn:Disable() end
    end
end

local function RB_ShowLeaderPopup()
    -- do not show if Raid Builder is already open
    if RB.frame and RB.frame:IsShown() then return end
    if RB._leaderPopup and RB._leaderPopup:IsShown() then return end
    if TacticaDB.disablePopupThisRaid then return end

    popupShownThisRaid = true

    local f = CreateFrame("Frame", "TacticaLeaderPopup", UIParent)
    RB._leaderPopup = f
    f:SetWidth(350); f:SetHeight(255)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 }
    })
    f:SetBackdropColor(0, 0, 0, 1)
    f:SetBackdropBorderColor(1, 1, 1, 1)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -20)
    title:SetText("TACTICA RAID BUILDER")
    title:SetTextColor(0.2, 1.0, 0.6)

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -45)
    text:SetWidth(360)
    text:SetJustifyH("LEFT")
    text:SetText("You are forming a raid.\nWould you like Tactica to assist?\n\nFeatures:\n• Auto role-assignment\n• Auto Gearchecks\n• Auto-invite (use /ttai)\n• Auto announcements\n• Auto LFM-message updates")

    local mlLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mlLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -162)
    if mlLbl.SetTextColor then mlLbl:SetTextColor(1.0, 0.82, 0) end
    mlLbl:SetText("Preset Masterlooter:")

    local mlDD = CreateFrame("Frame", "TacticaRBLeaderPopupML", f, "UIDropDownMenuTemplate")
    mlDD:SetPoint("TOPLEFT", f, "TOPLEFT", 120, -154)
    UIDropDownMenu_SetWidth(160, mlDD)
    local canEditML = (IsRaidLeader and IsRaidLeader() == 1) and true or false
    UIDropDownMenu_Initialize(mlDD, function()
      UIDropDownMenu_AddButton({
        text = "None/"..(RB_LeaderNameForNoneLabel() or "raidlead"),
        func = function()
          if not canEditML then return end
          if type(TacticaRaidRoles_SetPresetMasterLooter) == "function" then
            TacticaRaidRoles_SetPresetMasterLooter("")
          end
          UIDropDownMenu_SetText("None/"..(RB_LeaderNameForNoneLabel() or "raidlead"), mlDD)
        end
      })
      local names = RB_RaidNamesInOrder()
      for i=1, table.getn(names) do
        local nm = names[i]
        UIDropDownMenu_AddButton({
          text = nm,
          func = function()
            if not canEditML then return end
            if type(TacticaRaidRoles_SetPresetMasterLooter) == "function" then
              TacticaRaidRoles_SetPresetMasterLooter(nm)
            end
            UIDropDownMenu_SetText(nm, mlDD)
          end
        })
      end
    end)
    local currentML = (type(TacticaRaidRoles_GetPresetMasterLooter) == "function" and TacticaRaidRoles_GetPresetMasterLooter()) or ""
    UIDropDownMenu_SetText((currentML ~= "" and currentML) or ("None/"..(RB_LeaderNameForNoneLabel() or "raidlead")), mlDD)
    RB_SetDropdownEnabled(mlDD, canEditML)

    -- checkbox
    local checkbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkbox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 40)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
    label:SetText("Don't show this message again this raid")

    checkbox:SetScript("OnClick", function()
    TacticaDB.disablePopupThisRaid = this:GetChecked()
	end)


    -- No button
    local btnNo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnNo:SetWidth(140); btnNo:SetHeight(24)
    btnNo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 15)
    btnNo:SetText("No, manage manually")
    btnNo:SetScript("OnClick", function() f:Hide() end)

    -- Yes button
    local btnYes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnYes:SetWidth(160); btnYes:SetHeight(24)
    btnYes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 15)
    btnYes:SetText("Yes, open Raid Builder")
    btnYes:SetScript("OnClick", function()
        f:Hide()
        if RB.Open then RB.Open() end
    end)
end

-- handle events
RB_leaderEvt:SetScript("OnEvent", function()
    local num = GetNumRaidMembers and GetNumRaidMembers() or 0
	local inRaid = num > 0

    -- Reset per-raid popup flag when leaving raid
    if not inRaid and selfWasInRaid then
        TacticaDB.disablePopupThisRaid = false
        popupShownThisRaid = false
    end
    selfWasInRaid = inRaid

    if not inRaid then return end

    -- only show popup if not already shown this raid
    if popupShownThisRaid or TacticaDB.disablePopupThisRaid then return end

    local playerName = UnitName("player")
    if not playerName then return end

    for i = 1, num do
        local rname, rank = GetRaidRosterInfo(i)
        if rname and rname == playerName and (rank == 1 or rank == 2) then
            RB_ShowLeaderPopup()
            break
        end
    end
end)

-------------------------------------------------
-- Exclude List UI (session-only; affects LFM counts)
-------------------------------------------------
RB._exclude = RB._exclude or {}

local function RB_SortedRaidNames()
  local names = {}
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  local i
  for i=1,n do
    local nm = GetRaidRosterInfo(i)
    if nm and nm ~= "" then table.insert(names, nm) end
  end
  table.sort(names, function(a,b) return string.lower(a) < string.lower(b) end)
  return names
end

function RB_RefreshExcludeList()
  if not RB.excl or not RB.excl.child then return end
  local p = RB.excl
  -- wipe old
  local i
  if p.items then
    for i=1, table.getn(p.items) do
      local it = p.items[i]
      if it and it.cb then it.cb:Hide(); it.cb:SetParent(nil) end
      p.items[i] = nil
    end
  end
  p.items = {}
  local list = RB_SortedRaidNames()
  local y = -2
  for i=1, table.getn(list) do
    local nm = list[i]
    local cb = CreateFrame("CheckButton", nil, p.child, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", p.child, "TOPLEFT", 4, y)
    y = y - 22
    local font = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    font:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    font:SetText(nm)
    cb:SetChecked(RB._exclude and RB._exclude[nm] or false)
    p.items[i] = { cb=cb, name=nm }
  end
  p.child:SetHeight(-y + 6)
  if RB.excl and RB.excl.scroll and RB.excl.scroll.UpdateScrollChildRect then
    RB.excl.scroll:UpdateScrollChildRect()
  end
end

function RB_OpenExcludeList()
  if not RB.frame then return end
  if RB.excl then
    RB.excl:Show()
    RB_RefreshExcludeList()
    return
  end

  local f = RB.frame
  local p = CreateFrame("Frame", "TacticaRBExclude", f)
  RB.excl = p
  p:SetWidth(260); p:SetHeight(300)
  p:SetPoint("CENTER", f, "CENTER", 0, 0)
  p:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left=11, right=12, top=12, bottom=11 }
  })
  p:SetBackdropColor(0, 0, 0, 1)
  p:SetBackdropBorderColor(1, 1, 1, 1)
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:SetToplevel(true)
  p:EnableMouse(true)

  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOP", p, "TOP", 0, -15)
  t:SetText("Exclude List")
  t:SetTextColor(0.2, 1.0, 0.6)

  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -34)
  sub:SetWidth(232); sub:SetJustifyH("LEFT")
  sub:SetText("Any players checked in the list below will not count to the LFM message. Neither the total needed or role specific.")

  -- ONE scrollframe (create this first)
  local scrollFrame = CreateFrame("ScrollFrame", "TacticaRBExcludeScroll", p, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -75)
  scrollFrame:SetWidth(205); scrollFrame:SetHeight(180)
  p.scroll = scrollFrame

  -- Pretty background around the scroll area
  local bg = CreateFrame("Frame", nil, p)
  bg:SetPoint("TOPLEFT",     scrollFrame, "TOPLEFT",     -5,  5)
  bg:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT",  5, -5)
  bg:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left=4, right=4, top=4, bottom=4 }
  })
  if bg.SetBackdropColor then bg:SetBackdropColor(0, 0, 0, 0.5) end

  -- Child that will hold the checkboxes
  local child = CreateFrame("Frame", nil, scrollFrame)
  child:SetWidth(200); child:SetHeight(1)
  scrollFrame:SetScrollChild(child)
  p.child = child
  p.items = {}

  -- Mouse wheel support
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    local sb = getglobal("TacticaRBExcludeScrollScrollBar")
    if not sb then return end
    local step = 20
    if arg1 and arg1 > 0 then
      sb:SetValue(sb:GetValue() - step)
    else
      sb:SetValue(sb:GetValue() + step)
    end
  end)

  -- Buttons
  local btnCancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  btnCancel:SetWidth(70); btnCancel:SetHeight(22)
  btnCancel:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 12)
  btnCancel:SetText("Cancel")
  btnCancel:SetScript("OnClick", function() p:Hide() end)

  local btnClear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  btnClear:SetWidth(70); btnClear:SetHeight(22)
  btnClear:SetPoint("BOTTOM", p, "BOTTOM", 0, 12)
  btnClear:SetText("Clear")
  btnClear:SetScript("OnClick", function()
    if p.items then
      for i=1, table.getn(p.items) do
        local it = p.items[i]
        if it and it.cb then it.cb:SetChecked(false) end
      end
    end
  end)

  local btnApply = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  btnApply:SetWidth(70); btnApply:SetHeight(22)
  btnApply:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 12)
  btnApply:SetText("Apply")
  btnApply:SetScript("OnClick", function()
    RB._exclude = RB._exclude or {}
    if p.items then
      for i=1, table.getn(p.items) do
        local it = p.items[i]
        if it and it.name then
          if it.cb:GetChecked() then RB._exclude[it.name] = true else RB._exclude[it.name] = nil end
        end
      end
    end
    RB.RefreshPreview()
    p:Hide()
  end)

  RB_RefreshExcludeList()
  p:Show()
end
