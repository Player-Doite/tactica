-- TacticaInvite.lua - Auto-invite/role assign/gearcheck for "vanilla"-compliant versions of Wow
-- Created by Doite

local INV = {}
TacticaInvite = INV

-- session state
INV.enabled       = false
INV.keyword       = ""
INV.autoAssign    = false

-- RB bridge state
INV.rbEnabled     = false
INV.rbKeyword     = ""
INV.rbAutoRoles   = false

-- Gearcheck (RB-only)
INV.rbGearEnabled     = false
INV.rbGearThreshold   = nil
INV._gearRatings      = INV._gearRatings or {}
INV._gearTimeoutRemind= true

-- flow state
INV.awaitingRole  = {}
INV.awaitCtx      = {}
INV.pendingRoles  = {}
INV.lastPrompt    = {}

-- gear flow
INV.awaitingGear   = {}
INV._gearAsked     = {}
INV._gearAfterRole = {}
INV._gearPending   = {}

-- session ignores (cleared when RB frame closes or UI reload)
INV._sessionIgnores = {}
function TacticaInvite.ResetSessionIgnores()
  for k in pairs(INV._sessionIgnores) do INV._sessionIgnores[k] = nil end

  -- also clean per-player gear prompts for a fresh session
  INV.awaitingGear, INV._gearAsked, INV._gearAfterRole, INV._gearPending = {}, {}, {}, {}

  -- IMPORTANT: when RB UI closes (or reload), nothing in here should keep converting or inviting later
  INV._convertWhenFirstJoins = false
  INV._pendingReinvites = {}
end

-- confirm queue (+ de-dupe index)
INV._queue        = {}
INV._enq          = {}
INV._showing      = nil
INV._confirm      = nil

-- raid conversion intent + reinvite buffer
INV._convertWhenFirstJoins = false
INV._pendingReinvites = {}  -- name(lower) -> {name, role, doAssign, skipCapacity}
-- re-invite helper for "player already in a group"
INV._recentInvite = INV._recentInvite or {}   -- last invite attempt per player
INV._groupRetry   = INV._groupRetry   or {}   -- window to auto re-invite on re-whisper

-- UI
INV.frame         = nil
INV.ui            = { edit=nil, cb=nil, btn=nil, off=nil }

-- helpers
local function now() return (GetTime and GetTime()) or 0 end
local function cfmsg(m) local cf=DEFAULT_CHAT_FRAME or ChatFrame1; if cf then cf:AddMessage("|cff33ff99[Tactica]:|r "..m) end end
local function say(to, msg) if to and msg and SendChatMessage then SendChatMessage(msg,"WHISPER",nil,to) end end
local function trim(s) s=s or ""; s=string.gsub(s,"^%s+",""); s=string.gsub(s,"%s+$",""); return s end
local function lower(s) return string.lower(s or "") end
local function cleanName(n) n = n or ""; n = string.match(n, "^([^-]+)") or n; n = string.gsub(n, "[%s%p]+$", ""); return n end

-- tiny timer for ordered whispers
INV._timers = INV._timers or {}
local function After(sec, fn)
  if not sec or sec<=0 then fn(); return end
  table.insert(INV._timers, {t=(GetTime and GetTime() or 0)+sec, fn=fn})
end
if not INV._tick then
  INV._tick = CreateFrame("Frame")
  INV._tick:SetScript("OnUpdate", function(_,elapsed)
    if not INV._timers or table.getn(INV._timers)==0 then return end
    local t = GetTime and GetTime() or 0
    local i=1
    while i<=table.getn(INV._timers) do
      local it=INV._timers[i]
      if it.t<=t then
        local f=it.fn
        table.remove(INV._timers,i)
        if f then f() end
      else
        i=i+1
      end
    end
  end)
end

-- === Group helpers (party + raid) ===

local function IsNameInRaid(name)
  local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  for i=1,n do
    local nm = GetRaidRosterInfo(i)
    if nm and nm == name then return true end
  end
  return false
end

local function IsNameInParty(name)
  if not name or name == "" then return false end

  local me = UnitName and UnitName("player")
  if me and me == name then return true end

  local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  for i=1,pn do
    local u = "party"..i
    if UnitExists and UnitExists(u) then
      local nm = UnitName(u)
      if nm and nm == name then return true end
    end
  end
  return false
end

local function IsNameInGroup(name)
  if IsNameInRaid(name) then return true end
  return IsNameInParty(name)
end

local function RB() return TacticaRaidBuilder end
local function RBFrameShown()
  local R = RB()
  return (R and R.frame and R.frame:IsShown()) and true or false
end

-- Module should ONLY do anything when:
--  - standalone keyword autoinvite is enabled, OR
--  - raid builder frame is currently shown (and RB features are enabled)
local function INV_IsActive()
  if INV.enabled then return true end
  if RBFrameShown() and (INV.rbEnabled or INV.rbAutoRoles or (INV.rbGearEnabled and INV.rbGearThreshold ~= nil)) then
    return true
  end
  return false
end

-- Only convert to raid if the RB target size is > 5. If RB custom size is 5 or less, we must stay party.
local function INV_ShouldConvertToRaid()
  if not RBFrameShown() then
    return false
  end
  local R = RB()
  local size = (R and R.state and R.state.size) or 0
  if size > 0 and size <= 5 then return false end
  return true
end


local function TryConvertToRaid(reason, retries)
  retries = retries or 10
  if not INV._convertWhenFirstJoins then return end

  -- If RB size is 5 or less, never convert.
  if not INV_ShouldConvertToRaid() then
    INV._convertWhenFirstJoins = false
    INV._pendingReinvites = {}
    return
  end

  -- If not active, do NOT leak conversion behavior.
  if not INV_IsActive() then
    INV._convertWhenFirstJoins = false
    INV._pendingReinvites = {}
    return
  end

  local raidN  = (GetNumRaidMembers  and GetNumRaidMembers()  or 0)
  local partyN = (GetNumPartyMembers and GetNumPartyMembers() or 0)

  if raidN > 0 then
    INV._convertWhenFirstJoins = false
    return
  end

  -- If not even in a party yet, wait a bit (solo cannot convert directly)
  if partyN == 0 then
    if retries > 0 then
      After(0.5, function() TryConvertToRaid(reason, retries-1) end)
    end
    return
  end

  local amLead = (IsPartyLeader and IsPartyLeader()) and true or false
  if amLead and ConvertToRaid then
    ConvertToRaid()
    cfmsg("Auto-converting party to raid... ("..tostring(reason or "n/a")..")")
    INV._convertWhenFirstJoins = false
  else
    -- not leader yet; keep trying briefly
    if retries > 0 then
      After(0.5, function() TryConvertToRaid(reason, retries-1) end)
    end
  end
end

-- RB bridge
function TacticaInvite.SetFromRB(enabled, keyword, autoRoles)
  INV.rbEnabled   = enabled and true or false
  INV.rbKeyword   = trim(keyword or "")
  INV.rbAutoRoles = autoRoles and true or false
end

function TacticaInvite.SetGearcheckFromRB(enabled, threshold)
  INV.rbGearEnabled   = enabled and true or false
  INV.rbGearThreshold = threshold
end

function TacticaInvite.SetGearTimeoutRemind(on)
  INV._gearTimeoutRemind = on and true or false
end

-- tokens and knowledge
local PURE_DPS = { hunter=true, mage=true, rogue=true, warlock=true }

local ROLE_KEY = {
  tank="TANK", tanks="TANK", prot="TANK", protection="TANK", shield="TANK", bear="TANK", furyprot="TANK", ot="TANK", mt="TANK",
  offtank="TANK", maintank="TANK", tanking="TANK", def="TANK",
  heal="HEALER", healer="HEALER", heals="HEALER", resto="HEALER", holy="HEALER", disc="HEALER", discipline="HEALER", hpal="HEALER", hpr="HEALER", rdruid="HEALER", rdr="HEALER", healz="HEALER",
  spriest="DPS", fwar="DPS",
  dps="DPS", dd="DPS", damage="DPS", dmg="DPS", deeps="DPS", fury="DPS", arms="DPS", enh="DPS", enhancement="DPS", elemental="DPS", ele="DPS", hunter="DPS", mage="DPS", rogue="DPS", warlock="DPS",
  balance="DPS", boomkin="DPS", moonkin="DPS", shadow="DPS", sp="DPS", cat="DPS", feral="DPS", mm="DPS", marks="DPS", marksmanship="DPS", survival="DPS", bm="DPS", sv="DPS", surv="DPS",
  combat="DPS", assassin="DPS", assassination="DPS", assa="DPS", subtlety="DPS", sub="DPS", daggers="DPS", swords="DPS", rdps="DPS", mdps="DPS", boomi="DPS", boomie="DPS",
  ret="DPS", retri="DPS", destro="DPS", aff="DPS", demo="DPS",
  rdrood="HEALER", hpriest="HEALER",
  ["+tank"]="TANK", ["+heal"]="HEALER", ["+heals"] = "HEALER", ["+dps"] = "DPS", rsham="HEALER", hpala="HEALER", restosham="HEALER", restoshaman="HEALER", ["tank+"]="TANK", ["heal+"]="HEALER", ["heals+"] = "HEALER", ["dps+"] = "DPS"
}

local CLASS_KEY = {
  warrior=true, druid=true, priest=true, paladin=true, shaman=true,
  hunter=true, mage=true, rogue=true, warlock=true
}

-- spec to class hint (for displaying class when they write specs)
local SPEC2CLASS = {
  frost="mage", fire="mage", arcane="mage",
  shadow="priest", holy="priest", sp="priest",
  disc="priest", discipline="priest", spriest="priest", pri="priest", shadowpriest="priest",
  rsham="shaman", sham="shaman", sha="shaman", shammy="shaman", elesham="shaman",
  ret="paladin", retribution="paladin", retri="paladin", prot="paladin", pal="paladin", pala="paladin", pally="paladin", paly="paladin", protpal="paladin", protpala="paladin",
  enhance="shaman", enhancement="shaman", elemental="shaman", ele="shaman",
  feral="druid", balance="druid", boomkin="druid", bear="druid", cat="druid", drood="druid", dru="druid", drui="druid", feraldruid="druid",
  aff="warlock", affliction="warlock", demo="warlock", demonology="warlock", destro="warlock", destruction="warlock", lock="warlock", wlock="warlock", wl="warlock",
  mm="hunter", marks="hunter", marksmanship="hunter", survival="hunter", bm="hunter", hunt="hunter",
  combat="rogue", assassination="rogue", assassin="rogue", subtlety="rogue", sub="rogue", rog="rogue",
  fury="warrior", arms="warrior", war="warrior", warr="warrior", protection="warrior", protwar="warrior",
  mag="mage"
}

local ROLE_LET  = { TANK="T", HEALER="H", DPS="D" }
local ROLE_NAME = { TANK="Tank", HEALER="Healer", DPS="DPS" }
local LETTER2ROLE = { T="TANK", H="HEALER", D="DPS" }

local function tokenize(msg)
  local s = lower(msg or "")
  s = string.gsub(s, "[^%a%+]+", " ")
  local t = {}
  for w in string.gmatch(s, "%S+") do table.insert(t, w) end
  return t, s
end

-- normalize a string for keyword comparisons (letters/+ only, single spaces, trimmed, lowercased)
local function normalize_for_kw(s)
  s = lower(s or "")
  s = string.gsub(s, "[^%a%+]+", " ")
  s = string.gsub(s, "%s+", " ")
  s = trim(s)
  return s
end

-- keyword hit that supports single-word OR multi-word phrases (and "+")
local function kw_hit(msg, kw)
  kw = kw or ""
  if kw == "" then return false end
  if kw == "+" then
    -- accept any '+' anywhere in the raw message
    return string.find(msg or "", "%+") ~= nil
  end
  local rawNorm = normalize_for_kw(msg)
  local kwNorm  = normalize_for_kw(kw)
  if string.find(kwNorm, " ") then
    -- phrase: match on whole-word boundaries by padding spaces
    local hay    = " " .. rawNorm .. " "
    local needle = " " .. kwNorm .. " "
    return string.find(hay, needle, 1, true) ~= nil
  else
    -- single word: keep the old token semantics
    local toks = tokenize(msg)
    for i=1,table.getn(toks) do
      if toks[i] == kwNorm then return true end
    end
    return false
  end
end

-- detect both role and an optional class hint (even when role was explicit)
local function detectRoleAndClass(tokens)
  local roleFound, classFound = nil, nil
  local n = table.getn(tokens)
  for i=1,n do
    local w = tokens[i]
    if not roleFound then
      local r = ROLE_KEY[w]
      if r then roleFound = r end
    end
    if not classFound then
      if CLASS_KEY[w] then classFound = w
      elseif SPEC2CLASS[w] then classFound = SPEC2CLASS[w]
      end
    end
  end
  if not classFound then
    for i=1,n do
      local c = tokens[i]
      if PURE_DPS[c] then classFound = c; break end
    end
  end
  if not roleFound and classFound and PURE_DPS[classFound] then
    roleFound = "DPS"
  end
  return roleFound, classFound
end

-- class -> allowed roles (letters)
local function AllowedRolesForClass(class)
  class = lower(class or "")
  if class == "warrior"   then return { "T", "D" } end
  if class == "priest"    then return { "H", "D" } end
  if class == "paladin"   then return { "T", "H", "D" } end
  if class == "druid"     then return { "T", "H", "D" } end
  if class == "shaman"    then return { "H", "D" } end
  return { "T", "H", "D" }
end

local function RoleLettersToPrompt(list)
  local labels = { T="tank", H="healer", D="dps" }
  local out = {}
  for i=1,table.getn(list) do
    local r = list[i]
    table.insert(out, labels[r] or r)
  end
  return table.concat(out, " / ")
end

local function IntersectOffered(offered, allowed)
  if not offered or table.getn(offered)==0 then return allowed end
  local setAllowed = {}
  for i=1,table.getn(allowed) do setAllowed[allowed[i]] = true end
  local final = {}
  for j=1,table.getn(offered) do if setAllowed[offered[j]] then table.insert(final, offered[j]) end end
  if table.getn(final)==0 then return allowed end
  return final
end

-- forward declare for capacity filter
local rbHasRoom

-- keep only roles that still have room in RB (T/H/D letters)
local function FilterByCapacity(letters)
  if not letters or table.getn(letters) == 0 then return letters end
  local out = {}
  for i=1,table.getn(letters) do
    local r = letters[i]
    local role = LETTER2ROLE[r]
    if rbHasRoom(role) then table.insert(out, r) end
  end
  return out
end

-- parse possibly-multiple role hints
local function ParseRoleHints(raw)
  raw = lower(raw or "")
  if string.find(raw, "any role") or string.find(raw, "%f[%a]any%f[%A]") or string.find(raw, "%f[%a]either%f[%A]") then
    return { "T", "H", "D" }
  end
  local function firstpos(pat) return string.find(raw, pat) end
  local pos = {}
  pos["T"] = firstpos("%f[%a]tank%w*%f[%A]") or firstpos("%f[%a]prot%w*%f[%A]") or firstpos("%f[%a]bear%f[%A]")
  pos["H"] = firstpos("%f[%a]heal%w*%f[%A]") or firstpos("%f[%a]resto%f[%A]") or firstpos("%f[%a]holy%f[%A]") or firstpos("%f[%a]disc%f[%A]") or firstpos("%f[%a]discipline%f[%A]")
  pos["D"] = firstpos("%f[%a]dps%f[%A]") or firstpos("%f[%a]dd%f[%A]") or firstpos("%f[%a]damage%f[%A]")
           or firstpos("%f[%a]arms%f[%A]") or firstpos("%f[%a]fury%f[%A]") or firstpos("%f[%a]enh%w*%f[%A]")
           or firstpos("%f[%a]elemental%f[%A]") or firstpos("%f[%a]balance%f[%A]") or firstpos("%f[%a]shadow%f[%A]")
           or firstpos("%f[%a]cat%f[%A]") or firstpos("%f[%a]ret%f[%A]") or firstpos("%f[%a]boomkin%f[%A]")
  local list = {}
  if pos["T"] then table.insert(list,{k="T",p=pos["T"]}) end
  if pos["H"] then table.insert(list,{k="H",p=pos["H"]}) end
  if pos["D"] then table.insert(list,{k="D",p=pos["D"]}) end
  table.sort(list, function(a,b) return a.p < b.p end)
  local out = {}
  for i=1,table.getn(list) do table.insert(out, list[i].k) end
  return out
end

-- roles DB
local function ensureRoleBuckets()
  TacticaDB = TacticaDB or {}
  TacticaDB.Tanks   = TacticaDB.Tanks   or {}
  TacticaDB.Healers = TacticaDB.Healers or {}
  TacticaDB.DPS     = TacticaDB.DPS     or {}
end

local function clearAllRoles(name)
  ensureRoleBuckets()
  TacticaDB.Tanks[name]   = nil
  TacticaDB.Healers[name] = nil
  TacticaDB.DPS[name]     = nil
end

local function setRole(name, role)
  ensureRoleBuckets()
  clearAllRoles(name)
  if role == "TANK" then TacticaDB.Tanks[name] = true
  elseif role == "HEALER" then TacticaDB.Healers[name] = true
  elseif role == "DPS" then TacticaDB.DPS[name] = true
  end
  if TacticaRaidBuilder and TacticaRaidBuilder.NotifyRoleAssignmentChanged then
    TacticaRaidBuilder.NotifyRoleAssignmentChanged()
  end
end

-- hard refresh of visual tags (raid + party)
local function refreshRolesUI()
  if type(Tactica_DecorateRaidRoster) == "function" then Tactica_DecorateRaidRoster() end
  if type(Tactica_DecoratePartyFrames) == "function" then Tactica_DecoratePartyFrames() end
  if type(Tactica_DecoratePlayerFrame) == "function" then Tactica_DecoratePlayerFrame() end

  if type(RaidFrame_Update) == "function" then RaidFrame_Update() end
  if type(RaidGroupFrame_Update) == "function" then RaidGroupFrame_Update() end

  if type(PartyMemberFrame_Update) == "function" then
    PartyMemberFrame_Update()
  end

  if pfUI and pfUI.uf and pfUI.uf.raid and pfUI.uf.raid.Show then pfUI.uf.raid:Show() end
end

-- RB capacity check (EXCLUDE-AWARE)
rbHasRoom = function(role)
  local R = RB()
  if not (R and R.state and R.state.size) then return true end
  local size  = R.state.size or 0
  local wantT = R.state.tanks or 0
  local wantH = R.state.healers or 0

  local exclude = (R and R._exclude) or {}

  -- Build a present-name map that works for BOTH raid and party.
  local function GetPresentNameMap()
    local present = {}

    -- Always include player (party roster does not include it via party1..4).
    if UnitName then
      local me = UnitName("player")
      if me and me ~= "" then
        present[me] = true
      end
    end

    local nRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if nRaid and nRaid > 0 then
      local i
      for i = 1, nRaid do
        local name = GetRaidRosterInfo(i)
        if name and name ~= "" then
          present[name] = true
        end
      end
      return present
    end

    -- Party (0..4 members besides player)
    local nParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    local i
    for i = 1, nParty do
      local unit = "party" .. i
      local name = UnitName and UnitName(unit) or nil
      if name and name ~= "" then
        present[name] = true
      end
    end

    return present
  end

  -- Count:
  --  * presentCount = actual group size (exclude-aware) -> used for size cap
  --  * cT/cH/cD = role counts (exclude-aware) -> used for role capacity
  local function GetCounts()
    ensureRoleBuckets()
    local present = GetPresentNameMap()
    local cT, cH, cD = 0, 0, 0
    local presentCount = 0

    local name
    for name in pairs(present) do
      if not exclude[name] then
        presentCount = presentCount + 1
        if TacticaDB.Tanks[name] then
          cT = cT + 1
        elseif TacticaDB.Healers[name] then
          cH = cH + 1
        elseif TacticaDB.DPS[name] then
          cD = cD + 1
        end
      end
    end

    return cT, cH, cD, presentCount
  end

  local currentT, currentH, currentD, presentCount = GetCounts()

  -- Hard cap by actual occupied slots, not only "assigned roles"
  if presentCount >= size then
    return false
  end

  local wantD = size - wantT - wantH
  if wantD < 0 then wantD = 0 end

  local needT = wantT - currentT
  local needH = wantH - currentH
  local needD = wantD - currentD

  if needT < 0 then needT = 0 end
  if needH < 0 then needH = 0 end
  if needD < 0 then needD = 0 end

  -- Keep role capacity aligned with RB's own "Need:" logic.
  -- When role deficits exceed remaining physical slots, reserve slots in T/H/D order.
  local slotsLeft = size - presentCount
  if slotsLeft < 0 then slotsLeft = 0 end
  if needT > slotsLeft then needT = slotsLeft end
  slotsLeft = slotsLeft - needT
  if needH > slotsLeft then needH = slotsLeft end
  slotsLeft = slotsLeft - needH
  if needD > slotsLeft then needD = slotsLeft end

  if role == "TANK" then return needT > 0 end
  if role == "HEALER" then return needH > 0 end
  if role == "DPS" then return needD > 0 end

  return (needT > 0) or (needH > 0) or (needD > 0)
end

-- Role targets from Raid Builder (totals aimed for)
local function GetNeededTotals()
  local R = TacticaRaidBuilder
  local size  = (R and R.state and R.state.size)    or 0
  local wantT = (R and R.state and R.state.tanks)   or 0
  local wantH = (R and R.state and R.state.healers) or 0
  local dBudget = size - wantT - wantH
  if dBudget < 0 then dBudget = 0 end
  return wantT, wantH, dBudget
end

-- totals and counts (EXCLUDE-AWARE for PickBestRole)
local function GetAssignedCounts()
  local R = RB()
  local exclude = (R and R._exclude) or {}

  local present = {}
  local total = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  for i=1,total do
    local nm = GetRaidRosterInfo(i); if nm and nm~="" and not exclude[nm] then present[nm]=true end
  end

  local T = (TacticaDB and TacticaDB.Tanks)   or {}
  local H = (TacticaDB and TacticaDB.Healers) or {}
  local D = (TacticaDB and TacticaDB.DPS)     or {}

  local ct,ch,cd = 0,0,0
  for nm,_ in pairs(present) do
    if     T[nm] then ct=ct+1
    elseif H[nm] then ch=ch+1
    elseif D[nm] then cd=cd+1 end
  end
  return ct, ch, cd
end

-- Pick role in priority order:
-- 1) Missing tank/healer slots first (tank wins ties over healer)
-- 2) If T/H are full, fall back to DPS when offered
-- 3) If nothing is missing, keep deterministic order T > H > D
local function PickBestRole(offeredLetters)
  if not offeredLetters or table.getn(offeredLetters)==0 then return "D" end

  local needT, needH, needD = GetNeededTotals()
  local haveT, haveH, haveD = GetAssignedCounts()

  local missing = { T = math.max(needT - haveT, 0), H = math.max(needH - haveH, 0), D = math.max(needD - haveD, 0) }

  local hasT, hasH, hasD = false, false, false
  for i=1,table.getn(offeredLetters) do
    hasT = hasT or offeredLetters[i]=="T"
    hasH = hasH or offeredLetters[i]=="H"
    hasD = hasD or offeredLetters[i]=="D"
  end

  if hasT and missing.T > 0 then return "T" end
  if hasH and missing.H > 0 then return "H" end

  if hasD and missing.T == 0 and missing.H == 0 then
    return "D"
  end

  if hasT then return "T" end
  if hasH then return "H" end
  if hasD then return "D" end
  return offeredLetters[1]
end

-- invite helpers
local function inviteByName(name)
  if InviteByName then InviteByName(name) end
end

local function ScheduleReinvite(name, role, doAssign, skipCapacity)
  INV._pendingReinvites[lower(name)] = { name=name, role=role, doAssign=doAssign, skipCapacity=skipCapacity and true or false }
end

-- Centralized conversion intent: try to become a raid if not already one
local function EnsureRaidMode(reason)
  local inRaid  = (GetNumRaidMembers  and GetNumRaidMembers()  or 0) > 0
  if inRaid then return true end

  -- If RB size is 5 or less, never convert.
  if not INV_ShouldConvertToRaid() then
    INV._convertWhenFirstJoins = false
    return false
  end

  -- Don't arm conversion unless module is actually active (standalone or RB frame shown).
  if not INV_IsActive() then
    INV._convertWhenFirstJoins = false
    return false
  end

  INV._convertWhenFirstJoins = true
  TryConvertToRaid(reason or "ensure", 10)
  return false
end


local function inviteAndMaybeAssign(name, role, doAssign, skipCapacity)
  -- Capacity (RB) guard
  if role and (not skipCapacity) and not rbHasRoom(role) then
    say(name, "[Tactica]: Thanks! We are currently full on "..string.lower(role)..".")
    return
  end

  local raidN  = (GetNumRaidMembers  and GetNumRaidMembers()  or 0)
  local partyN = (GetNumPartyMembers and GetNumPartyMembers() or 0)
  local amLead = (IsPartyLeader and IsPartyLeader()) and true or false
  local inRaid = raidN > 0

  -- If not in a raid and party is full, convert first and retry invite after conversion
  if (not inRaid) and partyN >= 4 then
    if amLead and ConvertToRaid then
      cfmsg("Party is full; converting to raid before inviting "..name.."...")
      ScheduleReinvite(name, role, doAssign, skipCapacity)
      INV._convertWhenFirstJoins = true
      TryConvertToRaid("party-full", 10)
      return
    else
      cfmsg("Party is full and you're not the leader — can't auto-convert. Ask the leader to convert to a raid.")
      return
    end
  end

  -- Try to ensure (or will become) a raid
  if not inRaid then
    EnsureRaidMode("pre-invite")
  end

  -- Remember last attempted invite details (for re-invite if they were grouped)
  INV._recentInvite[lower(name)] = {
    name        = name,
    role        = role,
    doAssign    = doAssign and true or false,
    skipCapacity= skipCapacity and true or false,
    ts          = now(),
  }

  -- Proceed with invite now
  inviteByName(name)

  -- Only keep pending role assignment; do not whisper "Invited" at all.
  if doAssign and role then
    INV.pendingRoles[name] = role
  end
end

-- confirm queue
local function QueuePush(name, role, classHint, offered, rbMode)
  local key = lower(name or "")
  if INV._showing and lower(INV._showing.name) == key then
    if role then INV._showing.role = role end
    if classHint then INV._showing.class = classHint end
    if offered and table.getn(offered)>0 then INV._showing.offered = offered end
    if rbMode ~= nil then INV._showing.rb = rbMode end
    INV.ShowConfirm(INV._showing.name, INV._showing.role, INV._showing.class, INV._showing.offered, INV._showing.rb)
    return
  end
  local existing = INV._enq[key]
  if existing then
    if role then existing.role = role end
    if classHint then existing.class = classHint end
    if offered and table.getn(offered)>0 then existing.offered = offered end
    if rbMode ~= nil then existing.rb = rbMode end
    existing.ts = now()
    return
  end
  local item = { name=name, role=role, class=classHint, offered=offered, ts=now(), rb=rbMode and true or false }
  table.insert(INV._queue, item)
  INV._enq[key] = item
end

local function QueuePop()
  if table.getn(INV._queue) == 0 then return nil end
  local item = table.remove(INV._queue, 1)
  if item and item.name then INV._enq[lower(item.name)] = nil end
  return item
end

local function QueueShowNext()
  if INV._showing then return end
  local nextItem = QueuePop()
  if not nextItem then return end
  INV._showing = nextItem
  INV.ShowConfirm(nextItem.name, nextItem.role, nextItem.class, nextItem.offered, nextItem.rb)
end

-- intent filter for RB confirm mode
local INVITE_WORDS = { invite=true, inv=true, ["+"]=true, inviteme=true, invpls=true, invplz=true }
local function hasIntent(tokens)
  for i=1,table.getn(tokens) do
    local w = tokens[i]
    if INVITE_WORDS[w] or ROLE_KEY[w] or CLASS_KEY[w] or SPEC2CLASS[w] then return true end
  end
  return false
end

-- === Gearcheck helpers (RB only) ===
local AWAIT_SEC        = 90
local AWAIT_GEAR_SEC   = 90

local function GearLine(n)
  if n==0 then return "0 – Starter / Dungeon blues" end
  if n==1 then return "1 – ZG / AQ20 / MC" end
  if n==2 then return "2 – BWL / T2" end
  if n==3 then return "3 – AQ40 / T2.5" end
  if n==4 then return "4 – Naxx / T3" end
  if n==5 then return "5 – Kara40 / T3.5" end
  return ""
end

local function GearLabelOnly(n)
  local line = GearLine(n) or ""
  local label = string.match(line, "^%s*%d+%s*–%s*(.+)$")
  if label then return label end
  label = string.match(line, "^%s*%d+%s*%-%s*(.+)$")
  if label then return label end
  return ""
end

-- fresh or stale-session gear prompt
local function StartGearcheck(name)
  if not INV.rbGearEnabled or INV.rbGearThreshold == nil then return false end
  local tNow = now()
  local active = INV.awaitingGear[name] and (tNow <= INV.awaitingGear[name])

  -- if currently active prompt exists, don't re-spam the entire scale
  if INV._gearAsked[name] and active then
    say(name, "[Tactica]: Please reply only with a number 0-5, or a range like '2-3'.")
    return true
  end

  -- (re)start full prompt (handles stale session where _gearAsked was set but timer expired)
  INV._gearAsked[name] = true
  local intro = "[Tactica]: Gearcheck – please grade the MAJORITY of your gear (9+/18 itemslots) using the scale below. Reply only with a single number (e.g. '2' or '3') or a range (e.g. '2-3')."
  say(name, intro)
  -- Compressed scale into a single summary line
  say(name, "[Tactica]: (0)=Blues / (1)=ZG-AQ20-MC / (2)=BWL-T2 / (3)=AQ40-T2.5 / (4)=Naxx-T3 / (5)=K40-T3.5")
  INV.awaitingGear[name] = tNow + AWAIT_GEAR_SEC
  return true
end

local function ParseGearReply(msg)
  local s = trim(msg or "")

  -- Range like "2-3" (strictly 0..5 on both ends)
  local a, b = string.match(s, "^(%d)%s*[-–]%s*(%d)$")
  if a and b then
    local n1, n2 = tonumber(a), tonumber(b)
    if not n1 or not n2 then return nil end
    if n1 < 0 or n1 > 5 or n2 < 0 or n2 > 5 then return nil end
    local avg = (n1 + n2) / 2
    if math.abs(avg - math.floor(avg) - 0.5) < 0.0001 then
      return math.floor(avg)
    else
      return math.floor(avg + 0.5)
    end
  end

  -- Single digit "0".."5" only
  local n = tonumber(string.match(s, "^(%d)$") or "")
  if n == nil then return nil end
  if n < 0 or n > 5 then return nil end
  return n
end

local function ContinueAfterGear(name, passed)
  local pend = INV._gearPending[name]
  INV.awaitingGear[name] = nil
  INV._gearAsked[name]   = nil
  INV._gearAfterRole[name] = nil
  INV._gearPending[name] = nil
  if not passed then
    say(name, "[Tactica]: Thank you! For this raid, however, we are prioritizing higher gear. Please check future raids.")
    INV._sessionIgnores[lower(name)] = true
    return
  end
  if not pend then return end
  if pend.act == "invite" then
    inviteAndMaybeAssign(name, pend.role, pend.doAssign, pend.skipCapacity and true or false)
  elseif pend.act == "queue" then
    QueuePush(name, pend.role, pend.class, pend.offered, true)
    QueueShowNext()
  end
end

-- Background watcher: expire gear sessions exactly at 90s and optionally whisper again
if not INV._watch then
  INV._watch = CreateFrame("Frame")
  local acc = 0
  INV._watch:SetScript("OnUpdate", function(_, elapsed)
    acc = (acc or 0) + (elapsed or 0)
    if acc < 0.35 then return end
    acc = 0
    local tNow = now()
    for name, untilT in pairs(INV.awaitingGear) do
      if untilT and tNow > untilT then
        INV.awaitingGear[name] = nil
        INV._gearAsked[name]   = nil
        INV._gearAfterRole[name] = nil
        INV._gearPending[name] = nil
        if INV._gearTimeoutRemind then
          say(name, "[Tactica]: Gearcheck timed out. Whisper again to continue.")
        end
      end
    end
  end)
end

-- active (auto-invite) path
local function handleActive(author, msg, keyword, autoAssign, rbMode)
  if IsNameInGroup(author) then return end
  if INV._sessionIgnores[lower(author)] then return end

  local tokens, raw = tokenize(msg)

  -- Hit detection (supports single-word, "+", and multi-word phrases)
  local kw = trim(keyword or "")
  local hit = false
  if rbMode then
    if kw ~= "" then
      hit = kw_hit(msg, kw)
    else
      -- RB can run keywordless based on intent (role/class/invite words)
      hit = hasIntent(tokens)
    end
  else
    -- Standalone requires a keyword (word, "+", or phrase)
    if kw ~= "" then
      hit = kw_hit(msg, kw)
    end
  end
  if not hit then return end

  -- RB autoinvite can be keywordless; apply gear gate if enabled
  if not autoAssign then
    if rbMode and INV.rbGearEnabled and INV.rbGearThreshold ~= nil then
      INV._gearPending[author] = { act="invite", role=nil, class=nil, offered=nil, rb=true, doAssign=false, skipCapacity=false }
      StartGearcheck(author)
      return
    end
    inviteAndMaybeAssign(author, nil, false, not rbMode)
    return
  end

  -- Role parsing
  local role, classHint = detectRoleAndClass(tokens)
  local allowed = AllowedRolesForClass(classHint)
  local hinted  = ParseRoleHints(msg)
  local offered = (hinted and table.getn(hinted)>0) and IntersectOffered(hinted, allowed) or nil

  if rbMode then
    if role then
      if INV.rbGearEnabled and INV.rbGearThreshold ~= nil then
        INV._gearPending[author] = { act="invite", role=role, class=classHint, rb=true, doAssign=true, skipCapacity=false }
        StartGearcheck(author)
        return
      end
      inviteAndMaybeAssign(author, role, true, false)
      return
    end
    if offered and table.getn(offered) >= 1 and not (table.getn(offered) == 3 and classHint == nil) then
      local best = PickBestRole(FilterByCapacity(offered))
      local rolePicked = LETTER2ROLE[best]
      if INV.rbGearEnabled and INV.rbGearThreshold ~= nil then
        INV._gearPending[author] = { act="invite", role=rolePicked, class=classHint, offered=offered, rb=true, doAssign=true, skipCapacity=false }
        StartGearcheck(author)
        return
      end
      inviteAndMaybeAssign(author, rolePicked, true, false)
      return
    end
    local prompt = "[Tactica]: What role are you? ("..RoleLettersToPrompt(allowed)..")"
    say(author, prompt)
    INV.awaitingRole[author] = now() + AWAIT_SEC
    INV.awaitCtx[author]     = "active"
    INV.lastPrompt[author]   = { allowed = allowed }
    if INV.rbGearEnabled and INV.rbGearThreshold ~= nil then
      INV._gearAfterRole[author] = true
    end
    return
  end

  -- Standalone path unchanged beyond here
  if offered and table.getn(offered) >= 2 then
    local prompt = "[Tactica]: What role are you? ("..RoleLettersToPrompt(allowed).."). Please reply with ONE role only."
    say(author, prompt)
    INV.awaitingRole[author] = now() + AWAIT_SEC
    INV.awaitCtx[author]     = "active-single"
    INV.lastPrompt[author]   = { allowed = allowed }
    return
  end

  if role then
    inviteAndMaybeAssign(author, role, true, true)
    return
  end
  if offered and table.getn(offered) == 1 then
    inviteAndMaybeAssign(author, LETTER2ROLE[offered[1]], true, true)
    return
  end

  local prompt = "[Tactica]: What role are you? ("..RoleLettersToPrompt(allowed).."). Please reply with ONE role only."
  say(author, prompt)
  INV.awaitingRole[author] = now() + AWAIT_SEC
  INV.awaitCtx[author]     = "active-single"
  INV.lastPrompt[author]   = { allowed = allowed }
end

-- RB confirm ask (auto-invite OFF, auto-assign ON)
local function handleRBConfirmGearOnly(author, msg)
  if IsNameInGroup(author) then return end
  if INV._sessionIgnores[lower(author)] then return end
  local tokens, _ = tokenize(msg)
  if not hasIntent(tokens) then return end
  if not (INV.rbGearEnabled and (INV.rbGearThreshold ~= nil)) then return end
  INV._gearPending[author] = { act="queue", role=nil, class=nil, offered=nil, rb=true, doAssign=false, skipCapacity=true }
  StartGearcheck(author)
end

local function handleRBConfirmAsk(author, msg)
  if IsNameInGroup(author) then return end
  if INV._sessionIgnores[lower(author)] then return end

  local tokens, _ = tokenize(msg)
  if not hasIntent(tokens) then return end

  local _, classHint = detectRoleAndClass(tokens)
  local allowed = AllowedRolesForClass(classHint)

  local hinted = ParseRoleHints(msg)
  local offeredLetters = (hinted and table.getn(hinted)>0) and IntersectOffered(hinted, allowed) or nil
  local filtered = FilterByCapacity(offeredLetters)

  local gearOn = INV.rbGearEnabled and (INV.rbGearThreshold ~= nil)

  if filtered and table.getn(filtered) >= 2 then
    if gearOn then
      INV._gearPending[author] = { act="queue", role=nil, class=classHint, offered=filtered, rb=true, doAssign=true, skipCapacity=false }
      StartGearcheck(author); return
    end
    QueuePush(author, nil, classHint, filtered, true)
    QueueShowNext(); return
  elseif filtered and table.getn(filtered) == 1 then
    local singleRole = LETTER2ROLE[filtered[1]]
    if gearOn then
      INV._gearPending[author] = { act="queue", role=singleRole, class=classHint, offered=filtered, rb=true, doAssign=true, skipCapacity=false }
      StartGearcheck(author); return
    end
    QueuePush(author, singleRole, classHint, filtered, true)
    QueueShowNext(); return
  elseif offeredLetters and table.getn(offeredLetters) >= 1 then
    if table.getn(offeredLetters) == 1 then
      say(author, "[Tactica]: Thanks! We are currently full on "..string.lower(LETTER2ROLE[offeredLetters[1]])..".")
    else
      say(author, "[Tactica]: Thanks! We are currently full on the roles you mentioned.")
    end
    return
  end

  local prompt = "Tactica: What role are you? ("..RoleLettersToPrompt(allowed)..")"
  say(author, prompt)
  INV.awaitingRole[author] = now() + AWAIT_SEC
  INV.awaitCtx[author]     = "rb-confirm"
  INV.lastPrompt[author]   = { allowed = allowed }
  if gearOn then INV._gearAfterRole[author] = true end
end

-- popup UI
function INV.ShowConfirm(name, role, classHint, offeredLetters, rbMode)
  if not INV._confirm then
    local p = CreateFrame("Frame", "TacticaInviteConfirm", UIParent)
    INV._confirm = p
    p:SetWidth(330); p:SetHeight(180)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    p:SetBackdrop({
      bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
      tile=true, tileSize=16, edgeSize=32,
      insets={left=11,right=12,top=12,bottom=11}
    })
    p:SetBackdropColor(0,0,0,1)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetToplevel(true)
    p:SetClampedToScreen(true)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOP", p, "TOP", 0, -12)
    p.title:SetText("Raid Join Request")

    p.top = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.top:SetPoint("TOP", p, "TOP", 0, -40)
    p.top:SetWidth(300); p.top:SetJustifyH("CENTER")

    p.bot = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.bot:SetPoint("TOP", p.top, "BOTTOM", 0, -6)
    p.bot:SetWidth(300); p.bot:SetJustifyH("CENTER")

    -- Dynamic role selection bar (for ambiguous offers)
    p.roleBar = CreateFrame("Frame", nil, p)
    p.roleBar:SetPoint("BOTTOM", p, "BOTTOM", 0, 44)
    p.roleBar:SetWidth(1)
    p.roleBar:SetHeight(24)

    p.BuildRoleButtons = function(list, onPick)
      if p.roleButtons then
        for i=1,table.getn(p.roleButtons) do
          local b = p.roleButtons[i]
          if b then b:Hide(); b:SetParent(nil) end
        end
      end
      p.roleButtons = {}

      if not list or table.getn(list) <= 1 then return end
      local labels = { T="Invite as Tank", H="Invite as Healer", D="Invite as DPS" }
      local pad, w, h = 5, 100, 22
      local totalW = table.getn(list)*w + (table.getn(list)-1)*pad
      local startX = -math.floor(totalW/2)
      for i=1,table.getn(list) do
        local r = list[i]
        local b = CreateFrame("Button", nil, p.roleBar, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(h)
        b:SetPoint("LEFT", p.roleBar, "CENTER", startX + (i-1)*(w+pad), 0)
        b:SetText(labels[r] or r)
        b:SetScript("OnClick", function()
          if onPick then onPick(r) end
        end)
        table.insert(p.roleButtons, b)
      end
    end

    -- Centered main buttons
    local b1 = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b1:SetWidth(130); b1:SetHeight(22)
    b1:SetPoint("BOTTOM", p, "BOTTOM", 0, 20)
    b1:SetText("Invite & assign")
    p.btnAssign = b1

    local b2 = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b2:SetWidth(80); b2:SetHeight(22)
    b2:SetPoint("RIGHT", b1, "LEFT", -6, 0)
    b2:SetText("Invite")
    p.btnInvite = b2

    local b3 = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b3:SetWidth(80); b3:SetHeight(22)
    b3:SetPoint("LEFT", b1, "RIGHT", 6, 0)
    b3:SetText("Skip")
    p.btnClose = b3

    -- Grey note under buttons
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.note:SetPoint("BOTTOM", p, "BOTTOM", 0, 4)
    p.note:SetWidth(300); p.note:SetJustifyH("CENTER")
    if p.note.SetTextColor then p.note:SetTextColor(0.7,0.7,0.7) end
    p.note:SetText("Note: Skipping a player prevents them from triggering this question or popup again for this session.")
  end

  local p = INV._confirm
  p:Show()

  -- Adjust control positions for RB confirm popup only
  if rbMode then
    p.roleBar:ClearAllPoints();  p.roleBar:SetPoint("BOTTOM", p, "BOTTOM", 0, 44 + 30)
    p.btnAssign:ClearAllPoints(); p.btnAssign:SetPoint("BOTTOM", p, "BOTTOM", 0, 20 + 30)
    p.btnInvite:ClearAllPoints(); p.btnInvite:SetPoint("RIGHT", p.btnAssign, "LEFT", -6, 0)
    p.btnClose:ClearAllPoints();  p.btnClose:SetPoint("LEFT",  p.btnAssign, "RIGHT",  6, 0)
    p.note:ClearAllPoints();      p.note:SetPoint("BOTTOM", p, "BOTTOM", 0, 4 + 10)
  else
    p.roleBar:ClearAllPoints();  p.roleBar:SetPoint("BOTTOM", p, "BOTTOM", 0, 44)
    p.btnAssign:ClearAllPoints(); p.btnAssign:SetPoint("BOTTOM", p, "BOTTOM", 0, 20)
    p.btnInvite:ClearAllPoints(); p.btnInvite:SetPoint("RIGHT", p.btnAssign, "LEFT", -6, 0)
    p.btnClose:ClearAllPoints();  p.btnClose:SetPoint("LEFT",  p.btnAssign, "RIGHT",  6, 0)
    p.note:ClearAllPoints();      p.note:SetPoint("BOTTOM", p, "BOTTOM", 0, 4)
  end

  -- Hide 'Invite & assign' when RB is not auto-assigning roles
  if rbMode and (not INV.rbAutoRoles) and p.btnAssign then
    p.btnAssign:Hide()
  else
    if p.btnAssign then p.btnAssign:Show() end
  end

  local function LettersToWords(list)
    local label = { T="Tank", H="Healer", D="DPS" }
    if not list or table.getn(list)==0 then return "Role" end
    local ord = { T=1, H=2, D=3 }
    local tmp = {}
    for i=1,table.getn(list) do tmp[i] = list[i] end
    table.sort(tmp, function(a,b) return (ord[a] or 99) < (ord[b] or 99) end)
    if table.getn(tmp) == 1 then
      return label[tmp[1]] or "Role"
    elseif table.getn(tmp) == 2 then
      return (label[tmp[1]] or tmp[1]) .. " or " .. (label[tmp[2]] or tmp[2])
    else
      return (label[tmp[1]] or tmp[1]) .. ", " .. (label[tmp[2]] or tmp[2]) .. " or " .. (label[tmp[3]] or tmp[3])
    end
  end

  local cls = classHint and (", "..string.upper(string.sub(classHint,1,1))..string.sub(classHint,2)) or ""
  p.top:SetText("Would you like to invite and assign roles for:")

  local letStr, nameStr
  if role then
    letStr  = ROLE_LET[role] or "?"
    nameStr = ROLE_NAME[role] or "Role"
  elseif offeredLetters and table.getn(offeredLetters) >= 1 then
    local ord = { T=1, H=2, D=3 }
    local tmp = {}
    for i=1,table.getn(offeredLetters) do tmp[i] = offeredLetters[i] end
    table.sort(tmp, function(a,b) return (ord[a] or 99) < (ord[b] or 99) end)
    letStr  = table.concat(tmp, "/")
    nameStr = LettersToWords(tmp)
  else
    letStr, nameStr = "?", "Role"
  end

  if rbMode and (not INV.rbAutoRoles) then
    p.bot:SetText(name..cls..".")
  else
    p.bot:SetText(name.." – "..letStr.." ("..nameStr..")"..cls..".")
  end

  -- gear info line (RB Mode)
  if rbMode and INV.rbGearEnabled and (INV.rbGearThreshold ~= nil) then
    local rating = INV._gearRatings and INV._gearRatings[name]
    local gearLine
    if rating == nil then
      gearLine = "Gear: Not checked."
    else
      local lbl = GearLabelOnly(rating)
      if lbl ~= "" then gearLine = "Gear: " .. tostring(rating) .. " – " .. lbl .. "."
      else gearLine = "Gear: " .. tostring(rating) .. "." end
    end
    p.bot:SetText(p.bot:GetText() .. "\n" .. gearLine)
  end

  p.BuildRoleButtons(offeredLetters, function(letterPicked)
    local rolePicked = LETTER2ROLE[letterPicked]
    inviteAndMaybeAssign(name, rolePicked, true)
    INV._showing = nil
    p:Hide()
    QueueShowNext()
  end)

  p.btnAssign:SetScript("OnClick", function()
    local chosenRole = role
    if not chosenRole then
      local letters = offeredLetters or AllowedRolesForClass(classHint)
      local best = PickBestRole(letters)
      chosenRole = LETTER2ROLE[best]
    end
    inviteAndMaybeAssign(name, chosenRole, true)
    INV._showing = nil
    p:Hide()
    QueueShowNext()
  end)

  p.btnInvite:SetScript("OnClick", function()
    inviteAndMaybeAssign(name, role, false)
    INV._showing = nil
    p:Hide()
    QueueShowNext()
  end)

  p.btnClose:SetScript("OnClick", function()
    INV._showing = nil
    p:Hide()
    INV._sessionIgnores[lower(name)] = true
    QueueShowNext()
  end)
end

-- whisper routing
local function onWhisper(author, msg)
  author = cleanName(author or "")
  if INV._sessionIgnores[lower(author)] then return end
 
 -- If they tripped the "already in a group" check earlier and re-whispered within 90s, re-invite immediately using the same parameters as before.
  local gr = INV._groupRetry[lower(author)]
  if gr and now() <= (gr.untilT or 0) then
    inviteAndMaybeAssign(author, gr.role, gr.doAssign, gr.skipCapacity)
    INV._groupRetry[lower(author)] = nil
    return
  end

  if INV.enabled then
    handleActive(author, msg, INV.keyword, INV.autoAssign, false)
    return
  end

  if RBFrameShown() then
    if INV.rbEnabled then
      handleActive(author, msg, INV.rbKeyword, INV.rbAutoRoles, true)
      return
    end
    if (not INV.rbEnabled) and INV.rbAutoRoles then
      handleRBConfirmAsk(author, msg)
      return
    end
    if (not INV.rbEnabled) and (not INV.rbAutoRoles) and INV.rbGearEnabled and (INV.rbGearThreshold ~= nil) then
      handleRBConfirmGearOnly(author, msg)
      return
    end
  end
end

local function onWhisperReply(author, msg)
  author = cleanName(author or "")
  if INV._sessionIgnores[lower(author)] then return true end

  -- Gear reply first
  local gUntil = INV.awaitingGear[author]
  if gUntil and now() <= gUntil then
    local val = ParseGearReply(msg)
    INV._gearRatings[author] = val
    if val == nil then
      say(author, "[Tactica]: Please reply with a number 0-5, or a range like '2-3', using the gear scale above.")
      INV.awaitingGear[author] = now() + AWAIT_GEAR_SEC
      return true
    end
    local passed = (INV.rbGearThreshold == nil) or (val >= INV.rbGearThreshold)
    ContinueAfterGear(author, passed)
    return true
  end

  local untilT = INV.awaitingRole[author]
  if not untilT or now() > untilT then return false end

  local tokens,_ = tokenize(msg)
  local roleDetected, classHintDetected = detectRoleAndClass(tokens)
  local ctx = INV.awaitCtx[author]

  local function clearAwait()
    INV.awaitingRole[author] = nil
    INV.awaitCtx[author]     = nil
    INV.lastPrompt[author]   = nil
  end

  if ctx == "active-single" then
    local allowed = (INV.lastPrompt[author] and INV.lastPrompt[author].allowed) or AllowedRolesForClass(classHintDetected)
    local hinted  = ParseRoleHints(msg)
    local letters = (hinted and table.getn(hinted)>0) and IntersectOffered(hinted, allowed) or {}

    if (table.getn(letters) == 0) and roleDetected then
      local let = ROLE_LET[roleDetected]
      if let then letters = { let } end
    end

    if table.getn(letters) ~= 1 then
      local prompt = "[Tactica]: Please reply with ONE role only: "..RoleLettersToPrompt(allowed).."."
      say(author, prompt)
      INV.awaitingRole[author] = now() + AWAIT_SEC
      INV.awaitCtx[author]     = "active-single"
      INV.lastPrompt[author]   = { allowed = allowed }
      return true
    end

    local chosen = LETTER2ROLE[letters[1]]
    clearAwait()
    inviteAndMaybeAssign(author, chosen, true, true)
    return true
  end

  if ctx == "active" then
    local _, classHint2 = detectRoleAndClass(tokens)
    local allowed = (INV.lastPrompt[author] and INV.lastPrompt[author].allowed) or AllowedRolesForClass(classHint2)
    local hinted  = ParseRoleHints(msg)
    local letters = (hinted and table.getn(hinted)>0) and IntersectOffered(hinted, allowed) or nil
    local filtered = FilterByCapacity(letters)
    clearAwait()

    if filtered and table.getn(filtered) >= 1 then
      local best = PickBestRole(filtered)
      local role = LETTER2ROLE[best]
      if INV.rbGearEnabled and INV.rbGearThreshold ~= nil and INV._gearAfterRole[author] then
        INV._gearPending[author] = { act="invite", role=role, class=classHint2, rb=true, doAssign=true, skipCapacity=false }
        StartGearcheck(author)
        return true
      end
      inviteAndMaybeAssign(author, role, true, false)
      return true
    end

    if letters and table.getn(letters) >= 1 then
      if table.getn(letters) == 1 then
        say(author, "[Tactica]: Thanks! We are currently full on "..string.lower(LETTER2ROLE[letters[1]])..".")
      else
        say(author, "[Tactica]: Thanks! We are currently full on the roles you mentioned.")
      end
      return true
    end

    local allowed2 = AllowedRolesForClass(classHint2)
    say(author, "[Tactica]: Please reply with: "..RoleLettersToPrompt(allowed2)..".")
    INV.awaitingRole[author] = now() + AWAIT_SEC
    INV.awaitCtx[author]     = "active"
    INV.lastPrompt[author]   = { allowed = allowed2 }
    return true
  end

  -- RB confirm flow (popup)
  local role, classHint = roleDetected, classHintDetected
  clearAwait()

  if ctx == "rb-confirm" then
    local allowed = (INV.lastPrompt[author] and INV.lastPrompt[author].allowed) or AllowedRolesForClass(classHint)
    local hinted  = ParseRoleHints(msg)
    local letters = (hinted and table.getn(hinted)>0) and IntersectOffered(hinted, allowed) or nil
    local filtered = FilterByCapacity(letters)
    local gearOnAfter = INV.rbGearEnabled and INV.rbGearThreshold ~= nil and INV._gearAfterRole[author]

    if filtered and table.getn(filtered) >= 2 then
      if gearOnAfter then
        INV._gearPending[author] = { act="queue", role=nil, class=classHint, offered=filtered, rb=true, doAssign=true, skipCapacity=false }
        StartGearcheck(author); return true
      end
      QueuePush(author, nil, classHint, filtered, true); QueueShowNext(); return true
    elseif filtered and table.getn(filtered) == 1 then
      local singleRole = LETTER2ROLE[filtered[1]]
      if gearOnAfter then
        INV._gearPending[author] = { act="queue", role=singleRole, class=classHint, offered=filtered, rb=true, doAssign=true, skipCapacity=false }
        StartGearcheck(author); return true
      end
      QueuePush(author, singleRole, classHint, filtered, true); QueueShowNext(); return true
    else
      if letters and table.getn(letters) >= 1 then
        if table.getn(letters) == 1 then
          say(author, "[Tactica]: Thanks! We are currently full on "..string.lower(LETTER2ROLE[letters[1]])..".")
        else
          say(author, "[Tactica]: Thanks! We are currently full on the roles you mentioned.")
        end
        return true
      end
      if role then
        if rbHasRoom(role) then
          if gearOnAfter then
            INV._gearPending[author] = { act="queue", role=role, class=classHint, offered=nil, rb=true, doAssign=true, skipCapacity=false }
            StartGearcheck(author); return true
          end
          QueuePush(author, role, classHint, nil, true); QueueShowNext()
        else
          say(author, "[Tactica]: Thanks! We are currently full on "..string.lower(role)..".")
        end
      else
        local allowed2 = AllowedRolesForClass(classHint)
        say(author, "[Tactica]: Please reply with: "..RoleLettersToPrompt(allowed2)..".")
        INV.awaitingRole[author] = now() + AWAIT_SEC
        INV.awaitCtx[author]     = "rb-confirm"
        INV.lastPrompt[author]   = { allowed = allowed2 }
        if gearOnAfter then INV._gearAfterRole[author] = true end
      end
    end
    return true
  end

  return true
end

local function FlushPendingRolesInGroup()
  local inRaid = {}
  local rn = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  for i=1,rn do
    local nm = GetRaidRosterInfo(i)
    if nm and nm ~= "" then inRaid[nm] = true end
  end

  local inParty = {}
  local me = UnitName and UnitName("player")
  if me and me ~= "" then inParty[me] = true end
  local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  for i=1,pn do
    local u = "party"..i
    if UnitExists and UnitExists(u) then
      local nm = UnitName(u)
      if nm and nm ~= "" then inParty[nm] = true end
    end
  end

  for nm, role in pairs(INV.pendingRoles) do
    if (inRaid[nm] or inParty[nm]) then
      setRole(nm, role)

      local let = ROLE_LET[role] or "?"
      local rnm = ROLE_NAME[role] or role or "?"
      say(nm, "[Tactica]: You are marked as '"..let.."' ("..rnm..") in the group list.")

      INV.pendingRoles[nm] = nil
      refreshRolesUI()
    end
  end
end

-- events
INV._evt = CreateFrame("Frame")
INV._evt:RegisterEvent("CHAT_MSG_WHISPER")
INV._evt:RegisterEvent("RAID_ROSTER_UPDATE")
INV._evt:RegisterEvent("ADDON_LOADED")
INV._evt:RegisterEvent("PARTY_MEMBERS_CHANGED")
INV._evt:RegisterEvent("PARTY_LEADER_CHANGED")
INV._evt:RegisterEvent("CHAT_MSG_SYSTEM")
INV._evt:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "Tactica" then
  -- Sync RB -> Invite flags on reload
  local S = TacticaDB and TacticaDB.Builder
  INV.rbEnabled     = false                    -- keep auto-invite OFF unless RB toggles it
  INV.rbKeyword     = ""
  INV.rbAutoRoles   = (S and S.aiAutoRoles) and true or false

  -- Gearcheck to persist across reloads (optional):
  if S and S.autoGear and S.gearScale ~= nil then
    INV.rbGearEnabled   = true
    INV.rbGearThreshold = S.gearScale
  else
    INV.rbGearEnabled   = false
    INV.rbGearThreshold = nil
  end
  return

  elseif event == "CHAT_MSG_WHISPER" then
    local msg, author = arg1, arg2
    author = cleanName(author)
    if onWhisperReply(author, msg) then return end
    onWhisper(author, msg)

  elseif event == "CHAT_MSG_SYSTEM" then
    local sys = arg1 or ""

    local who
    if ERR_ALREADY_IN_GROUP_S then
      local patt = string.gsub(ERR_ALREADY_IN_GROUP_S, "%%s", "(.+)")
      who = string.match(sys, patt)
    end
    if not who then
      who = string.match(sys, "^(.-) is already in a group%.?$")
    end

    if who and who ~= "" then
      local name  = cleanName(who)
      local lname = lower(name)

      INV._groupWarned = INV._groupWarned or {}
      if not INV._groupWarned[lname] then
        if INV_IsActive() then
          say(name, "[Tactica]: You are in group - please leave and write to me again.")
        end
        INV._groupWarned[lname] = true
      end

      local ri = INV._recentInvite[lname]
      INV._groupRetry[lname] = {
        untilT       = now() + AWAIT_SEC,
        role         = ri and ri.role or nil,
        doAssign     = ri and ri.doAssign or false,
        skipCapacity = ri and ri.skipCapacity or false,
      }
    end

  elseif event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_LEADER_CHANGED" then
    FlushPendingRolesInGroup()

    if INV_ShouldConvertToRaid() then
      TryConvertToRaid("roster-event", 6)
    else
      INV._convertWhenFirstJoins = false
      INV._pendingReinvites = {}
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    if (GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0) then
      INV._convertWhenFirstJoins = false

      local reinv = INV._pendingReinvites
      INV._pendingReinvites = {}
      for _, pend in pairs(reinv) do
        inviteAndMaybeAssign(pend.name, pend.role, pend.doAssign, pend.skipCapacity)
      end
    end

    FlushPendingRolesInGroup()
  end
end)

-- standalone UI
local function setPH(e) e._ph="Keyword"; e:SetText(e._ph); if e.SetTextColor then e:SetTextColor(0.6,0.6,0.6) end end
local function isPH(e) return e and e._ph and e:GetText()==e._ph end

function INV.Open()
  if INV.frame then INV.frame:Show(); return end

  local f = CreateFrame("Frame", "TacticaInviteFrame", UIParent)
  INV.frame = f
  f:SetWidth(260); f:SetHeight(120)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({
      bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
      tile=true, tileSize=16, edgeSize=32,
      insets={left=11,right=12,top=12,bottom=11}
    })
    f:SetBackdropColor(0,0,0,1)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)

  local title = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -16)
  title:SetText("|cff33ff99Auto Invite|r")

  local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -45)
  lbl:SetText("Select keyword:")

  local e = CreateFrame("EditBox", "TacticaInviteKeyword", f, "InputBoxTemplate")
  INV.ui.edit = e
  e:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
  e:SetWidth(90); e:SetHeight(18); e:SetAutoFocus(false)
  setPH(e)
  e:SetScript("OnEditFocusGained", function() if isPH(e) then e:SetText(""); e:SetTextColor(1,1,1) end end)
  e:SetScript("OnEditFocusLost", function() if trim(e:GetText() or "")=="" then setPH(e) end end)
  e:SetScript("OnEnterPressed", function() INV.ui.btn:Click() end)
  e:SetScript("OnEscapePressed", function() e:ClearFocus() end)

  local cb = CreateFrame("CheckButton", "TacticaInviteAutoAssign", f, "UICheckButtonTemplate")
  INV.ui.cb = cb
  INV.autoAssign = false
  cb:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -5)
  cb:SetWidth(20); cb:SetHeight(20)
  getglobal("TacticaInviteAutoAssignText"):SetText("Auto-assign roles")
  cb:SetChecked(INV.autoAssign and true or false)
  cb:SetScript("OnClick", function()
    INV.autoAssign = this:GetChecked() and true or false
    cfmsg("Auto-Assign roles "..(INV.autoAssign and "|cff00ff00ENABLED|r" or "|cffff5555DISABLED|r").." (Standalone).")
  end)

  local off = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  INV.ui.off = off
  off:SetWidth(70); off:SetHeight(20)
  off:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 13)
  off:SetText("Hide")
	off:SetScript("OnClick", function()
	  f:Hide()
	  if INV.enabled then
		cfmsg("Auto-Invite (standalone) is still running in the background. Use /ttai or /tt autoinvite to reopen.")
	  end
	end)

  local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  INV.ui.btn = go
  go:SetWidth(110); go:SetHeight(20)
  go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 13)
  go:SetText("Enable")
	go:SetScript("OnClick", function()
	  if INV.enabled then
		INV.enabled = false
		INV.awaitingRole, INV.awaitCtx, INV.pendingRoles = {}, {}, {}
		go:SetText("Enable")
		cfmsg("Auto-Invite (standalone) disabled.")
	  else
		local kw = e:GetText() or ""
		if isPH(e) or trim(kw)=="" then
		  cfmsg("|cffff5555Please enter a keyword before enabling.|r"); return
		end
		INV.keyword = trim(kw)
		INV.enabled = true
		go:SetText("Disable")
		cfmsg(string.format(
		  "Auto-Invite (standalone) enabled (keyword: |cffffff00%s|r). " ..
		  "It will run in the background even if you close this window. " ..
		  "Auto-assign roles: %s.",
		  INV.keyword,
		  (INV.autoAssign and "|cff00ff00ON|r" or "|cffff5555OFF|r")
		))
	  end
	end)
end

-- slash
SLASH_TTACTINV1 = "/ttai"
SLASH_TTACTINV2 = "/ttautoinvite"
SlashCmdList["TTACTINV"] = function() TacticaInvite.Open() end
