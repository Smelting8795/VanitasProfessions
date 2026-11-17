-- Made by Tyska for Vanitas Guild EU WoW Forever PvP

local ADDON_NAME = ...
local PREFIX     = "VanitasProf"
local PROTOCOL   = 1
local DB_VERSION = 5

VanitasProfessionsDB = VanitasProfessionsDB or {}

local roster = {}
local myCraftables = {}

local SendAddon      = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

local function After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
    else
        local waiter, total = CreateFrame("Frame"), 0
        waiter:SetScript("OnUpdate", function(self, e)
            total = total + e
            if total >= delay then
                self:SetScript("OnUpdate", nil)
                fn()
            end
        end)
    end
end

local KNOWN_PROFESSIONS = {}
for _, n in ipairs({
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Inscription", "Jewelcrafting", "Leatherworking", "Mining", "Skinning",
    "Tailoring", "Cooking", "First Aid", "Fishing", "Archaeology",
}) do
    KNOWN_PROFESSIONS[n:lower()] = true
end

local function CanonKey(raw)
    if not raw or raw == "" then return raw end
    local name, realm = raw:match("^(.-)%-(.*)$")
    if not name then name, realm = raw, "" end
    local first = name:match("^%S+") or name
    realm = (realm ~= "" and realm or (GetRealmName() or "")):gsub("%s+", "")
    if realm == "" then return first end
    return first .. "-" .. realm
end

local function MyFullName() return CanonKey(UnitName("player")) end
local function KeyFor(sender) return CanonKey(sender) end
local function ShortName(key) return key:match("^[^-]+") or key end

local function Entry(key)
    local e = roster[key]
    if not e then
        e = { professions = {}, craftables = {}, updated = time() }
        roster[key] = e
    end
    e.craftables = e.craftables or {}
    return e
end

local function ScanMyProfessions()
    local profs = {}
    if GetProfessions and GetProfessionInfo then
        local p1, p2, arch, fish, cook = GetProfessions()
        for _, index in ipairs({ p1, p2, arch, fish, cook }) do
            if index then
                local name, _, skill, maxSkill = GetProfessionInfo(index)
                if name and name ~= "" then
                    profs[#profs + 1] = { name = name, skill = skill or 0, max = maxSkill or 0 }
                end
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
            if skillName and not isHeader and KNOWN_PROFESSIONS[skillName:lower()] then
                profs[#profs + 1] = { name = skillName, skill = skillRank or 0, max = skillMaxRank or 0 }
            end
        end
    end
    return profs
end

local function KnowsProfession(target)
    target = target:lower()
    for _, p in ipairs(ScanMyProfessions()) do
        if p.name:lower() == target then return true end
    end
    return false
end

local function Serialize(profs)
    local parts = {}
    for _, p in ipairs(profs) do
        parts[#parts + 1] = p.name .. "^" .. p.skill .. "^" .. p.max
    end
    return table.concat(parts, ";")
end

local function Deserialize(str)
    local profs = {}
    for record in string.gmatch(str or "", "[^;]+") do
        local name, skill, max = string.match(record, "([^%^]+)%^([^%^]+)%^([^%^]+)")
        if name then
            profs[#profs + 1] = { name = name, skill = tonumber(skill) or 0, max = tonumber(max) or 0 }
        end
    end
    return profs
end

local sendQueue, sending = {}, false

local function PumpQueue()
    if #sendQueue == 0 then sending = false; return end
    local msg = table.remove(sendQueue, 1)
    if IsInGuild() then SendAddon(PREFIX, msg, "GUILD") end
    After(0.3, PumpQueue)
end

local function Enqueue(msg)
    sendQueue[#sendQueue + 1] = msg
    if not sending then sending = true; After(0, PumpQueue) end
end

local RefreshUI

local function RefreshIfShown()
    if VanitasProfessions_UI and VanitasProfessions_UI:IsShown() then RefreshUI() end
end

local function Broadcast()
    if not IsInGuild() then return end
    local profs = ScanMyProfessions()
    local e = Entry(MyFullName())
    e.professions = profs
    e.updated = time()
    SendAddon(PREFIX, PROTOCOL .. "|U|" .. Serialize(profs), "GUILD")
    RefreshIfShown()
end

local function BroadcastCraftables(prof)
    if not IsInGuild() then return end
    local list = myCraftables[prof]
    if not list or #list == 0 then return end

    local chunks, cur = {}, ""
    for _, rec in ipairs(list) do
        local piece = rec.name .. "\31" .. (rec.recipeID or "") .. "\31" .. (rec.itemID or "")
        local cand = (cur == "") and piece or (cur .. "\t" .. piece)
        if #cand > 230 then
            chunks[#chunks + 1] = cur
            cur = piece
        else
            cur = cand
        end
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end

    local total = #chunks
    for idx, payload in ipairs(chunks) do
        Enqueue(PROTOCOL .. "|C|" .. prof .. "|" .. idx .. "|" .. total .. "|" .. payload)
    end
end

local function BroadcastAllCraftables()
    for prof in pairs(myCraftables) do BroadcastCraftables(prof) end
end

local function RequestAll()
    if not IsInGuild() then return end
    SendAddon(PREFIX, PROTOCOL .. "|R|", "GUILD")
end

local broadcastPending = false
local function ScheduleBroadcast()
    if broadcastPending then return end
    broadcastPending = true
    After(3, function()
        broadcastPending = false
        Broadcast()
    end)
end

local function ExpandAllTradeSkill()
    if not ExpandTradeSkillSubClass then return end
    local guard = 0
    local i = 1
    while i <= (GetNumTradeSkills() or 0) and guard < 200 do
        guard = guard + 1
        local _, skillType, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" and not isExpanded then
            ExpandTradeSkillSubClass(i)
            i = 1
        else
            i = i + 1
        end
    end
end

local function sameRecipeList(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do
        if (a[i].name or "") ~= (b[i].name or "") then return false end
    end
    return true
end

local function ScanTradeSkill()
    local prof, list

    if GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo then
        local p = GetTradeSkillLine()
        if p and p ~= "" and p ~= "UNKNOWN" and (GetNumTradeSkills() or 0) > 0 then
            ExpandAllTradeSkill()
            local l = {}
            for i = 1, (GetNumTradeSkills() or 0) do
                local name, skillType = GetTradeSkillInfo(i)
                if name and skillType ~= "header" then
                    local itemID
                    if GetTradeSkillItemLink then
                        local link = GetTradeSkillItemLink(i)
                        if link then itemID = tonumber(link:match("item:(%d+)")) end
                    end
                    l[#l + 1] = { name = name, itemID = itemID }
                end
            end
            if #l > 0 then prof, list = p, l end
        end
    end

    if not list and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
        local u = C_TradeSkillUI
        local p
        if u.GetTradeSkillLine then
            local a, b = u.GetTradeSkillLine()
            if type(b) == "string" and b ~= "" then p = b
            elseif type(a) == "string" and a ~= "" then p = a end
        end
        if (not p or p == "") and u.GetBaseProfessionInfo then
            local ok, info = pcall(u.GetBaseProfessionInfo)
            if ok and type(info) == "table" then p = info.professionName or info.name end
        end
        if (not p or p == "") and u.GetTradeSkillLine and GetProfessions and GetProfessionInfo then
            local id = u.GetTradeSkillLine()
            if id then
                local a1, a2, a3, a4, a5 = GetProfessions()
                for _, idx in ipairs({ a1 or false, a2 or false, a3 or false, a4 or false, a5 or false }) do
                    if idx then
                        local pname, _, _, _, _, _, sl = GetProfessionInfo(idx)
                        if sl == id then p = pname; break end
                    end
                end
            end
        end
        local ids = u.GetAllRecipeIDs()
        if ids and #ids > 0 then
            local l = {}
            for _, id in ipairs(ids) do
                local info = u.GetRecipeInfo(id)
                if info and info.name and info.learned ~= false then
                    local itemID
                    if u.GetRecipeItemLink then
                        local link = u.GetRecipeItemLink(id)
                        if link then itemID = tonumber(link:match("item:(%d+)")) end
                    end
                    l[#l + 1] = { name = info.name, recipeID = id, itemID = itemID }
                end
            end
            if #l > 0 then prof, list = (p and p ~= "" and p) or "Profession", l end
        end
    end

    if not list then return end
    if sameRecipeList(myCraftables[prof], list) then return end

    myCraftables[prof] = list
    VanitasProfessionsDB.myCraftables = myCraftables

    local e = Entry(MyFullName())
    e.craftables[prof] = list
    e.updated = time()

    BroadcastCraftables(prof)
    RefreshIfShown()
    print(string.format("|cff8e7cc3VanitasProfessions|r: learned |cffffd100%d|r %s recipes.", #list, prof))
end

local function ScanCraft()
    if not (GetNumCrafts and GetCraftInfo) then return end
    if not KnowsProfession("Enchanting") then return end

    local prof = "Enchanting"
    local list = {}
    for i = 1, (GetNumCrafts() or 0) do
        local name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" then
            list[#list + 1] = { name = name }
        end
    end
    if #list == 0 then return end
    if sameRecipeList(myCraftables[prof], list) then return end

    myCraftables[prof] = list
    VanitasProfessionsDB.myCraftables = myCraftables

    local e = Entry(MyFullName())
    e.craftables[prof] = list
    e.updated = time()

    BroadcastCraftables(prof)
    RefreshIfShown()
    print(string.format("|cff8e7cc3VanitasProfessions|r: learned |cffffd100%d|r %s recipes.", #list, prof))
end

local tsPending, crPending = false, false
local function ScheduleScanTradeSkill()
    if tsPending then return end
    tsPending = true
    After(0.5, function() tsPending = false; ScanTradeSkill() end)
end
local function ScheduleScanCraft()
    if crPending then return end
    crPending = true
    After(0.5, function() crPending = false; ScanCraft() end)
end

local craftBuffer = {}

local function OnAddonMessage(prefix, text, _, sender)
    if prefix ~= PREFIX then return end
    local proto, mtype, payload = string.match(text, "^(%d+)|(%a)|(.*)$")
    if not proto or tonumber(proto) ~= PROTOCOL then return end

    if mtype == "U" then
        local key = KeyFor(sender)
        local e = Entry(key)
        e.professions = Deserialize(payload)
        e.updated = time()
        RefreshIfShown()

    elseif mtype == "R" then
        After(math.random() * 4, function()
            Broadcast()
            BroadcastAllCraftables()
        end)

    elseif mtype == "C" then
        local prof, idx, total, names = string.match(payload, "^([^|]+)|(%d+)|(%d+)|(.*)$")
        if not prof then return end
        idx, total = tonumber(idx), tonumber(total)

        local key = KeyFor(sender)
        craftBuffer[key] = craftBuffer[key] or {}
        local buf = craftBuffer[key][prof]
        if not buf or buf.total ~= total then
            buf = { total = total, parts = {}, got = 0 }
            craftBuffer[key][prof] = buf
        end
        if not buf.parts[idx] then
            buf.parts[idx] = names
            buf.got = buf.got + 1
        end
        if buf.got >= buf.total then
            local all = {}
            for i = 1, buf.total do
                for token in string.gmatch(buf.parts[i] or "", "[^\t]+") do
                    local nm, rid, iid = token:match("^(.-)\31(.-)\31(.*)$")
                    if nm then
                        all[#all + 1] = { name = nm, recipeID = tonumber(rid), itemID = tonumber(iid) }
                    else
                        all[#all + 1] = { name = token }
                    end
                end
            end
            Entry(key).craftables[prof] = all
            craftBuffer[key][prof] = nil
            RefreshIfShown()
        end
    end
end

local function CreateUI()
    local backdropTmpl = (BackdropTemplateMixin ~= nil) and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "VanitasProfessions_UI", UIParent, backdropTmpl)
    f:SetSize(560, 500)
    f:SetPoint("CENTER")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.06, 0.07, 0.09, 1)
        f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    end

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\Buttons\\WHITE8X8")
    header:SetVertexColor(0.13, 0.14, 0.18, 1)
    header:SetPoint("TOPLEFT", 5, -5)
    header:SetPoint("TOPRIGHT", -5, -5)
    header:SetHeight(32)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 16, -13)
    f.title:SetText("|cff8e7cc3Vanitas|r Professions")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -3)
    close:SetScript("OnClick", function() f:Hide() end)

    local function makeBox(yOff, labelText)
        local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        box:SetSize(260, 22)
        box:SetPoint("TOPLEFT", 20, yOff)
        box:SetAutoFocus(false)
        box:SetScript("OnTextChanged", function() RefreshUI() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetPoint("LEFT", box, "RIGHT", 10, 0)
        lbl:SetText(labelText)
        return box
    end

    f.memberSearch = makeBox(-48, "filter by guild member")
    f.search       = makeBox(-76, "filter by profession")
    f.itemSearch   = makeBox(-104, "filter by item")

    f.memberSearch:SetScript("OnTabPressed", function() f.search:SetFocus() end)
    f.search:SetScript("OnTabPressed", function() f.itemSearch:SetFocus() end)
    f.itemSearch:SetScript("OnTabPressed", function() f.memberSearch:SetFocus() end)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(1, 1, 1, 0.12)
    divider:SetPoint("TOPLEFT", 12, -132)
    divider:SetPoint("TOPRIGHT", -12, -132)
    divider:SetHeight(1)

    local scroll = CreateFrame("ScrollFrame", "VanitasProfessions_Scroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -140)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    f.content = content
    f.lines = {}

    scroll:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(w)
        RefreshIfShown()
    end)

    tinsert(UISpecialFrames, "VanitasProfessions_UI")

    f:Hide()
    return f
end

local function GetLine(f, i)
    local b = f.lines[i]
    if not b then
        b = CreateFrame("Button", nil, f.content)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.fs:SetJustifyH("LEFT")
        b:SetScript("OnEnter", function(self)
            if not self.tipKind then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = false
            if self.recipeID and GameTooltip.SetSpellByID then
                ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.recipeID)
            end
            if not ok and self.itemID then
                if GameTooltip.SetItemByID then
                    ok = pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
                end
                if not ok then
                    pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemID)
                    ok = true
                end
            end
            if not ok then GameTooltip:SetText(self.plain or "", 1, 1, 1, 1, true) end
            GameTooltip:Show()
            self.bg:SetVertexColor(1, 1, 1, 0.12)
        end)
        b:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self.bg:SetVertexColor(1, 1, 1, self.baseAlpha or 0)
        end)
        f.lines[i] = b
    end
    return b
end

local function SortedKeys()
    local keys = {}
    for k in pairs(roster) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return a:lower() < b:lower() end)
    return keys
end

local SEP = "   |cff5a5a5a-|r   "

function RefreshUI()
    local f = VanitasProfessions_UI
    if not f then return end

    local w = f.content:GetWidth()
    if not w or w < 50 then w = 500 end

    for _, b in ipairs(f.lines) do b:Hide() end

    local memberText = (f.memberSearch:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local itemText   = (f.itemSearch:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local profText   = (f.search:GetText() or ""):lower()

    local st = { y = -4, n = 0 }

    local function line(opts)
        st.n = st.n + 1
        local b = GetLine(f, st.n)
        local indent = opts.indent or 8
        b.fs:ClearAllPoints()
        b.fs:SetPoint("TOPLEFT", b, "TOPLEFT", indent, -2)
        b.fs:SetWidth(w - indent - 10)
        b.fs:SetText(opts.text)
        b.plain = opts.text
        b.baseAlpha = opts.header and 0.06 or 0
        b.bg:SetVertexColor(1, 1, 1, b.baseAlpha)
        b.tipKind = opts.tipKind
        b.recipeID = opts.recipeID
        b.itemID = opts.itemID
        if opts.tipKind then b:EnableMouse(true) else b:EnableMouse(false) end
        local h = math.max(b.fs:GetStringHeight(), 1) + (opts.header and 10 or 7)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, st.y)
        b:SetPoint("TOPRIGHT", 0, st.y)
        b:SetHeight(h)
        b:Show()
        st.y = st.y - h
    end

    local function nameMatches(key)
        return memberText == "" or ShortName(key):lower():find(memberText, 1, true) ~= nil
    end

    if itemText ~= "" then
        for _, key in ipairs(SortedKeys()) do
            if nameMatches(key) then
                local data = roster[key]
                local hits = {}
                if data.craftables then
                    for prof, plist in pairs(data.craftables) do
                        for _, rec in ipairs(plist) do
                            if rec.name and rec.name:lower():find(itemText, 1, true) then
                                hits[#hits + 1] = { rec = rec, prof = prof }
                            end
                        end
                    end
                end
                if #hits > 0 then
                    line{ text = "|cff8e7cc3" .. ShortName(key) .. "|r", header = true }
                    for _, hit in ipairs(hits) do
                        local tag = (hit.prof and hit.prof ~= "" and hit.prof ~= "Profession")
                            and ("  |cff808080(" .. hit.prof .. ")|r") or ""
                        line{
                            text = "|cffffffff" .. hit.rec.name .. "|r" .. tag,
                            indent = 22, tipKind = "item",
                            recipeID = hit.rec.recipeID, itemID = hit.rec.itemID,
                        }
                    end
                end
            end
        end
        if st.n == 0 then
            line{ text = "|cffff8080No match.|r Nobody has a known recipe for that. "
                .. "They must open the profession once so it can be learned." }
        end
    else
        for _, key in ipairs(SortedKeys()) do
            if nameMatches(key) then
                local data = roster[key]
                local profStrings = {}
                for _, p in ipairs(data.professions) do
                    if profText == "" or p.name:lower():find(profText, 1, true) then
                        profStrings[#profStrings + 1] =
                            string.format("%s |cffffd100%d|r/%d", p.name, p.skill, p.max)
                    end
                end
                if #profStrings > 0 then
                    line{ text = "|cff8e7cc3" .. ShortName(key) .. "|r", header = true }
                    line{ text = table.concat(profStrings, SEP), indent = 22 }
                end
            end
        end
        if st.n == 0 then
            line{ text = "No data yet. Guildmates need the addon too - try /vp request." }
        end
    end

    f.content:SetHeight(math.max(1, -st.y + 4))
end

SLASH_VANITASPROFESSIONS1 = "/vp"
SLASH_VANITASPROFESSIONS2 = "/vanitasprof"
SlashCmdList["VANITASPROFESSIONS"] = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "scan" then
        Broadcast()
        BroadcastAllCraftables()
        print("|cff8e7cc3VanitasProfessions|r: broadcast sent.")
    elseif msg == "request" then
        RequestAll()
        print("|cff8e7cc3VanitasProfessions|r: requested guild data.")
    elseif msg == "mine" then
        local any = false
        for prof, list in pairs(myCraftables) do
            any = true
            print(string.format("|cff8e7cc3VanitasProfessions|r: %s - |cffffd100%d|r recipes", prof, #list))
        end
        if not any then
            print("|cff8e7cc3VanitasProfessions|r: no recipes learned yet. "
                .. "Open each profession window once (Tailoring, Enchanting, ...).")
        end
    elseif msg == "diag" then
        local function has(v) return v and "|cff40ff40yes|r" or "|cffff4040no|r" end
        print("|cff8e7cc3Vanitas diag|r (open a profession window first, then run this)")
        print("  TOC=" .. tostring(select(4, GetBuildInfo())))
        print("  GetProfessions " .. has(GetProfessions))
        print("  GetNumTradeSkills " .. has(GetNumTradeSkills)
            .. (GetNumTradeSkills and ("  now=" .. tostring(GetNumTradeSkills())) or ""))
        print("  GetTradeSkillLine " .. has(GetTradeSkillLine)
            .. (GetTradeSkillLine and ("  ='" .. tostring(GetTradeSkillLine()) .. "'") or ""))
        print("  C_TradeSkillUI " .. has(C_TradeSkillUI))
        if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
            local ids = C_TradeSkillUI.GetAllRecipeIDs()
            print("    modern recipes now=" .. tostring(ids and #ids or 0))
        end
        print("  GetNumCrafts " .. has(GetNumCrafts)
            .. (GetNumCrafts and ("  now=" .. tostring(GetNumCrafts())) or ""))
    else
        if not VanitasProfessions_UI then CreateUI() end
        if VanitasProfessions_UI:IsShown() then
            VanitasProfessions_UI:Hide()
        else
            RefreshUI()
            VanitasProfessions_UI:Show()
        end
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "CHAT_MSG_ADDON", "SKILL_LINES_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
    "CRAFT_SHOW", "CRAFT_UPDATE",
}) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)

    elseif event == "SKILL_LINES_CHANGED" then
        ScheduleBroadcast()

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE"
        or event == "TRADE_SKILL_LIST_UPDATE" then
        ScheduleScanTradeSkill()

    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        ScheduleScanCraft()

    elseif event == "PLAYER_LOGIN" then
        if RegisterPrefix then RegisterPrefix(PREFIX) end

        if VanitasProfessionsDB.version ~= DB_VERSION then
            VanitasProfessionsDB.roster = nil
            VanitasProfessionsDB.version = DB_VERSION
        end

        local mc = VanitasProfessionsDB.myCraftables
        if type(mc) == "table" then
            for _, plist in pairs(mc) do
                if type(plist) ~= "table" or (plist[1] ~= nil and type(plist[1]) ~= "table") then
                    mc = nil
                    VanitasProfessionsDB.myCraftables = nil
                end
                break
            end
        end

        if type(VanitasProfessionsDB.roster) == "table" then
            for k, v in pairs(VanitasProfessionsDB.roster) do roster[k] = v end
        end
        if type(mc) == "table" then
            myCraftables = mc
            local e = Entry(MyFullName())
            for prof, list in pairs(myCraftables) do e.craftables[prof] = list end
        end

        After(5, function()
            RequestAll()
            Broadcast()
            BroadcastAllCraftables()
        end)

        print("|cff8e7cc3VanitasProfessions|r loaded. Type |cffffff00/vp|r to open.")
        if next(myCraftables) == nil then
            print("|cff8e7cc3VanitasProfessions|r: open each profession window once "
                .. "(and Enchanting) so your recipes can be shared for item search.")
        end

    elseif event == "PLAYER_LOGOUT" then
        VanitasProfessionsDB.roster = roster
        VanitasProfessionsDB.myCraftables = myCraftables
        VanitasProfessionsDB.version = DB_VERSION
    end
end)
