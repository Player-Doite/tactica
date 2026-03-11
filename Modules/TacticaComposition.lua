-- TacticaComposition.lua - Raid-Helper composition import/mapping tool

TacticaComposition = TacticaComposition or {}
local TC = TacticaComposition

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
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(s) return string.lower(tostring(s or "")) end

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

local function roleFromSlot(slot)
  local classN = lower(slot.className)
  local specN = lower(slot.specName)
  if classN == "tank" or string.find(specN, "protection", 1, true) or specN == "guardian" then return "Tank" end
  if string.find(specN, "restoration", 1, true) or string.find(specN, "holy", 1, true) or specN == "discipline" then return "Healer" end
  return "DPS"
end

local function hexToRGB(hex)
  hex = tostring(hex or ""):gsub("#", "")
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

local function SetButtonEnabled(btn, enabled)
  if not btn then return end
  if enabled then btn:Enable() else btn:Disable() end
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

local function FindAutoMatch(discordName)
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

function TC:ShowImportFrame()
  EnsureDB()
  if not self.importFrame then self:CreateImportFrame() end
  local existing = TacticaDB.Composition.current and TacticaDB.Composition.current.raw or ""
  self.importFrame.input:SetText(existing)
  SetButtonEnabled(self.importFrame.submit, trim(existing) ~= "")
  self.importFrame:Show()
end

function TC:CreateImportFrame()
  local f = CreateFrame("Frame", "TacticaCompositionImportFrame", UIParent)
  f:SetWidth(760); f:SetHeight(520)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24, insets={left=8,right=8,top=8,bottom=8} })
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -18)
  title:SetText("TACTICA COMPOSITION TOOL")
  title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sub:SetPoint("TOP", title, "BOTTOM", 0, -10)
  sub:SetText("Import JSON export from Raid-Helper's Composition Tool, after you have arranged all groups.")
  sub:SetTextColor(1,1,1)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local bg = CreateFrame("Frame", nil, f)
  bg:SetWidth(700); bg:SetHeight(360)
  bg:SetPoint("TOP", sub, "BOTTOM", 0, -14)
  bg:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
  bg:SetBackdropColor(0,0,0,0.85)

  local edit = CreateFrame("EditBox", "TacticaCompositionImportEdit", bg)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(668); edit:SetHeight(328)
  edit:SetPoint("TOPLEFT", bg, "TOPLEFT", 14, -14)
  edit:SetAutoFocus(false)

  local submit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  submit:SetWidth(120); submit:SetHeight(24)
  submit:SetPoint("BOTTOM", f, "BOTTOM", -70, 20)
  submit:SetText("Submit")
  submit:Disable()

  local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  cancel:SetWidth(120); cancel:SetHeight(24)
  cancel:SetPoint("LEFT", submit, "RIGHT", 16, 0)
  cancel:SetText("Cancel")

  cancel:SetScript("OnClick", function() f:Hide() end)
  edit:SetScript("OnTextChanged", function()
    SetButtonEnabled(submit, trim(edit:GetText()) ~= "")
  end)
  submit:SetScript("OnClick", function()
    local parsed = ParseCompositionJson(edit:GetText())
    if not parsed then
      cfmsg("Wrong format. Please paste the JSON export directly from Raid-Helper's Composition Tool.")
      return
    end
    TacticaDB.Composition.current = parsed
    f:Hide()
    TC:ShowCompositionFrame()
  end)

  f.input = edit
  f.submit = submit
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

  for i=1, table.getn(data.slots) do
    local slot = data.slots[i]
    local row = rows[i]
    if not row then
      row = CreateFrame("Frame", nil, f.content)
      row:SetWidth(700); row:SetHeight(24)
      if i == 1 then row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0) else row:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, -4) end

      row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.label:SetWidth(350); row.label:SetJustifyH("LEFT")

      row.input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
      row.input:SetAutoFocus(false)
      row.input:SetWidth(145); row.input:SetHeight(20)
      row.input:SetPoint("LEFT", row.label, "RIGHT", 6, 0)

      row.add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      row.add:SetWidth(35); row.add:SetHeight(20)
      row.add:SetPoint("LEFT", row.input, "RIGHT", 4, 0)
      row.add:SetText("Add")

      row.dd = CreateFrame("Frame", nil, row, "UIDropDownMenuTemplate")
      row.dd:SetPoint("LEFT", row.add, "RIGHT", -4, -3)
      UIDropDownMenu_SetWidth(150, row.dd)

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

  local last = rows[table.getn(data.slots)]
  if last then
    f.content:SetHeight(math.max(1, table.getn(data.slots) * 28 + 8))
  end
end

function TC:ShowCompositionFrame()
  EnsureDB()
  if not TacticaDB.Composition.current then self:ShowImportFrame(); return end
  if not self.viewFrame then self:CreateCompositionFrame() end
  self:RefreshCompositionRows()
  self.viewFrame:Show()
end

function TC:CreateCompositionFrame()
  local f = CreateFrame("Frame", "TacticaCompositionViewFrame", UIParent)
  f:SetWidth(820); f:SetHeight(560)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24, insets={left=8,right=8,top=8,bottom=8} })

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -18)
  title:SetText("TACTICA COMPOSITION TOOL")
  title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 48)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(730); content:SetHeight(1)
  scroll:SetScrollChild(content)

  local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  importBtn:SetWidth(120); importBtn:SetHeight(24)
  importBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
  importBtn:SetText("Import")
  importBtn:SetScript("OnClick", function()
    f:Hide()
    TC:ShowImportFrame()
  end)

  f.rows = {}
  f.content = content
  self.viewFrame = f
end

local _wasInRaid = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
  EnsureDB()
  if event == "PLAYER_LOGIN" then
    _wasInRaid = UnitInRaid and UnitInRaid("player") and true or false
    return
  end

  if event == "RAID_ROSTER_UPDATE" then
    local inRaid = UnitInRaid and UnitInRaid("player") and true or false
    if _wasInRaid and (not inRaid) then
      TacticaDB.Composition.current = nil
      if TC.viewFrame then TC.viewFrame:Hide() end
      if TC.importFrame then TC.importFrame:Hide() end
    end
    _wasInRaid = inRaid
    if TC.viewFrame and TC.viewFrame:IsShown() then
      TC:RefreshCompositionRows()
    end
  end
end)
