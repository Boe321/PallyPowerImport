--[[  PallyPower Import
      Applies a PPI1 string (from the preset generator) to PallyPower as a
      direct assignment -- NOT a saved preset.

      String generator:  https://github.com/Boe321/pallypower-preset
      PPI1 format spec:   https://github.com/Boe321/pallypower-preset/blob/main/docs/ppi1-format.md

      Deliberately lean: NO blessing / diff preview in game (that comes later via
      the website / Discord). Just hard error checks, then Import.

      Import = DIRECT ASSIGNMENT like clicking the grid: it sets
      PallyPower_Assignments / _NormalAssignments / _AuraAssignments and
      broadcasts (PASSIGN / NASSIGN / AASSIGN). PallyPower_SavedPresets is NOT
      touched -- other people's saved presets stay intact.
      Broadcasting to other paladins works when you are leader/assist OR
      "Free Assign" is on; assignments for yourself always go through.

      Flow:  /ppi  ->  paste string  ->  Import  (window closes on success).

      PPI1 format:
        PPI1
        # format 1
        # expansion bcc
        # event 100000000000000001
        pala Dawnhammer aura 7
        bless 3 3 3 3 3 3 3 3 3        -- 9 classes (1..9), 0 = no blessing
        over 4 Bearwall 6             -- single override: class, target, blessing
        pala Shieldbash aura 1
        bless 4 4 1 4 4 4 4 4 4

      Alternatively one line:  PPI1:<base64 of the text above>
--]]

-- replaced by the packager at release time; "dev" in a raw checkout
local VERSION = "@project-version@"
if VERSION:find("@") then VERSION = "dev" end
local MAX_FORMAT = 1
local DB_SCHEMA = 1
local MAXCLASS = 9

local BLESSING_NAME = { [0] = "-", "Wisdom", "Might", "Kings", "Salvation", "Light", "Sanctuary" }

local C_R, C_G = "|cff33ff99", "|r"
local C_ERR = "|cffff5555"

local atan2 = math.atan2 or math.atan

PallyPowerImportDB = PallyPowerImportDB or {}

-- ================================================================ strings
local L = {
	READY           = "Ready. Paste a PPI1 string.",
	IN_COMBAT       = "Blocked in combat.",
	ERR_PREFIX      = "Error: ",
	PARSER_ERROR    = "Parser error.",
	EMPTY           = "Empty string.",
	BAD_BASE64      = "Invalid base64 content.",
	NOT_PPI1        = "Not a PPI1 string (first line must be 'PPI1').",
	NO_PALADINS     = "No paladins in the string.",
	PALA_NO_NAME    = "Line %d: 'pala' without a name.",
	BLESS_NO_PALA   = "Line %d: 'bless' before 'pala'.",
	OVER_NO_PALA    = "Line %d: 'over' before 'pala'.",
	OVER_SYNTAX     = "Line %d: expected 'over <class> <target> <blessing>'.",
	FMT_UNSUPPORTED = "String format v%d is not supported (addon: v%d). Update the addon.",
	CLIENT_TBC      = "String is for TBC (6 blessings), this client only knows %d.",
	CLIENT_BLESS    = "Blessing ID %d (%s) does not exist on this client.",
	CLIENT_OVER     = "Override blessing ID %d not available.",
	BAD_NAME        = "Invalid paladin name.",
	BAD_AURA        = "Aura out of range 0..8 for %s.",
	BAD_BLESS       = "Blessing out of range 0..6 for %s (class %d).",
	BAD_OVER_CLASS  = "Override with invalid class %s for %s.",
	BAD_OVER        = "Invalid override %s for %s.",
	NOT_LOADED      = "PallyPower is not loaded.",
	CANT_COMBAT     = "Not possible in combat.",
	OK_SOLO         = "OK - %d paladin(s). Not in a group: local only.",
	OK_RAID         = "OK - %d paladin(s). Import goes to the raid.",
	OK_LIMITED      = "OK - %d paladin(s). Warning: no leader + Free Assign off - may not reach other paladins.",
	IMPORTING       = "Importing...",
	MODE_SOLO       = "set locally (not in a group).",
	MODE_RAID       = "sent to the raid.",
	MODE_LIMITED    = "sent - may not reach other paladins (no leader, Free Assign off).",
	TITLE           = "PallyPower Import",
	HINT            = "Paste a PPI1 string (Ctrl+V), then Import.",
	BTN_IMPORT      = "Import",
	BTN_CLEAR       = "Clear",
	BTN_CLOSE       = "Close",
	CHECK_MINIMAP   = "Minimap button",
	TIP_CLICK       = "Click: open / close the window",
	MM_ON           = "minimap button on.",
	MM_OFF          = "minimap button off.",
	PP_DETECTED     = "Aznamir detected",
	PP_MISSING      = "not found / incompatible",
	LOADED          = "loaded. /ppi to open.",
	NO_PP           = "PallyPower not found - addon inactive.",
}
local function say(msg) print(C_R .. "PallyPower Import|r " .. msg) end
local function sayErr(msg) print(C_ERR .. "PallyPower Import:|r " .. msg) end

-- ================================================================ utils
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function setEnabled(btn, on)
	if btn.SetEnabled then btn:SetEnabled(on)
	elseif on then btn:Enable() else btn:Disable() end
end

local function tokens(line)
	local t = {}
	for w in line:gmatch("%S+") do t[#t + 1] = w end
	return t
end

local function normName(n)
	return (tostring(n or ""):gsub("%-.*$", ""):lower())
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(data)
	data = tostring(data or ""):gsub("[^A-Za-z0-9+/=]", "")
	local out, bits, nbits = {}, 0, 0
	for i = 1, #data do
		local c = data:sub(i, i)
		if c == "=" then break end
		local idx = B64:find(c, 1, true)
		if not idx then return nil end
		bits = bits * 64 + (idx - 1)
		nbits = nbits + 6
		if nbits >= 8 then
			nbits = nbits - 8
			out[#out + 1] = string.char(math.floor(bits / (2 ^ nbits)) % 256)
			bits = bits % (2 ^ nbits)
		end
	end
	return table.concat(out)
end

-- ================================================================ SavedVars
local function initDB()
	local db = PallyPowerImportDB
	db.minimap = db.minimap or {}
	if db.minimap.angle == nil then db.minimap.angle = 220 end
	if db.minimap.hide == nil then db.minimap.hide = false end
	db.closeAfterApply = nil -- removed in 0.3
	db.schema = DB_SCHEMA
end

-- ================================================================ roster
local function currentRoster()
	local list = {}
	local function add(unit)
		if UnitExists(unit) and UnitIsPlayer(unit) then
			local _, cls = UnitClass(unit)
			local n = (GetUnitName and GetUnitName(unit, false)) or UnitName(unit)
			if n then list[#list + 1] = { name = n, isPala = (cls == "PALADIN") } end
		end
	end
	add("player")
	local prefix, count = "party", 4
	if IsInRaid() then prefix, count = "raid", 40 end
	for i = 1, count do add(prefix .. i) end
	return list
end

-- Silently maps string names to the real in-game names (for the assignment keys).
local function resolveNames(data)
	local byNorm = {}
	for _, e in ipairs(currentRoster()) do
		if e.isPala then byNorm[normName(e.name)] = e.name end
	end
	for _, p in ipairs(data.palas) do
		p.resolved = byNorm[normName(p.name)] or p.name
	end
end

-- ================================================================ parse
-- returns data, err
local function parseImport(text)
	text = trim(text)
	if text == "" then return nil, L.EMPTY end

	local head, rest = text:match("^(PPI1):(.+)$")
	if head and not rest:find("\n") then
		local decoded = b64decode(trim(rest))
		if not decoded or not decoded:find("^%s*PPI1") then
			return nil, L.BAD_BASE64
		end
		text = decoded
	end

	local lines = {}
	for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
	if trim(lines[1]) ~= "PPI1" then return nil, L.NOT_PPI1 end

	local data = { meta = {}, palas = {} }
	local cur

	for i = 2, #lines do
		local line = trim(lines[i])
		if line ~= "" then
			if line:sub(1, 1) == "#" then
				local k, v = line:match("^#%s*(%S+)%s+(.+)$")
				if k then data.meta[k] = trim(v) end
			else
				local tk = tokens(line)
				local dir = tk[1]
				if dir == "pala" then
					if not tk[2] then return nil, L.PALA_NO_NAME:format(i) end
					cur = { name = tk[2], aura = 0, bless = {}, over = {} }
					if tk[3] == "aura" then cur.aura = tonumber(tk[4]) or 0 end
					data.palas[#data.palas + 1] = cur
				elseif dir == "bless" then
					if not cur then return nil, L.BLESS_NO_PALA:format(i) end
					for c = 1, MAXCLASS do cur.bless[c] = tonumber(tk[c + 1] or 0) or 0 end
				elseif dir == "over" then
					if not cur then return nil, L.OVER_NO_PALA:format(i) end
					local cls, tgt, b = tonumber(tk[2]), tk[3], tonumber(tk[4])
					if not (cls and tgt and b) then return nil, L.OVER_SYNTAX:format(i) end
					cur.over[cls] = cur.over[cls] or {}
					cur.over[cls][tgt] = b
				end
			end
		end
	end

	if #data.palas == 0 then return nil, L.NO_PALADINS end
	return data
end

-- ================================================================ checks (hard errors only)
local function checkFormat(data)
	local fmt = tonumber(data.meta.format or "1") or 1
	if fmt > MAX_FORMAT then return L.FMT_UNSUPPORTED:format(fmt, MAX_FORMAT) end
end

local function clientBlessingCount()
	if PallyPower and PallyPower.Spells then
		local n = 0
		for i = 1, 6 do if PallyPower.Spells[i] then n = i end end
		return n
	end
end

local function checkClient(data)
	local n = clientBlessingCount()
	if data.meta.expansion == "bcc" and n and n < 6 then return L.CLIENT_TBC:format(n) end
	if n then
		for _, p in ipairs(data.palas) do
			for c = 1, MAXCLASS do
				if (p.bless[c] or 0) > n then return L.CLIENT_BLESS:format(p.bless[c], p.name) end
			end
			for _, targets in pairs(p.over) do
				for _, b in pairs(targets) do
					if b > n then return L.CLIENT_OVER:format(b) end
				end
			end
		end
	end
end

local function validate(data)
	for _, p in ipairs(data.palas) do
		if type(p.name) ~= "string" or p.name == "" then return L.BAD_NAME end
		if p.aura < 0 or p.aura > 8 then return L.BAD_AURA:format(p.name) end
		for c = 1, MAXCLASS do
			local b = p.bless[c] or 0
			if b < 0 or b > 6 then return L.BAD_BLESS:format(p.name, c) end
		end
		for cls, targets in pairs(p.over) do
			if type(cls) ~= "number" or cls < 1 or cls > MAXCLASS then
				return L.BAD_OVER_CLASS:format(tostring(cls), p.name)
			end
			for tgt, b in pairs(targets) do
				if type(tgt) ~= "string" or b < 0 or b > 6 then
					return L.BAD_OVER:format(tostring(tgt), p.name)
				end
			end
		end
	end
end

-- All hard checks in one call.
local function checkAll(text)
	local ok, data, err = pcall(parseImport, text)
	if not ok then return nil, L.PARSER_ERROR end
	if not data then return nil, tostring(err) end
	err = checkFormat(data) or validate(data) or checkClient(data)
	if err then return nil, err end
	resolveNames(data)
	return data
end

-- ================================================================ apply
local function buildTables(data)
	local A, N, AU = {}, {}, {}
	for _, p in ipairs(data.palas) do
		local key = p.resolved or p.name
		A[key] = {}
		for c = 1, MAXCLASS do
			if (p.bless[c] or 0) > 0 then A[key][c] = p.bless[c] end
		end
		if (p.aura or 0) > 0 then AU[key] = p.aura end
		for cls, targets in pairs(p.over) do
			for tgt, b in pairs(targets) do
				N[key] = N[key] or {}
				N[key][cls] = N[key][cls] or {}
				N[key][cls][tgt] = b
			end
		end
	end
	return A, N, AU
end

local function canControlPallys()
	if not PallyPower then return false end
	if PallyPower.CheckLeader and PallyPower.player and PallyPower:CheckLeader(PallyPower.player) then
		return true
	end
	return PallyPower.opt and PallyPower.opt.freeassign and true or false
end

-- Direct assignment like clicking the grid: sets PallyPower_Assignments /
-- _NormalAssignments / _AuraAssignments and broadcasts them. No preset,
-- PallyPower_SavedPresets is not touched.
-- Returns: ok, mode ("solo"|"raid"|"raid-limited"), err
local function applyData(data)
	if not PallyPower then return false, nil, L.NOT_LOADED end
	if InCombatLockdown() then return false, nil, L.CANT_COMBAT end
	if not data.palas[1].resolved then resolveNames(data) end

	local A, N, AU = buildTables(data)

	PallyPower_Assignments = PallyPower_Assignments or {}
	PallyPower_NormalAssignments = PallyPower_NormalAssignments or {}
	PallyPower_AuraAssignments = PallyPower_AuraAssignments or {}

	local send = IsInGroup() and PallyPower.SendMessage
		and function(msg) PallyPower:SendMessage(msg) end
		or function() end

	for _, p in ipairs(data.palas) do
		local name = p.resolved
		local classes = A[name] or {}

		-- 1) class blessings: full 9-slot row (authoritative)
		PallyPower_Assignments[name] = {}
		local s = ""
		for i = 1, MAXCLASS do
			local v = classes[i] or 0
			if v > 0 then PallyPower_Assignments[name][i] = v end
			s = s .. (v > 0 and tostring(v) or "n")
		end
		send("PASSIGN " .. name .. "@" .. s)

		-- 2) aura
		local aura = AU[name] or 0
		PallyPower_AuraAssignments[name] = (aura > 0) and aura or nil
		send("AASSIGN " .. name .. " " .. aura)

		-- 3) overrides, authoritative: clear this paladin's existing ones, then set new
		local oldN = PallyPower_NormalAssignments[name]
		if oldN then
			for cls, targets in pairs(oldN) do
				for tname in pairs(targets) do
					send("NASSIGN " .. name .. " " .. cls .. " " .. tname .. " 0")
				end
			end
		end
		PallyPower_NormalAssignments[name] = nil

		local newN = N[name]
		if newN then
			PallyPower_NormalAssignments[name] = {}
			for cls, targets in pairs(newN) do
				PallyPower_NormalAssignments[name][cls] = {}
				for tname, value in pairs(targets) do
					PallyPower_NormalAssignments[name][cls][tname] = value
					if PallyPower.SendNormalBlessings and IsInGroup() then
						PallyPower:SendNormalBlessings(name, cls, tname)
					else
						send("NASSIGN " .. name .. " " .. cls .. " " .. tname .. " " .. value)
					end
				end
			end
		end
	end

	if PallyPower.UpdateRoster then PallyPower:UpdateRoster() end
	if PallyPower.UpdateLayout then PallyPower:UpdateLayout() end

	PallyPowerImportDB.last = {
		event = data.meta.event,
		generated = data.meta.generated,
		palas = #data.palas,
		at = date("%Y-%m-%d %H:%M"),
	}

	if not IsInGroup() then return true, "solo" end
	return true, canControlPallys() and "raid" or "raid-limited"
end

-- ================================================================ UI
local frame
local pending
local checkTimer
local mmBtn

local MODE_MSG = { solo = L.MODE_SOLO, raid = L.MODE_RAID, ["raid-limited"] = L.MODE_LIMITED }

local function makeButton(parent, label, w)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 24)
	b:SetText(label)
	return b
end

local function makeEditBox(parent)
	local scroll = CreateFrame("ScrollFrame", "PallyPowerImportScroll", parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 16, -58)
	scroll:SetPoint("BOTTOMRIGHT", -34, 92)
	local edit = CreateFrame("EditBox", "PallyPowerImportEdit", scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(430)
	edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	return edit
end

local function makeStatusLine(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("BOTTOMLEFT", 16, 74)
	fs:SetPoint("BOTTOMRIGHT", -16, 74)
	fs:SetJustifyH("LEFT")
	local function set(msg, kind)
		fs:SetText(msg or "")
		local c = (kind == "err" and { 1, 0.33, 0.33 })
			or (kind == "warn" and { 1, 0.8, 0.2 })
			or (kind == "ok" and { 0.4, 1, 0.6 })
			or { 0.8, 0.8, 0.8 }
		fs:SetTextColor(c[1], c[2], c[3])
	end
	return set
end

local function createUI()
	if frame then return frame end
	frame = CreateFrame("Frame", "PallyPowerImportFrame", UIParent,
		BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(500, 320)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local a, _, rp, x, y = f:GetPoint()
		PallyPowerImportDB.point = { a, rp, x, y }
	end)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.92)
	end
	if PallyPowerImportDB.point then
		local p = PallyPowerImportDB.point
		frame:ClearAllPoints()
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end
	tinsert(UISpecialFrames, "PallyPowerImportFrame")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText(L.TITLE .. "  " .. C_R .. "v" .. VERSION .. C_G)

	local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeX:SetPoint("TOPRIGHT", -4, -4)
	closeX:SetScript("OnClick", function() frame:Hide() end)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -40)
	hint:SetText(L.HINT)

	local edit = makeEditBox(frame)
	local setStatus = makeStatusLine(frame)

	-- minimap checkbox
	local mmCB = CreateFrame("CheckButton", "PallyPowerImportMinimapCB", frame, "UICheckButtonTemplate")
	mmCB:SetPoint("BOTTOMLEFT", 14, 46)
	mmCB:SetSize(22, 22)
	local mmCBText = mmCB.Text or mmCB.text or _G["PallyPowerImportMinimapCBText"]
	if mmCBText then mmCBText:SetText(L.CHECK_MINIMAP) end
	mmCB:SetChecked(not PallyPowerImportDB.minimap.hide)
	mmCB:SetScript("OnClick", function(self)
		local v = self:GetChecked() and true or false
		PallyPowerImportDB.minimap.hide = not v
		if mmBtn then if v then mmBtn:Show() else mmBtn:Hide() end end
	end)

	local importBtn = makeButton(frame, L.BTN_IMPORT, 120)
	importBtn:SetPoint("BOTTOMLEFT", 16, 14)
	local clearBtn = makeButton(frame, L.BTN_CLEAR, 90)
	clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
	local closeBtn = makeButton(frame, L.BTN_CLOSE, 90)
	closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)
	closeBtn:SetScript("OnClick", function() frame:Hide() end)

	local function refreshButtons()
		setEnabled(importBtn, pending ~= nil and not InCombatLockdown())
	end

	local function doCheck()
		pending = nil
		refreshButtons()
		local txt = trim(edit:GetText())
		if txt == "" then setStatus(L.READY); return end
		if InCombatLockdown() then setStatus(L.IN_COMBAT, "err"); return end

		local data, err = checkAll(txt)
		if not data then setStatus(L.ERR_PREFIX .. err, "err"); return end

		pending = data
		refreshButtons()
		local n = #data.palas
		if not IsInGroup() then
			setStatus(L.OK_SOLO:format(n), "warn")
		elseif canControlPallys() then
			setStatus(L.OK_RAID:format(n), "ok")
		else
			setStatus(L.OK_LIMITED:format(n), "warn")
		end
	end

	edit:SetScript("OnTextChanged", function()
		pending = nil
		refreshButtons()
		if checkTimer and checkTimer.Cancel then checkTimer:Cancel() end
		if C_Timer and C_Timer.NewTimer then
			checkTimer = C_Timer.NewTimer(0.3, function() checkTimer = nil; doCheck() end)
		else
			doCheck()
		end
	end)

	local function finishApply()
		local data = pending
		if not data then return end
		setEnabled(importBtn, false)
		setStatus(L.IMPORTING, nil)
		local ok, mode, err = applyData(data)
		if not ok then
			setStatus(L.ERR_PREFIX .. (err or "?"), "err")
			refreshButtons()
			return
		end
		say(("%d paladin(s), %s"):format(#data.palas, MODE_MSG[mode] or mode))
		pending = nil
		edit:SetText("")
		setStatus(L.READY)
		frame:Hide()
	end

	importBtn:SetScript("OnClick", function()
		if pending then finishApply() end
	end)

	clearBtn:SetScript("OnClick", function()
		edit:SetText("")
		pending = nil
		setStatus(L.READY)
		refreshButtons()
	end)

	frame:SetScript("OnShow", function()
		refreshButtons()
		if trim(edit:GetText()) ~= "" then doCheck() end
	end)

	local watch = CreateFrame("Frame")
	watch:RegisterEvent("PLAYER_REGEN_ENABLED")
	watch:RegisterEvent("PLAYER_REGEN_DISABLED")
	watch:SetScript("OnEvent", function() if frame:IsShown() then refreshButtons() end end)

	frame:Hide()
	return frame
end

local function toggleUI()
	local f = createUI()
	if f:IsShown() then f:Hide() else f:Show() end
end

-- ================================================================ minimap
local function positionMinimap()
	if not mmBtn then return end
	local a = math.rad(PallyPowerImportDB.minimap.angle or 220)
	mmBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function createMinimap()
	if mmBtn or not Minimap then return end
	mmBtn = CreateFrame("Button", "PallyPowerImportMinimapButton", Minimap)
	mmBtn:SetSize(31, 31)
	mmBtn:SetFrameStrata("MEDIUM")
	mmBtn:SetFrameLevel(8)
	mmBtn:RegisterForClicks("LeftButtonUp")
	mmBtn:RegisterForDrag("LeftButton")

	local border = mmBtn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	local icon = mmBtn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(19, 19)
	icon:SetTexture("Interface\\Icons\\Spell_Holy_GreaterBlessingofKings")
	icon:SetPoint("CENTER")

	mmBtn:SetScript("OnClick", toggleUI)
	mmBtn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			cx, cy = cx / scale, cy / scale
			PallyPowerImportDB.minimap.angle = math.deg(atan2(cy - my, cx - mx))
			positionMinimap()
		end)
	end)
	mmBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	mmBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L.TITLE)
		GameTooltip:AddLine(L.TIP_CLICK, 1, 1, 1)
		GameTooltip:Show()
	end)
	mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	positionMinimap()
	if PallyPowerImportDB.minimap.hide then mmBtn:Hide() end
end

local function setMinimapShown(show)
	PallyPowerImportDB.minimap.hide = not show
	if mmBtn then if show then mmBtn:Show() else mmBtn:Hide() end end
	local cb = _G["PallyPowerImportMinimapCB"]
	if cb then cb:SetChecked(show) end
end

-- ================================================================ slash
SLASH_PALLYPOWERIMPORT1 = "/ppi"
SLASH_PALLYPOWERIMPORT2 = "/ppimport"
SlashCmdList["PALLYPOWERIMPORT"] = function(msg)
	msg = trim(msg)
	local low = msg:lower()

	if low == "minimap" then
		setMinimapShown(PallyPowerImportDB.minimap.hide)
		say(PallyPowerImportDB.minimap.hide and L.MM_OFF or L.MM_ON)
		return
	end
	if low == "version" then
		say(("v%s  |  PallyPower: %s"):format(
			VERSION,
			(PallyPower and PallyPower.LoadPreset) and L.PP_DETECTED or L.PP_MISSING))
		return
	end

	if msg ~= "" then
		local data, err = checkAll(msg)
		if not data then sayErr(err); return end
		local ok, mode, aerr = applyData(data)
		if not ok then sayErr(aerr or "?"); return end
		say(("%d paladin(s), %s"):format(#data.palas, MODE_MSG[mode] or mode))
		return
	end

	toggleUI()
end

-- ================================================================ init
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	initDB()
	createMinimap()
	if not PallyPower then
		sayErr(L.NO_PP)
	else
		say(("v%s %s"):format(VERSION, L.LOADED))
	end
end)
