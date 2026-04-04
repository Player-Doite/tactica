-- TacticaComposition.lua - Raid-Helper composition import/mapping tool

TacticaComposition = TacticaComposition or {}
local TC = TacticaComposition
local FindAutoMatch

local TITLE_R, TITLE_G, TITLE_B = 0.2, 1.0, 0.6

local function cfmsg(msg)
  local f = DEFAULT_CHAT_FRAME or ChatFrame1
  if f then f:AddMessage("|cff33ff99Tactica:|r " .. tostring(msg or "")) end
end

local function EnsureDB()
  TacticaDB = TacticaDB or {}
  TacticaDB.Composition = TacticaDB.Composition or {}
  TacticaDB.Composition.current = TacticaDB.Composition.current or nil -- session-only, cleared when leaving raid
  TacticaDB.Composition.nameMap = TacticaDB.Composition.nameMap or {} -- persistent discordName -> { alias=true }
  TacticaDB.Composition.setupOverrides = TacticaDB.Composition.setupOverrides or {} -- session-only, cleared when leaving raid
  TacticaDB.Composition.splitConfig = TacticaDB.Composition.splitConfig or nil -- session-only, cleared with import data
end

local function GetSetupOverrides()
  EnsureDB()
  TacticaDB.Composition.setupOverrides = TacticaDB.Composition.setupOverrides or {}
  if TC then TC.setupOverrides = TacticaDB.Composition.setupOverrides end
  return TacticaDB.Composition.setupOverrides
end

local function ResetSetupOverrides()
  EnsureDB()
  TacticaDB.Composition.setupOverrides = {}
  if TC then TC.setupOverrides = TacticaDB.Composition.setupOverrides end
end

local function GetMaxGroupFromSlots(slots)
  local maxGroup = 0
  local i
  for i=1,table.getn(slots or {}) do
    local g = tonumber(slots[i].groupNumber) or 0
    if g > maxGroup then maxGroup = g end
  end
  if maxGroup < 1 then maxGroup = 1 end
  return maxGroup
end

local function NormalizeSplitConfig(splitConfig, maxGroup)
  maxGroup = tonumber(maxGroup) or 1
  if maxGroup < 1 then maxGroup = 1 end

  local cfg = splitConfig or {}
  local raids = cfg.raids or {}
  local out = { raids = {}, activeRaid = tonumber(cfg.activeRaid) or 1 }
  local i
  for i=1,4 do
    local row = raids[i]
    local fromG = row and tonumber(row.fromGroup) or nil
    local toG = row and tonumber(row.toGroup) or nil
    if fromG and toG then
      if fromG < 1 then fromG = 1 end
      if toG < 1 then toG = 1 end
      if fromG > maxGroup then fromG = maxGroup end
      if toG > maxGroup then toG = maxGroup end
      if fromG > toG then
        local t = fromG; fromG = toG; toG = t
      end
      out.raids[i] = { fromGroup = fromG, toGroup = toG }
    else
      out.raids[i] = { fromGroup = nil, toGroup = nil }
    end
  end

  if not (out.raids[1] and out.raids[1].fromGroup and out.raids[1].toGroup) then
    out.raids[1] = { fromGroup = 1, toGroup = math.min(maxGroup, 8) }
  end
  if out.activeRaid < 1 or out.activeRaid > 4 then out.activeRaid = 1 end
  if not out.raids[out.activeRaid] or not out.raids[out.activeRaid].fromGroup then out.activeRaid = 1 end
  return out
end

local function GetActiveRaidRange(data)
  EnsureDB()
  local maxGroup = GetMaxGroupFromSlots(data and data.slots or {})
  TacticaDB.Composition.splitConfig = NormalizeSplitConfig(TacticaDB.Composition.splitConfig, maxGroup)
  local cfg = TacticaDB.Composition.splitConfig
  local row = cfg.raids[cfg.activeRaid] or cfg.raids[1]
  return row.fromGroup, row.toGroup
end

local function GetActiveSlots(data)
  local out = {}
  if not data or not data.slots then return out end
  local fromG, toG = GetActiveRaidRange(data)
  local i
  for i=1,table.getn(data.slots) do
    local slot = data.slots[i]
    local g = tonumber(slot.groupNumber) or 0
    local sidx = tonumber(slot.slotNumber) or 0
    if g >= fromG and g <= toG and sidx >= 1 and sidx <= 5 then
      local mapped = g - fromG + 1
      if mapped >= 1 and mapped <= 8 then
        local copy = {
          name = slot.name,
          specName = slot.specName,
          className = slot.className,
          color = slot.color,
          groupNumber = mapped,
          originalGroupNumber = g,
          slotNumber = sidx,
          role = slot.role,
        }
        table.insert(out, copy)
      end
    end
  end
  return out
end

local function trim(s)
  local v = tostring(s or "")
  v = string.gsub(v, "^%s+", "")
  v = string.gsub(v, "%s+$", "")
  return v
end

local function lower(s) return string.lower(tostring(s or "")) end

local function countLines(text)
  local s = tostring(text or "")
  local _, n = string.gsub(s, "\n", "\n")
  return (n or 0) + 1
end

local function splitDiscordCandidates(name)
  local out, seen = {}, {}
  local raw = tostring(name or "")
  local function add(v)
    v = trim(v)
    if v ~= "" then
      local k = lower(v)
      if not seen[k] then seen[k] = true; table.insert(out, v) end
    end
  end
  add(raw)
  for token in string.gmatch(raw, "[^/]+") do add(token) end
  return out
end

local function getRaidMemberNamesLower()
  local set = {}
  if UnitInRaid and UnitInRaid("player") then
    local i
    for i=1,40 do
      local n = GetRaidRosterInfo(i)
      if n and n ~= "" then set[lower(n)] = n end
    end
  else
    local me = UnitName and UnitName("player")
    if me and me ~= "" then set[lower(me)] = me end
    local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    local i
    for i=1,pn do
      local u = "party"..i
      if UnitExists and UnitExists(u) then
        local n = UnitName(u)
        if n and n ~= "" then set[lower(n)] = n end
      end
    end
  end
  return set
end

local function getAssignedRoleLetter(name)
  if not TacticaDB then return "?" end
  if TacticaDB.Tanks and TacticaDB.Tanks[name] then return "T" end
  if TacticaDB.Healers and TacticaDB.Healers[name] then return "H" end
  if TacticaDB.DPS and TacticaDB.DPS[name] then return "D" end

  local ln = lower(name)
  local n, v
  if TacticaDB.Tanks then for n, v in pairs(TacticaDB.Tanks) do if v and lower(n) == ln then return "T" end end end
  if TacticaDB.Healers then for n, v in pairs(TacticaDB.Healers) do if v and lower(n) == ln then return "H" end end end
  if TacticaDB.DPS then for n, v in pairs(TacticaDB.DPS) do if v and lower(n) == ln then return "D" end end end
  return "?"
end

local function clearRoleForName(name)
  if not TacticaDB or not name or name == "" then return end
  TacticaDB.Tanks = TacticaDB.Tanks or {}
  TacticaDB.Healers = TacticaDB.Healers or {}
  TacticaDB.DPS = TacticaDB.DPS or {}
  TacticaDB.Tanks[name] = nil
  TacticaDB.Healers[name] = nil
  TacticaDB.DPS[name] = nil
end

local function setRoleForName(name, roleLetter)
  if not name or name == "" then return end
  clearRoleForName(name)
  if roleLetter == "T" then
    TacticaDB.Tanks[name] = true
  elseif roleLetter == "H" then
    TacticaDB.Healers[name] = true
  elseif roleLetter == "D" then
    TacticaDB.DPS[name] = true
  end
end

local function getClassColorForName(name)
  local ln = lower(name)
  local function unitColor(unit)
    if not (UnitExists and UnitExists(unit)) then return nil end
    local nm = UnitName and UnitName(unit)
    if not nm or lower(nm) ~= ln then return nil end
    local _, classFile = UnitClass and UnitClass(unit)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
      local c = RAID_CLASS_COLORS[classFile]
      return c.r or 1, c.g or 1, c.b or 1
    end
    return nil
  end

  local r,g,b
  if UnitInRaid and UnitInRaid("player") then
    local i
    for i=1,40 do
      r,g,b = unitColor("raid"..i)
      if r then return r,g,b end
    end
  end
  r,g,b = unitColor("player"); if r then return r,g,b end
  local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  local i
  for i=1,pn do
    r,g,b = unitColor("party"..i)
    if r then return r,g,b end
  end
  return nil
end

local function roleFromSlot(slot)
  local classN = lower(slot.className)
  local specN = lower(slot.specName)
  if classN == "tank" or string.find(specN, "protection", 1, true) or specN == "guardian" then return "Tank" end
  if string.find(specN, "restoration", 1, true) or string.find(specN, "holy", 1, true) or specN == "discipline" then return "Healer" end
  return "DPS"
end

local function hexToRGB(hex)
  hex = string.gsub(tostring(hex or ""), "#", "")
  if string.len(hex) ~= 6 then return 1,1,1 end
  local r = tonumber(string.sub(hex,1,2), 16) or 255
  local g = tonumber(string.sub(hex,3,4), 16) or 255
  local b = tonumber(string.sub(hex,5,6), 16) or 255
  return r/255, g/255, b/255
end

local function extractSlotObjects(text)
  local slotsStart = string.find(text, '"slots"%s*:%s*%[')
  if not slotsStart then return nil end
  local start = string.find(text, "%[", slotsStart)
  if not start then return nil end

  local depth = 0
  local i
  local finish
  for i=start, string.len(text) do
    local ch = string.sub(text, i, i)
    if ch == "[" then depth = depth + 1
    elseif ch == "]" then
      depth = depth - 1
      if depth == 0 then finish = i; break end
    end
  end
  if not finish then return nil end

  local arr = string.sub(text, start + 1, finish - 1)
  local objs = {}
  local d, s = 0, nil
  for i=1, string.len(arr) do
    local ch = string.sub(arr, i, i)
    if ch == "{" then
      if d == 0 then s = i end
      d = d + 1
    elseif ch == "}" then
      d = d - 1
      if d == 0 and s then
        table.insert(objs, string.sub(arr, s, i))
        s = nil
      end
    end
  end
  return objs
end

local function parseSlotObject(obj)
  local function getS(key)
    return string.match(obj, '"'..key..'"%s*:%s*"([^"]-)"')
  end
  local function getN(key)
    return tonumber(string.match(obj, '"'..key..'"%s*:%s*(%d+)') or "")
  end
  local slot = {
    name = getS("name"),
    specName = getS("specName") or "",
    className = getS("className") or "",
    color = getS("color") or "#FFFFFF",
    groupNumber = getN("groupNumber") or 0,
    slotNumber = getN("slotNumber") or 0,
  }
  if not slot.name or slot.name == "" then return nil end
  slot.role = roleFromSlot(slot)
  return slot
end

local function ParseCompositionJson(raw)
  local text = trim(raw)
  if text == "" then return nil, "empty" end
  if string.sub(text,1,1) ~= "{" then return nil, "not_json" end
  if not string.find(text, '"slots"%s*:%s*%[') then return nil, "no_slots" end

  local slotObjs = extractSlotObjects(text)
  if not slotObjs or table.getn(slotObjs) == 0 then return nil, "no_slot_entries" end

  local slots = {}
  local i
  for i=1,table.getn(slotObjs) do
    local p = parseSlotObject(slotObjs[i])
    if p then table.insert(slots, p) end
  end
  if table.getn(slots) == 0 then return nil, "bad_slot_payload" end

  return { raw = text, slots = slots, importedAt = time and time() or 0 }
end

local function ParseAndStoreCurrent(raw, splitConfig)
  local parsed = ParseCompositionJson(raw)
  if not parsed then
    cfmsg("Wrong format. Please paste the JSON export directly from Raid-Helper's Composition Tool.")
    return nil
  end
  TacticaDB.Composition.current = parsed
  local maxGroup = GetMaxGroupFromSlots(parsed.slots)
  TacticaDB.Composition.splitConfig = NormalizeSplitConfig(splitConfig, maxGroup)
  ResetSetupOverrides()
  return parsed
end

local function SetButtonEnabled(btn, enabled)
  if not btn then return end
  if enabled then btn:Enable() else btn:Disable() end
end

local function HasValidCompositionText(text)
  return ParseCompositionJson(text) ~= nil
end

local function StyleAccentButton(btn)
  if not btn then return end
  btn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  btn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
  btn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
end

local function SetAccentButtonEnabled(btn, enabled)
  if not btn then return end
  SetButtonEnabled(btn, enabled)

  local fs = btn:GetFontString()
  local nt = btn:GetNormalTexture()
  local pt = btn:GetPushedTexture()
  local ht = btn:GetHighlightTexture()

  if enabled then
    if fs and fs.SetTextColor then fs:SetTextColor(0.2, 1.0, 0.2) end
    if nt and nt.SetVertexColor then nt:SetVertexColor(0.2, 0.8, 0.2) end
    if pt and pt.SetVertexColor then pt:SetVertexColor(0.2, 0.8, 0.2) end
    if ht then
      if ht.SetBlendMode then ht:SetBlendMode("ADD") end
      if ht.SetVertexColor then ht:SetVertexColor(0.2, 1.0, 0.2) end
    end
  else
    if fs and fs.SetTextColor then fs:SetTextColor(0.5, 0.5, 0.5) end
    if nt and nt.SetVertexColor then nt:SetVertexColor(0.4, 0.4, 0.4) end
    if pt and pt.SetVertexColor then pt:SetVertexColor(0.4, 0.4, 0.4) end
    if ht and ht.SetVertexColor then ht:SetVertexColor(0.4, 0.4, 0.4) end
  end
end

local function OpenKeywordInvite()
  if TacticaInvite and TacticaInvite.Open then
    TacticaInvite.Open()
    return
  end
  if SlashCmdList and SlashCmdList["TTACTINV"] then
    SlashCmdList["TTACTINV"]("")
    return
  end
  cfmsg("Auto-Invite module is unavailable.")
end

local function CanManageRaidSubgroups()
  if IsRaidLeader and IsRaidLeader() then return true end
  if IsRaidOfficer and IsRaidOfficer() then return true end
  if IsRaidAssistant and IsRaidAssistant() then return true end
  if IsPartyLeader and IsPartyLeader() then return true end
  return false
end

local function BuildRaidRosterLookup()
  local byLower = {}
  local members = {}
  local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  local i
  for i=1,n do
    local name, _, subgroup = GetRaidRosterInfo(i)
    if name and name ~= "" then
      local entry = { index = i, name = name, subgroup = tonumber(subgroup) or 0 }
      byLower[lower(name)] = entry
      table.insert(members, entry)
    end
  end
  return byLower, members
end

function TC:BuildDesiredGroups()
  EnsureDB()
  local data = TacticaDB and TacticaDB.Composition and TacticaDB.Composition.current
  local desired = {}
  local seen = {}
  local g
  for g=1,8 do desired[g] = {} end
  if not data then return desired end

  local members = getRaidMemberNamesLower()
  local defaults = {}
  local i
  local activeSlots = GetActiveSlots(data)
  for i=1,table.getn(activeSlots) do
    local slot = activeSlots[i]
    local sg = tonumber(slot.groupNumber) or 0
    local sidx = tonumber(slot.slotNumber) or 0
    if sg >= 1 and sg <= 8 and sidx >= 1 and sidx <= 5 then
      local key = sg..":"..sidx
      local autoName = FindAutoMatch(slot.name)
      if autoName and members[lower(autoName)] then
        defaults[key] = autoName
      else
        defaults[key] = slot.name
      end
    end
  end

  self.setupOverrides = GetSetupOverrides()

  local function effectiveNameFor(key)
    local ov = self.setupOverrides[key]
    if ov and ov.kind == "empty" then return nil end
    if ov and ov.kind == "raid" then return ov.name end
    if ov and ov.kind == "slot" then return defaults[ov.sourceKey] end
    return defaults[key]
  end

  for g=1,8 do
    local sidx
    for sidx=1,5 do
      local key = g..":"..sidx
      local nm = effectiveNameFor(key)
      if nm and nm ~= "" then
        local raidName = members[lower(nm)]
        if raidName then
          local lk = lower(raidName)
          if not seen[lk] then
            table.insert(desired[g], raidName)
            seen[lk] = true
          end
        end
      end
    end
  end

  return desired
end

function TC:BuildDesiredRoleMap()
  EnsureDB()
  local data = TacticaDB and TacticaDB.Composition and TacticaDB.Composition.current
  local roleMap = {}
  if not data then return roleMap end

  self.setupOverrides = GetSetupOverrides()
  local members = getRaidMemberNamesLower()
  local defaults = {}

  local i
  local activeSlots = GetActiveSlots(data)
  for i=1,table.getn(activeSlots) do
    local slot = activeSlots[i]
    local g = tonumber(slot.groupNumber) or 0
    local sidx = tonumber(slot.slotNumber) or 0
    if g >= 1 and g <= 8 and sidx >= 1 and sidx <= 5 then
      local key = g..":"..sidx
      local autoName = FindAutoMatch(slot.name)
      local name = (autoName and members[lower(autoName)]) and autoName or slot.name
      local role = (slot.role == "Tank" and "T") or (slot.role == "Healer" and "H") or "D"
      defaults[key] = { name = name, role = role }
    end
  end

  local g, sidx
  for g=1,8 do
    for sidx=1,5 do
      local key = g..":"..sidx
      local ov = self.setupOverrides[key]
      local effective = defaults[key]

      if ov and ov.kind == "slot" and defaults[ov.sourceKey] then
        effective = defaults[ov.sourceKey]
      elseif ov and ov.kind == "empty" then
        effective = nil
      elseif ov and ov.kind == "raid" then
        effective = nil
      end

      if effective and effective.name and members[lower(effective.name)] then
        local raidName = members[lower(effective.name)]
        roleMap[raidName] = effective.role
      end
    end
  end

  return roleMap
end

function TC:SortRaidToSetupGroups()
  if not (UnitInRaid and UnitInRaid("player")) then
    cfmsg("You must be in a raid to sort groups.")
    return
  end
  if not CanManageRaidSubgroups() then
    cfmsg("Only raid leader/assist can sort groups.")
    return
  end

  local desired = self:BuildDesiredGroups()
  local plannedByLower = {}
  local plannedGroups = {}
  local g
  for g=1,8 do
    plannedGroups[g] = table.getn(desired[g]) > 0
    local i
    for i=1,table.getn(desired[g]) do
      plannedByLower[lower(desired[g][i])] = g
    end
  end

  local function moveNameToGroup(name, targetGroup)
    local roster = BuildRaidRosterLookup()
    local entry = roster[lower(name)]
    if not entry then return false end
    if entry.subgroup == targetGroup then return false end
    SetRaidSubgroup(entry.index, targetGroup)
    return true
  end

  local moved = 0
  for g=1,8 do
    local i
    for i=1,table.getn(desired[g]) do
      if moveNameToGroup(desired[g][i], g) then moved = moved + 1 end
    end
  end

  local function groupCounts(members)
    local counts = {}
    local i
    for i=1,8 do counts[i] = 0 end
    for i=1,table.getn(members) do
      local sg = tonumber(members[i].subgroup) or 0
      if sg >= 1 and sg <= 8 then counts[sg] = counts[sg] + 1 end
    end
    return counts
  end

  local function findBestTargetGroup(counts, preferUnplanned)
    local best = nil
    local i
    for i=1,8 do
      if counts[i] < 5 and ((not preferUnplanned) or (not plannedGroups[i])) then
        if not best or counts[i] < counts[best] then best = i end
      end
    end
    if best then return best end
    for i=1,8 do
      if counts[i] < 5 then
        if not best or counts[i] < counts[best] then best = i end
      end
    end
    return best
  end

  local function moveUnplannedOutOfPlannedGroups()
    local byLower, members = BuildRaidRosterLookup()
    local counts = groupCounts(members)
    local i
    for i=1,table.getn(members) do
      local m = members[i]
      local sg = tonumber(m.subgroup) or 0
      if sg >= 1 and sg <= 8 and plannedGroups[sg] and not plannedByLower[lower(m.name)] then
        local tgt = findBestTargetGroup(counts, true)
        if tgt and tgt ~= sg then
          local current = byLower[lower(m.name)]
          if current and current.index then
            SetRaidSubgroup(current.index, tgt)
            counts[sg] = math.max(0, counts[sg] - 1)
            counts[tgt] = counts[tgt] + 1
            moved = moved + 1
          end
        end
      end
    end
  end

  local function spillOverfilledGroups()
    local changed = true
    local safety = 0
    while changed and safety < 80 do
      changed = false
      safety = safety + 1
      local byLower, members = BuildRaidRosterLookup()
      local counts = groupCounts(members)

      local src = nil
      local i
      for i=1,8 do if counts[i] > 5 then src = i; break end end
      if not src then break end

      local tgt = findBestTargetGroup(counts, true)
      if not tgt or tgt == src then break end

      local candidate = nil
      for i=1,table.getn(members) do
        local m = members[i]
        if tonumber(m.subgroup) == src then
          if not plannedByLower[lower(m.name)] then
            candidate = m
            break
          end
          if not candidate then candidate = m end
        end
      end

      if candidate then
        local cur = byLower[lower(candidate.name)]
        if cur and cur.index then
          SetRaidSubgroup(cur.index, tgt)
          moved = moved + 1
          changed = true
        end
      else
        break
      end
    end
  end

  moveUnplannedOutOfPlannedGroups()
  spillOverfilledGroups()

  local roleMap = self:BuildDesiredRoleMap()
  local changedRoles = 0
  local nm, roleLetter
  for nm, roleLetter in pairs(roleMap) do
    if getAssignedRoleLetter(nm) ~= roleLetter then
      setRoleForName(nm, roleLetter)
      changedRoles = changedRoles + 1
    end
  end

  if changedRoles > 0 and TacticaRaidBuilder and TacticaRaidBuilder.NotifyRoleAssignmentChanged then
    TacticaRaidBuilder.NotifyRoleAssignmentChanged()
  end

  if self.setupFrame and self.setupFrame:IsShown() then self:RefreshSetupFrame() end
  cfmsg("Sort groups complete. Moves: "..tostring(moved)..", roles updated: "..tostring(changedRoles)..".")
end

local function BuildAliasList(discordName)
  EnsureDB()
  local bucket = TacticaDB.Composition.nameMap[discordName] or {}
  local list = {}
  local n
  for n in pairs(bucket) do table.insert(list, n) end
  table.sort(list)
  return list
end

local function AddAlias(discordName, alias)
  EnsureDB()
  alias = trim(alias)
  if alias == "" then return end
  TacticaDB.Composition.nameMap[discordName] = TacticaDB.Composition.nameMap[discordName] or {}
  TacticaDB.Composition.nameMap[discordName][alias] = true
end

local function ClearAliases(discordName)
  EnsureDB()
  TacticaDB.Composition.nameMap[discordName] = nil
end

FindAutoMatch = function(discordName)
  local raidNames = getRaidMemberNamesLower()
  local aliases = BuildAliasList(discordName)
  local i
  for i=1,table.getn(aliases) do
    local a = aliases[i]
    if raidNames[lower(a)] then return raidNames[lower(a)], "alias" end
  end

  local candidates = splitDiscordCandidates(discordName)
  for i=1,table.getn(candidates) do
    local c = candidates[i]
    if raidNames[lower(c)] then return raidNames[lower(c)], "candidate" end
  end

  return nil, nil
end

function TC:Open()
  EnsureDB()
  if TacticaDB.Composition.current then
    self:ShowCompositionFrame()
  else
    self:ShowImportFrame()
  end
end

function TC:OpenSetupStep()
  self:ShowSetupFrame()
end

function TC:UpdateImportSplitControls(rawText)
  if not self.importFrame then return end
  local text = rawText or (self.importFrame.input and self.importFrame.input:GetText()) or ""
  local parsed = ParseCompositionJson(text)
  local hasValid = parsed ~= nil
  SetAccentButtonEnabled(self.importFrame.btnSplitRaid, hasValid)

  if not hasValid then
    self.pendingSplitConfig = nil
    if self.importFrame.splitDropDown then
      self.importFrame.splitDropDown:Hide()
      UIDropDownMenu_SetText("", self.importFrame.splitDropDown)
    end
    return
  end

  local maxGroup = GetMaxGroupFromSlots(parsed.slots)
  local cfg = NormalizeSplitConfig(self.pendingSplitConfig or TacticaDB.Composition.splitConfig, maxGroup)
  self.pendingSplitConfig = cfg

  local labels = {}
  local count = 0
  local i
  for i=1,4 do
    local r = cfg.raids[i]
    if r and r.fromGroup and r.toGroup then
      count = count + 1
      labels[i] = string.format("Raid %d (group %d-%d)", i, r.fromGroup, r.toGroup)
    end
  end

  if count > 1 and self.importFrame.splitDropDown then
    UIDropDownMenu_Initialize(self.importFrame.splitDropDown, function()
      local idx
      for idx=1,4 do
        if labels[idx] then
          local selectedIdx = idx
          local info = UIDropDownMenu_CreateInfo()
          info.text = labels[idx]
          info.notCheckable = 1
          info.func = function()
            self.pendingSplitConfig.activeRaid = selectedIdx
            UIDropDownMenu_SetText(labels[selectedIdx], self.importFrame.splitDropDown)
          end
          UIDropDownMenu_AddButton(info)
        end
      end
    end)
    local activeLabel = labels[cfg.activeRaid] or labels[1]
    UIDropDownMenu_SetText(activeLabel or "", self.importFrame.splitDropDown)
    self.importFrame.splitDropDown:Show()
  elseif self.importFrame.splitDropDown then
    self.importFrame.splitDropDown:Hide()
  end
end

function TC:ShowSplitRaidFrame()
  if not self.importFrame then return end
  local parsed = ParseCompositionJson(self.importFrame.input:GetText() or "")
  if not parsed then return end
  if not self.splitRaidFrame then self:CreateSplitRaidFrame() end

  local maxGroup = GetMaxGroupFromSlots(parsed.slots)
  local cfg = NormalizeSplitConfig(self.pendingSplitConfig or TacticaDB.Composition.splitConfig, maxGroup)
  self.splitRaidFrame.maxGroup = maxGroup

  local i
  for i=1,4 do
    local row = cfg.raids[i]
    self.splitRaidFrame.rows[i].from:SetText((row and row.fromGroup) and tostring(row.fromGroup) or "")
    self.splitRaidFrame.rows[i].to:SetText((row and row.toGroup) and tostring(row.toGroup) or "")
  end

  self.splitRaidFrame:Show()
  self.splitRaidFrame:Raise()
end

function TC:CreateSplitRaidFrame()
  local f = CreateFrame("Frame", "TacticaCompositionSplitRaidFrame", UIParent)
  f:SetWidth(340); f:SetHeight(240)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24, insets={left=8,right=8,top=8,bottom=8} })
  f:SetMovable(true); f:EnableMouse(true); f:SetToplevel(true); f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
  title:SetText("Split Raid")
  title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local colFrom = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  colFrom:SetPoint("TOPLEFT", f, "TOPLEFT", 116, -48)
  colFrom:SetText("Select Groups")

  f.rows = {}
  local i
  for i=1,4 do
    local y = -70 - ((i-1) * 34)
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
    lbl:SetText("Raid "..i..":")

    local from = CreateFrame("EditBox", nil, f)
    from:SetAutoFocus(false)
    from:SetFontObject(ChatFontNormal)
    from:SetWidth(56); from:SetHeight(22)
    from:SetPoint("LEFT", lbl, "RIGHT", 18, 0)
    from:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    from:SetBackdropColor(0,0,0,0.85)
    from:SetTextInsets(6, 6, 0, 0)

    local toTxt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toTxt:SetPoint("LEFT", from, "RIGHT", 10, 0)
    toTxt:SetText("to")

    local to = CreateFrame("EditBox", nil, f)
    to:SetAutoFocus(false)
    to:SetFontObject(ChatFontNormal)
    to:SetWidth(56); to:SetHeight(22)
    to:SetPoint("LEFT", toTxt, "RIGHT", 10, 0)
    to:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    to:SetBackdropColor(0,0,0,0.85)
    to:SetTextInsets(6, 6, 0, 0)

    f.rows[i] = { from = from, to = to }
  end

  local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  cancel:SetWidth(90); cancel:SetHeight(24)
  cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 64, 16)
  cancel:SetText("Cancel")
  cancel:SetScript("OnClick", function() f:Hide() end)

  local submit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  submit:SetWidth(90); submit:SetHeight(24)
  submit:SetPoint("LEFT", cancel, "RIGHT", 24, 0)
  submit:SetText("Submit")
  submit:SetScript("OnClick", function()
    local maxGroup = f.maxGroup or 1
    local cfg = { raids = {}, activeRaid = 1 }
    local count = 0
    local i
    for i=1,4 do
      local fromG = tonumber(trim(f.rows[i].from:GetText() or ""))
      local toG = tonumber(trim(f.rows[i].to:GetText() or ""))
      if fromG and toG then
        if fromG < 1 then fromG = 1 end
        if toG < 1 then toG = 1 end
        if fromG > maxGroup then fromG = maxGroup end
        if toG > maxGroup then toG = maxGroup end
        if fromG > toG then local t = fromG; fromG = toG; toG = t end
        cfg.raids[i] = { fromGroup = fromG, toGroup = toG }
        count = count + 1
      else
        cfg.raids[i] = { fromGroup = nil, toGroup = nil }
      end
    end
    cfg = NormalizeSplitConfig(cfg, maxGroup)
    self.pendingSplitConfig = cfg
    self:UpdateImportSplitControls(self.importFrame and self.importFrame.input and self.importFrame.input:GetText() or "")
    f:Hide()
  end)

  self.splitRaidFrame = f
end

function TC:ShowImportFrame()
  EnsureDB()
  if not self.importFrame then self:CreateImportFrame() end
  local existing = TacticaDB.Composition.current and TacticaDB.Composition.current.raw or ""
  self.pendingSplitConfig = TacticaDB.Composition.splitConfig
  self.importFrame.input:SetText(existing)
  self.importFrame.input:ClearFocus()
  if self.importFrame.inputScroll and self.importFrame.inputScroll.SetVerticalScroll then
    self.importFrame.inputScroll:SetVerticalScroll(0)
  end
  local hasInput = trim(existing) ~= ""
  local hasValidInput = HasValidCompositionText(existing)
  local canSort = hasValidInput and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
  SetButtonEnabled(self.importFrame.submit, hasInput)
  if self.importFrame.btnSetup then SetButtonEnabled(self.importFrame.btnSetup, hasInput) end
  if self.importFrame.btnKeywordInvite then SetAccentButtonEnabled(self.importFrame.btnKeywordInvite, hasValidInput) end
  if self.importFrame.btnSortRaid then SetAccentButtonEnabled(self.importFrame.btnSortRaid, canSort) end
  self:UpdateImportSplitControls(existing)
  if self.setupFrame then self.setupFrame:Hide() end
  self.importFrame:Show()
  self.importFrame:Raise()
end

function TC:CreateImportFrame()
  local f = CreateFrame("Frame", "TacticaCompositionImportFrame", UIParent)
  f:SetWidth(760); f:SetHeight(520)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24, insets={left=8,right=8,top=8,bottom=8} })
  f:SetMovable(true); f:EnableMouse(true); f:SetToplevel(true); f:SetFrameStrata("DIALOG")
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
  title:SetText("TACTICA COMPOSITION TOOL - 1/3. Import")
  title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
  sub:SetWidth(700)
  sub:SetJustifyH("LEFT")
  sub:SetText("Import JSON export from Raid-Helper's Composition Tool, after you have arranged all groups.")
  sub:SetTextColor(1,1,1)

  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -74)
  sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -74)
  sep:SetTexture(1, 1, 1)
  if sep.SetVertexColor then sep:SetVertexColor(1, 1, 1, 0.25) end

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local bg = CreateFrame("Frame", nil, f)
  bg:SetWidth(700); bg:SetHeight(360)
  bg:SetPoint("TOP", f, "TOP", 0, -102)
  bg:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
  bg:SetBackdropColor(0,0,0,0.85)

  local scroll = CreateFrame("ScrollFrame", "TacticaCompositionImportScrollFrame", bg, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", bg, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 8)

  local edit = CreateFrame("EditBox", "TacticaCompositionImportEdit", scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(660)
  edit:SetHeight(320)
  edit:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  edit:SetAutoFocus(false)
  edit:EnableMouse(true)
  scroll:SetScrollChild(edit)

  local btnImport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnImport:SetWidth(130); btnImport:SetHeight(24)
  btnImport:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
  btnImport:SetText("<- 1/3. Import")
  btnImport:Disable()

  local submit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  submit:SetWidth(130); submit:SetHeight(24)
  submit:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
  submit:SetText("2/3. Matching")
  submit:Disable()

  local btnKeywordInvite = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnKeywordInvite:SetWidth(130); btnKeywordInvite:SetHeight(24)
  btnKeywordInvite:SetPoint("RIGHT", submit, "LEFT", -6, 0)
  btnKeywordInvite:SetText("Keyword invite")
  StyleAccentButton(btnKeywordInvite)
  SetAccentButtonEnabled(btnKeywordInvite, false)

  local btnSortRaid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSortRaid:SetWidth(130); btnSortRaid:SetHeight(24)
  btnSortRaid:SetPoint("LEFT", submit, "RIGHT", 6, 0)
  btnSortRaid:SetText("Sort groups")
  StyleAccentButton(btnSortRaid)
  SetAccentButtonEnabled(btnSortRaid, false)

  local btnSetup = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSetup:SetWidth(130); btnSetup:SetHeight(24)
  btnSetup:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  btnSetup:SetText("3/3. Setup ->")

  local btnSplitRaid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSplitRaid:SetWidth(130); btnSplitRaid:SetHeight(24)
  btnSplitRaid:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", 0, 0)
  btnSplitRaid:SetText("Split raid")
  StyleAccentButton(btnSplitRaid)
  SetAccentButtonEnabled(btnSplitRaid, false)

  local splitDropDown = CreateFrame("Frame", "TacticaCompositionImportSplitDropDown", f, "UIDropDownMenuTemplate")
  splitDropDown:SetPoint("LEFT", btnSplitRaid, "RIGHT", -10, -3)
  UIDropDownMenu_SetWidth(230, splitDropDown)
  splitDropDown:Hide()

  bg:EnableMouse(true)
  scroll:EnableMouse(true)
  scroll:EnableMouseWheel(true)

  local function FocusImportEdit()
    edit:SetFocus()
  end

  bg:SetScript("OnMouseDown", FocusImportEdit)
  scroll:SetScript("OnMouseDown", FocusImportEdit)
  edit:SetScript("OnMouseDown", FocusImportEdit)

  scroll:SetScript("OnVerticalScroll", function()
    if ScrollingEdit_OnVerticalScroll then ScrollingEdit_OnVerticalScroll(20) end
  end)
  edit:SetScript("OnCursorChanged", function()
    if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged() end
  end)

  btnSetup:SetScript("OnClick", function()
    if not ParseAndStoreCurrent(edit:GetText(), self.pendingSplitConfig) then return end
    f:Hide()
    TC:OpenSetupStep()
  end)
  btnKeywordInvite:SetScript("OnClick", function()
    if not HasValidCompositionText(edit:GetText()) then return end
    OpenKeywordInvite()
  end)
  btnSortRaid:SetScript("OnClick", function()
    if not HasValidCompositionText(edit:GetText()) then return end
    if not ParseAndStoreCurrent(edit:GetText(), self.pendingSplitConfig) then return end
    TC:SortRaidToSetupGroups()
  end)
  btnSplitRaid:SetScript("OnClick", function()
    if not HasValidCompositionText(edit:GetText()) then return end
    TC:ShowSplitRaidFrame()
  end)
  edit:SetScript("OnTextChanged", function()
    local lines = countLines(edit:GetText())
    local minH = 320
    local targetH = lines * 14 + 16
    if targetH < minH then targetH = minH end
    edit:SetHeight(targetH)
    if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged() end
    local current = edit:GetText()
    local hasInput = trim(current) ~= ""
    local hasValidInput = HasValidCompositionText(current)
    local canSort = hasValidInput and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
    SetButtonEnabled(submit, hasInput)
    SetButtonEnabled(btnSetup, hasInput)
    SetAccentButtonEnabled(btnKeywordInvite, hasValidInput)
    SetAccentButtonEnabled(btnSortRaid, canSort)
    TC:UpdateImportSplitControls(current)
  end)
  submit:SetScript("OnClick", function()
    if not ParseAndStoreCurrent(edit:GetText(), self.pendingSplitConfig) then return end
    f:Hide()
    TC:ShowCompositionFrame()
  end)

  f.input = edit
  f.inputScroll = scroll
  f.btnImport = btnImport
  f.btnSetup = btnSetup
  f.submit = submit
  f.btnKeywordInvite = btnKeywordInvite
  f.btnSortRaid = btnSortRaid
  f.btnSplitRaid = btnSplitRaid
  f.splitDropDown = splitDropDown
  self.importFrame = f
end

function TC:RefreshCompositionRows()
  local f = self.viewFrame
  if not f then return end

  local data = TacticaDB and TacticaDB.Composition and TacticaDB.Composition.current
  if not data then f:Hide(); return end

  local rows = f.rows
  local i
  for i=1, table.getn(rows) do rows[i]:Hide() end
  if f.unmatchedTitle then f.unmatchedTitle:Hide() end
  for i=1, table.getn(f.unmatchedRows or {}) do f.unmatchedRows[i]:Hide() end

  local matchedLower = {}

  local activeSlots = GetActiveSlots(data)
  for i=1, table.getn(activeSlots) do
    local slot = activeSlots[i]
    local row = rows[i]
    if not row then
      row = CreateFrame("Frame", nil, f.content)
      row:SetWidth(718); row:SetHeight(24)
      if i == 1 then row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0) else row:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, -4) end

      row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.label:SetWidth(320); row.label:SetJustifyH("LEFT")

      row.input = CreateFrame("EditBox", nil, row)
      row.input:SetAutoFocus(false)
      row.input:SetFontObject(ChatFontNormal)
      row.input:SetWidth(145); row.input:SetHeight(20)
      row.input:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
      row.input:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
      })
      row.input:SetBackdropColor(0, 0, 0, 0.75)
      row.input:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
      row.input:SetTextInsets(6, 6, 0, 0)

      row.add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      row.add:SetWidth(35); row.add:SetHeight(20)
      row.add:SetPoint("LEFT", row.input, "RIGHT", 4, 0)
      row.add:SetText("Add")

      row.dd = CreateFrame("Frame", "TacticaCompositionRowDropDown"..i, row, "UIDropDownMenuTemplate")
      row.dd:SetPoint("LEFT", row.add, "RIGHT", -4, -3)
      UIDropDownMenu_SetWidth(150, row.dd)

      row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      row.status:SetPoint("LEFT", row.dd, "RIGHT", 0, 0)
      row.status:SetJustifyH("LEFT")

      rows[i] = row
    end

    local r,g,b = hexToRGB(slot.color)
    local rr, gg, bb = math.floor(r*255), math.floor(g*255), math.floor(b*255)
    row.label:SetText(string.format("|cff%02x%02x%02x%s|r - %s - |cffffffffGroup %d|r", rr, gg, bb, slot.name, slot.role, tonumber(slot.groupNumber) or 0))

    local slotName = slot.name
    local rowRef = row
    local aliases = BuildAliasList(slotName)

    UIDropDownMenu_Initialize(rowRef.dd, function()
      local info = UIDropDownMenu_CreateInfo()
      info.text = "Select name"; info.notCheckable = 1; info.isTitle = 1
      UIDropDownMenu_AddButton(info)

      local j
      for j=1,table.getn(aliases) do
        local alias = aliases[j]
        local it = UIDropDownMenu_CreateInfo()
        it.text = alias
        it.notCheckable = 1
        it.func = function()
          UIDropDownMenu_SetText(alias, rowRef.dd)
        end
        UIDropDownMenu_AddButton(it)
      end

      local clr = UIDropDownMenu_CreateInfo()
      clr.text = "- DELELTE/CLEAR -"
      clr.notCheckable = 1
      clr.func = function()
        ClearAliases(slotName)
        UIDropDownMenu_SetText("Select", rowRef.dd)
        TC:RefreshCompositionRows()
      end
      UIDropDownMenu_AddButton(clr)
    end)

    UIDropDownMenu_SetText((table.getn(aliases) > 0 and aliases[1]) or "Select", rowRef.dd)

    local autoName = FindAutoMatch(slotName)
    if autoName then
      local isAlias = false
      local j
      for j=1,table.getn(aliases) do if lower(aliases[j]) == lower(autoName) then isAlias = true end end
      if isAlias then
        UIDropDownMenu_SetText(autoName, rowRef.dd)
        rowRef.input:SetText("")
      else
        rowRef.input:SetText(autoName)
      end
    else
      rowRef.input:SetText("")
    end

    local ddText = UIDropDownMenu_GetText and UIDropDownMenu_GetText(rowRef.dd) or ""
    local hasDropdownSelection = ddText and ddText ~= "" and ddText ~= "Select" and ddText ~= "Select name" and ddText ~= "- DELELTE/CLEAR -"
    local membersNow = getRaidMemberNamesLower()
    local dropdownJoined = hasDropdownSelection and membersNow[lower(ddText)] and true or false

    if dropdownJoined then
      matchedLower[lower(ddText)] = ddText
      rowRef.status:SetText("|cff00ff00[R]|r")
    elseif autoName and autoName ~= "" and membersNow[lower(autoName)] then
      rowRef.status:SetText("|cffffa500[o]|r")
    else
      rowRef.status:SetText("|cffff5555[X]|r")
    end

    rowRef.input:SetScript("OnEditFocusGained", function()
      rowRef.input:SetBackdropBorderColor(1, 0.82, 0, 1)
    end)
    rowRef.input:SetScript("OnEditFocusLost", function()
      rowRef.input:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    end)

    SetButtonEnabled(rowRef.add, trim(rowRef.input:GetText()) ~= "")
    rowRef.input:SetScript("OnTextChanged", function()
      SetButtonEnabled(rowRef.add, trim(rowRef.input:GetText()) ~= "")
    end)
    rowRef.add:SetScript("OnClick", function()
      local val = trim(rowRef.input:GetText())
      if val == "" then return end
      AddAlias(slotName, val)
      rowRef.input:SetText("")
      TC:RefreshCompositionRows()
    end)

    rowRef:Show()
  end

  -- Unmatched/Not Listed section (joined but not currently matched)
  local members = getRaidMemberNamesLower()
  local unmatched = {}
  local nm
  for k, v in pairs(members) do
    if not matchedLower[k] then table.insert(unmatched, v) end
  end
  table.sort(unmatched)

  local last = rows[table.getn(activeSlots)]
  local anchor = last

  if not f.unmatchedTitle then
    f.unmatchedTitle = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.unmatchedTitle:SetJustifyH("LEFT")
  end

  if anchor then
    f.unmatchedTitle:ClearAllPoints()
    f.unmatchedTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
  else
    f.unmatchedTitle:ClearAllPoints()
    f.unmatchedTitle:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
  end
  f.unmatchedTitle:SetText("UNMATCHED/NOT LISTED")
  f.unmatchedTitle:Show()

  f.unmatchedRows = f.unmatchedRows or {}
  local prev = f.unmatchedTitle
  for i=1, table.getn(unmatched) do
    local fs = f.unmatchedRows[i]
    if not fs then
      fs = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetJustifyH("LEFT")
      f.unmatchedRows[i] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
    fs:SetText("- " .. unmatched[i])
    fs:Show()
    prev = fs
  end

  local rowsBottom = table.getn(activeSlots) * 28 + 8
  local unmatchedExtra = 24 + (table.getn(unmatched) * 16)
  f.content:SetHeight(math.max(1, rowsBottom + unmatchedExtra))
end

function TC:ShowCompositionFrame()
  EnsureDB()
  if not TacticaDB.Composition.current then self:ShowImportFrame(); return end
  if not self.viewFrame then self:CreateCompositionFrame() end
  self:RefreshCompositionRows()
  local hasValidCurrent = HasValidCompositionText(TacticaDB.Composition.current and TacticaDB.Composition.current.raw or "")
  local canSortCurrent = hasValidCurrent and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
  if self.viewFrame.btnKeywordInvite then SetAccentButtonEnabled(self.viewFrame.btnKeywordInvite, hasValidCurrent) end
  if self.viewFrame.btnSortRaid then SetAccentButtonEnabled(self.viewFrame.btnSortRaid, canSortCurrent) end
  if self.setupFrame then self.setupFrame:Hide() end
  self.viewFrame:Show()
  self.viewFrame:Raise()
end

function TC:CreateCompositionFrame()
  local f = CreateFrame("Frame", "TacticaCompositionViewFrame", UIParent)
  f:SetWidth(790); f:SetHeight(560)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24, insets={left=8,right=8,top=8,bottom=8} })
  f:SetMovable(true); f:EnableMouse(true); f:SetToplevel(true); f:SetFrameStrata("DIALOG")
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
  title:SetText("TACTICA COMPOSITION TOOL - 2/3. Matching")
  title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
  sub:SetWidth(740)
  sub:SetJustifyH("LEFT")
  sub:SetText("When a joining player's name fully or partly matches a Discord name, it is suggested in the field. Press Add to confirm a mapping, and add multiple names for one Discord entry when needed.")
  sub:SetTextColor(1,1,1)

  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -82)
  sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -82)
  sep:SetTexture(1, 1, 1)
  if sep.SetVertexColor then sep:SetVertexColor(1, 1, 1, 0.25) end

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local scroll = CreateFrame("ScrollFrame", "TacticaCompositionViewScrollFrame", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -94)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 48)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(728); content:SetHeight(1)
  scroll:SetScrollChild(content)

  local btnImport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnImport:SetWidth(130); btnImport:SetHeight(24)
  btnImport:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
  btnImport:SetText("<- 1/3. Import")
  btnImport:SetScript("OnClick", function()
    f:Hide()
    TC:ShowImportFrame()
  end)

  local btnMatching = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnMatching:SetWidth(130); btnMatching:SetHeight(24)
  btnMatching:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
  btnMatching:SetText("2/3. Matching")
  btnMatching:Disable()

  local btnKeywordInvite = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnKeywordInvite:SetWidth(130); btnKeywordInvite:SetHeight(24)
  btnKeywordInvite:SetPoint("RIGHT", btnMatching, "LEFT", -6, 0)
  btnKeywordInvite:SetText("Keyword invite")
  StyleAccentButton(btnKeywordInvite)
  local hasValidCurrent = HasValidCompositionText(TacticaDB.Composition.current and TacticaDB.Composition.current.raw or "")
  local canSortCurrent = hasValidCurrent and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
  SetAccentButtonEnabled(btnKeywordInvite, hasValidCurrent)
  btnKeywordInvite:SetScript("OnClick", function() OpenKeywordInvite() end)

  local btnSortRaid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSortRaid:SetWidth(130); btnSortRaid:SetHeight(24)
  btnSortRaid:SetPoint("LEFT", btnMatching, "RIGHT", 6, 0)
  btnSortRaid:SetText("Sort groups")
  StyleAccentButton(btnSortRaid)
  SetAccentButtonEnabled(btnSortRaid, canSortCurrent)
  btnSortRaid:SetScript("OnClick", function()
    TC:SortRaidToSetupGroups()
  end)

  local btnSetup = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSetup:SetWidth(130); btnSetup:SetHeight(24)
  btnSetup:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  btnSetup:SetText("3/3. Setup ->")
  btnSetup:SetScript("OnClick", function() TC:OpenSetupStep() end)

  f.rows = {}
  f.unmatchedTitle = nil
  f.unmatchedRows = {}
  f.content = content
  f.btnImport = btnImport
  f.btnMatching = btnMatching
  f.btnSetup = btnSetup
  f.btnKeywordInvite = btnKeywordInvite
  f.btnSortRaid = btnSortRaid
  self.viewFrame = f
end

function TC:ShowSetupFrame()
  EnsureDB()
  if not self.setupFrame then self:CreateSetupFrame() end
  if self.importFrame then self.importFrame:Hide() end
  if self.viewFrame then self.viewFrame:Hide() end
  self:RefreshSetupFrame()
  local hasValidCurrent = HasValidCompositionText(TacticaDB.Composition.current and TacticaDB.Composition.current.raw or "")
  local canSortCurrent = hasValidCurrent and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
  if self.setupFrame.btnKeywordInvite then SetAccentButtonEnabled(self.setupFrame.btnKeywordInvite, hasValidCurrent) end
  if self.setupFrame.btnSortRaid then SetAccentButtonEnabled(self.setupFrame.btnSortRaid, canSortCurrent) end
  self.setupFrame:Show()
  self.setupFrame:Raise()
end

function TC:RefreshSetupFrame()
  local f = self.setupFrame
  if not f then return end
  local data = TacticaDB and TacticaDB.Composition and TacticaDB.Composition.current
  if not data then return end

  self.setupOverrides = GetSetupOverrides()
  local members = getRaidMemberNamesLower()
  local defaults = {}
  local matchedLower = {}

  local orderedKeys = {}
  local gg, ss
  for gg=1,8 do
    for ss=1,5 do
      table.insert(orderedKeys, gg..":"..ss)
    end
  end

  local function normalizeOverrides()
    local usedRaid = {}
    local usedSlotSource = {}
    local changed = false

    local _, key
    for _, key in ipairs(orderedKeys) do
      local ov = self.setupOverrides[key]
      if ov then
        if ov.kind == "slot" then
          if ov.sourceKey == key or not defaults[ov.sourceKey] or usedSlotSource[ov.sourceKey] then
            self.setupOverrides[key] = nil
            changed = true
          else
            usedSlotSource[ov.sourceKey] = true
          end
        elseif ov.kind == "raid" then
          local lk = lower(ov.name or "")
          if lk == "" or not members[lk] or usedRaid[lk] then
            self.setupOverrides[key] = nil
            changed = true
          else
            usedRaid[lk] = true
          end
        elseif ov.kind ~= "empty" then
          self.setupOverrides[key] = nil
          changed = true
        end
      end
    end

    if changed then
      TacticaDB.Composition.setupOverrides = self.setupOverrides
    end
  end

  local function setOverrideForKey(targetKey, ov)
    local k
    if ov and ov.kind == "slot" and ov.sourceKey then
      for k,_ in pairs(self.setupOverrides) do
        if k ~= targetKey then
          local other = self.setupOverrides[k]
          if other and other.kind == "slot" and other.sourceKey == ov.sourceKey then
            self.setupOverrides[k] = nil
          end
        end
      end
    elseif ov and ov.kind == "raid" and ov.name then
      local lk = lower(ov.name)
      for k,_ in pairs(self.setupOverrides) do
        if k ~= targetKey then
          local other = self.setupOverrides[k]
          if other and other.kind == "raid" and lower(other.name or "") == lk then
            self.setupOverrides[k] = nil
          end
        end
      end
    end

    if ov then
      self.setupOverrides[targetKey] = ov
    else
      self.setupOverrides[targetKey] = nil
    end
    TacticaDB.Composition.setupOverrides = self.setupOverrides
  end

  local activeSlots = GetActiveSlots(data)
  local i
  for i=1,table.getn(activeSlots) do
    local slot = activeSlots[i]
    local g = tonumber(slot.groupNumber) or 0
    local sidx = tonumber(slot.slotNumber) or 0
    if g >= 1 and g <= 8 and sidx >= 1 and sidx <= 5 then
      local key = g..":"..sidx
      local aliases = BuildAliasList(slot.name)
      local autoName = FindAutoMatch(slot.name)
      local isAlias = false
      local j
      for j=1,table.getn(aliases) do if autoName and lower(aliases[j]) == lower(autoName) then isAlias = true end end

      local status = "X"
      local displayName = slot.name
      if autoName and isAlias and members[lower(autoName)] then
        status = "R"
        displayName = autoName
        matchedLower[lower(autoName)] = autoName
      elseif autoName and members[lower(autoName)] then
        status = "O"
      end

      local roleLetter = (slot.role == "Tank" and "T") or (slot.role == "Healer" and "H") or "D"
      defaults[key] = {
        key = key,
        slot = slot,
        role = roleLetter,
        status = status,
        name = displayName,
      }
    end
  end

  normalizeOverrides()

  local raidUnlisted = {}
  for k, nm in pairs(members) do
    if not matchedLower[k] then table.insert(raidUnlisted, nm) end
  end
  table.sort(raidUnlisted)

  local function statusColor(st)
    if st == "R" then return "|cff00ff00" end
    if st == "O" then return "|cffffa500" end
    return "|cffff5555"
  end

  local function colorizedName(slot, name)
    local r,g,b = hexToRGB(slot.color)
    local rr,gg,bb = math.floor(r*255), math.floor(g*255), math.floor(b*255)
    return string.format("|cff%02x%02x%02x%s|r", rr,gg,bb, tostring(name or ""))
  end

  local function defaultText(d)
    return "("..d.role..") "..colorizedName(d.slot, d.name).." - "..statusColor(d.status)..d.status.."|r"
  end

  -- pool contains raid-unlisted + displaced defaults from overridden slots
  local pool = {}
  for i=1,table.getn(raidUnlisted) do
    local nm = raidUnlisted[i]
    local id = "raid:"..lower(nm)
    pool[id] = { id=id, kind="raid", name=nm, text="(?) "..nm.." - |cff00ff00R|r" }
  end

  for key, ov in pairs(self.setupOverrides) do
    if ov and defaults[key] then
      local d = defaults[key]
      local id = "slot:"..key
      pool[id] = { id=id, kind="slot", sourceKey=key, role=d.role, name=d.name, slot=d.slot, status=d.status, text=defaultText(d) }
    end
  end

  local function effectiveFor(key)
    local d = defaults[key]
    local ov = self.setupOverrides[key]

    local function raidText(name)
      local st = members[lower(name or "")] and "R" or "X"
      local role = getAssignedRoleLetter(name or "")
      local cr, cg, cb = getClassColorForName(name or "")
      if not cr then cr, cg, cb = 0.70, 0.70, 0.70 end
      local txt = string.format("(%s) |cff%02x%02x%02x%s|r - %s%s|r", role, math.floor(cr*255), math.floor(cg*255), math.floor(cb*255), tostring(name or ""), statusColor(st), st)
      return txt, st
    end

    local function emptyText()
      return "(?) |cffb0b0b0- Empty -|r - |cffff5555X|r", "X"
    end

    if not d then
      if not ov then return emptyText() end
      if ov.kind == "raid" then return raidText(ov.name or "") end
      if ov.kind == "empty" then return emptyText() end
      if ov.kind == "slot" and defaults[ov.sourceKey] then
        local src = defaults[ov.sourceKey]
        local txt = "("..src.role..") "..colorizedName(src.slot, src.name).." - "..statusColor(src.status)..src.status.."|r"
        return txt, src.status
      end
      return emptyText()
    end

    if not ov then
      return defaultText(d), d.status
    end

    if ov.kind == "raid" then
      return raidText(ov.name or "")
    elseif ov.kind == "empty" then
      return emptyText()
    elseif ov.kind == "slot" and defaults[ov.sourceKey] then
      local src = defaults[ov.sourceKey]
      local txt = "("..src.role..") "..colorizedName(src.slot, src.name).." - "..statusColor(src.status)..src.status.."|r"
      return txt, src.status
    end

    return defaultText(d), d.status
  end

  local g,sidx
  for g=1,8 do
    for sidx=1,5 do
      local key = g..":"..sidx
      local slotUI = f.groupSlots[g] and f.groupSlots[g][sidx]
      if slotUI then
        local txt = effectiveFor(key)
        slotUI.label:SetText(txt)

        UIDropDownMenu_Initialize(slotUI.dd, function()
          local usedRaidByOthers = {}
          local usedSlotByOthers = {}
          local k2, ov2
          for k2, ov2 in pairs(self.setupOverrides) do
            if k2 ~= key and ov2 then
              if ov2.kind == "raid" then usedRaidByOthers[lower(ov2.name or "")] = true end
              if ov2.kind == "slot" then usedSlotByOthers[ov2.sourceKey or ""] = true end
            end
          end

          local info = UIDropDownMenu_CreateInfo()
          info.text = "Default"
          info.notCheckable = 1
          info.func = function()
            setOverrideForKey(key, nil)
            UIDropDownMenu_SetText("Default", slotUI.dd)
            self:RefreshSetupFrame()
          end
          UIDropDownMenu_AddButton(info)

          local ei = UIDropDownMenu_CreateInfo()
          ei.text = "- Empty -"
          ei.notCheckable = 1
          ei.func = function()
            setOverrideForKey(key, { kind="empty" })
            UIDropDownMenu_SetText("Empty", slotUI.dd)
            self:RefreshSetupFrame()
          end
          UIDropDownMenu_AddButton(ei)

          for _, nm in ipairs(raidUnlisted) do
            local lk = lower(nm)
            if not usedRaidByOthers[lk] then
              local picked = nm
              local ri = UIDropDownMenu_CreateInfo()
              ri.text = "Use: "..picked
              ri.notCheckable = 1
              ri.func = function()
                setOverrideForKey(key, { kind="raid", name=picked })
                UIDropDownMenu_SetText("Other", slotUI.dd)
                self:RefreshSetupFrame()
              end
              UIDropDownMenu_AddButton(ri)
            end
          end

          local k, entry
          for k, entry in pairs(pool) do
            if entry and entry.kind == "slot" and entry.sourceKey and entry.sourceKey ~= key and (not usedSlotByOthers[entry.sourceKey]) then
              local sourceKey = entry.sourceKey
              local sourceText = entry.text
              local si = UIDropDownMenu_CreateInfo()
              si.text = "Use: "..sourceText
              si.notCheckable = 1
              si.func = function()
                setOverrideForKey(key, { kind="slot", sourceKey=sourceKey })
                UIDropDownMenu_SetText("from "..sourceKey, slotUI.dd)
                self:RefreshSetupFrame()
              end
              UIDropDownMenu_AddButton(si)
            end
          end
        end)

        local ov = self.setupOverrides[key]
        if ov and ov.kind == "raid" then
          UIDropDownMenu_SetText("Other", slotUI.dd)
        elseif ov and ov.kind == "empty" then
          UIDropDownMenu_SetText("Empty", slotUI.dd)
        elseif ov and ov.kind == "slot" then
          UIDropDownMenu_SetText("from "..tostring(ov.sourceKey or "?"), slotUI.dd)
        else
          UIDropDownMenu_SetText("Default", slotUI.dd)
        end
      end
    end
  end
end

function TC:CreateSetupFrame()
  local f = CreateFrame("Frame", "TacticaCompositionSetupFrame", UIParent)
  f:SetWidth(790); f:SetHeight(570)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24, insets={left=8,right=8,top=8,bottom=8} })
  f:SetMovable(true); f:EnableMouse(true); f:SetToplevel(true); f:SetFrameStrata("DIALOG")
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
  title:SetText("TACTICA COMPOSITION TOOL - 3/3. Setup")
  title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
  sub:SetWidth(740)
  sub:SetJustifyH("LEFT")
  sub:SetText("Allocate all unlisted or unmatched players into groups. When your layout looks correct, press Sort groups to apply it to the live raid roster.")
  sub:SetTextColor(1,1,1)

  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -82)
  sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -82)
  sep:SetTexture(1, 1, 1)
  if sep.SetVertexColor then sep:SetVertexColor(1, 1, 1, 0.25) end

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local scroll = CreateFrame("ScrollFrame", "TacticaCompositionSetupScrollFrame", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -94)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 48)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetWidth(728); content:SetHeight(1)
  scroll:SetScrollChild(content)

  f.groupSlots = {}
  local groupW, groupH = 357, 123
  local colGap, rowGap = 14, 5
  local topOffset = 2
  local g
  for g=1,8 do
    local col = math.mod((g-1), 2)
    local row = math.floor((g-1) / 2)
    local gf = CreateFrame("Frame", nil, content)
    gf:SetWidth(groupW); gf:SetHeight(groupH)
    local yoff = topOffset + (row * (groupH + rowGap))
    gf:SetPoint("TOPLEFT", content, "TOPLEFT", col * (groupW + colGap), -yoff)
    gf:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    gf:SetBackdropColor(0,0,0,0.45)

    local gtitle = gf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gtitle:SetPoint("TOPLEFT", gf, "TOPLEFT", 8, -6)
    gtitle:SetText("Group "..g)
    gtitle:SetTextColor(1,1,1)

    f.groupSlots[g] = {}
    local sidx
    for sidx=1,5 do
      local rowf = CreateFrame("Frame", nil, gf)
      rowf:SetWidth(groupW-14); rowf:SetHeight(26)
      rowf:SetPoint("TOPLEFT", gf, "TOPLEFT", 7, -8 - (sidx*17))

      local label = rowf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("LEFT", rowf, "LEFT", 0, 0)
      label:SetWidth(250)
      label:SetJustifyH("LEFT")
      label:SetText("-")

      local dd = CreateFrame("Frame", "TacticaCompositionSetupDropDownG"..g.."S"..sidx, rowf, "UIDropDownMenuTemplate")
      dd:SetPoint("LEFT", label, "RIGHT", -37, -2)
      UIDropDownMenu_SetWidth(96, dd)

      f.groupSlots[g][sidx] = { frame=rowf, label=label, dd=dd }
    end
  end

  local totalRows = 4
  local totalW = (groupW * 2) + colGap
  local totalH = topOffset + (totalRows * groupH) + ((totalRows - 1) * rowGap)
  content:SetWidth(totalW)
  content:SetHeight(totalH + 8)

  local btnImport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnImport:SetWidth(130); btnImport:SetHeight(24)
  btnImport:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
  btnImport:SetText("<- 1/3. Import")
  btnImport:SetScript("OnClick", function()
    f:Hide()
    TC:ShowImportFrame()
  end)

  local btnMatching = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnMatching:SetWidth(130); btnMatching:SetHeight(24)
  btnMatching:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
  btnMatching:SetText("2/3. Matching")
  btnMatching:SetScript("OnClick", function()
    f:Hide()
    TC:ShowCompositionFrame()
  end)

  local btnKeywordInvite = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnKeywordInvite:SetWidth(130); btnKeywordInvite:SetHeight(24)
  btnKeywordInvite:SetPoint("RIGHT", btnMatching, "LEFT", -6, 0)
  btnKeywordInvite:SetText("Keyword invite")
  StyleAccentButton(btnKeywordInvite)
  local hasValidCurrent = HasValidCompositionText(TacticaDB.Composition.current and TacticaDB.Composition.current.raw or "")
  local canSortCurrent = hasValidCurrent and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
  SetAccentButtonEnabled(btnKeywordInvite, hasValidCurrent)
  btnKeywordInvite:SetScript("OnClick", function() OpenKeywordInvite() end)

  local btnSortRaid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSortRaid:SetWidth(130); btnSortRaid:SetHeight(24)
  btnSortRaid:SetPoint("LEFT", btnMatching, "RIGHT", 6, 0)
  btnSortRaid:SetText("Sort groups")
  StyleAccentButton(btnSortRaid)
  SetAccentButtonEnabled(btnSortRaid, canSortCurrent)
  btnSortRaid:SetScript("OnClick", function()
    TC:SortRaidToSetupGroups()
  end)

  local btnSetup = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSetup:SetWidth(130); btnSetup:SetHeight(24)
  btnSetup:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  btnSetup:SetText("3/3. Setup ->")
  btnSetup:Disable()

  f.btnKeywordInvite = btnKeywordInvite
  f.btnSortRaid = btnSortRaid

  self.setupFrame = f
end

local _wasInRaid = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:RegisterEvent("PARTY_LEADER_CHANGED")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function()
  EnsureDB()
  if event == "CHAT_MSG_ADDON" then
    if arg1 == "TACTICA" then
      if TC.viewFrame and TC.viewFrame:IsShown() then TC:RefreshCompositionRows() end
      if TC.setupFrame and TC.setupFrame:IsShown() then TC:RefreshSetupFrame() end
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    _wasInRaid = UnitInRaid and UnitInRaid("player") and true or false
    return
  end

  if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_LEADER_CHANGED" then
    local inRaid = UnitInRaid and UnitInRaid("player") and true or false
    if _wasInRaid and (not inRaid) then
      TacticaDB.Composition.current = nil
      TacticaDB.Composition.splitConfig = nil
      if TC.viewFrame then TC.viewFrame:Hide() end
      if TC.importFrame then TC.importFrame:Hide() end
      if TC.setupFrame then TC.setupFrame:Hide() end
      ResetSetupOverrides()
    end
    _wasInRaid = inRaid
    if TC.viewFrame and TC.viewFrame:IsShown() then
      TC:RefreshCompositionRows()
      local hasValidCurrent = HasValidCompositionText(TacticaDB.Composition.current and TacticaDB.Composition.current.raw or "")
      local canSortCurrent = hasValidCurrent and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
      if TC.viewFrame.btnKeywordInvite then SetAccentButtonEnabled(TC.viewFrame.btnKeywordInvite, hasValidCurrent) end
      if TC.viewFrame.btnSortRaid then SetAccentButtonEnabled(TC.viewFrame.btnSortRaid, canSortCurrent) end
    end
    if TC.setupFrame and TC.setupFrame:IsShown() then
      TC:RefreshSetupFrame()
      local hasValidCurrent = HasValidCompositionText(TacticaDB.Composition.current and TacticaDB.Composition.current.raw or "")
      local canSortCurrent = hasValidCurrent and CanManageRaidSubgroups() and (UnitInRaid and UnitInRaid("player"))
      if TC.setupFrame.btnKeywordInvite then SetAccentButtonEnabled(TC.setupFrame.btnKeywordInvite, hasValidCurrent) end
      if TC.setupFrame.btnSortRaid then SetAccentButtonEnabled(TC.setupFrame.btnSortRaid, canSortCurrent) end
    end
  end
end)
