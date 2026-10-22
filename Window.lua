-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Fenêtres du compteur : barres, menus, relecture de combat, rapport.

local ADDON, ns = ...
local Z = ns.Z
local UI = Z.UI

local floor, max, min, sort = math.floor, math.max, math.min, table.sort
local Num, Time = Z.Num, Z.Time

local HEADER, FOOTER, REPLAY = 22, 15, 18
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_COORDS = CLASS_ICON_TCOORDS or {
	WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
	DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
	PALADIN = { 0, 0.25, 0.5, 0.75 }, DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
}
Z.CLASS_ICONS, Z.CLASS_COORDS = CLASS_ICONS, CLASS_COORDS

-- Modes dont la somme a un sens à afficher en pied de fenêtre.
local SUM_LABEL = {
	damage = "Total", taken = "Total", heal = "Total", healonly = "Total", absorb = "Total", over = "Total",
	ff = "Total", mitig = "Total", takenspell = "Total", healin = "Total", foedmg = "Total", foeheal = "Total",
	enemies = "Total", dps = "Groupe", live = "Groupe", hps = "Groupe",
}

local Win = {}
Win.__index = Win
Z.windows = {}

local function ByValue(a, b) return a.value > b.value end

-- Couleur du rang pour le podium : or, argent, bronze.
local MEDALS = { "|cffffd24a", "|cffcfd6e0", "|cffd9925a" }

-- Texte de droite d'une ligne, selon le dernier rafraîchissement.
function Win:RowText(row)
	if self.ctxReplay then
		return Num(row.value) .. " (" .. Num(row.value / self.ctxDur) .. ")"
	end
	return self.ctxMode.text(row.value, row.p, self.ctxDur, self.ctxSum)
end

-------------------------------------------------------------------------------
-- Menus
-------------------------------------------------------------------------------

function Win:ModeMenu(anchor)
	local items, group = {}, nil
	local expert = Z.db.expert
	if not expert then items[1] = { text = "Que voulez-vous mesurer ?", title = true } end
	for _, m in ipairs(Z.modes) do
		-- En affichage simple, seuls les modes essentiels sont proposés
		-- (et celui en cours, pour ne jamais perdre l'utilisateur).
		if expert or m.basic or self.cfg.mode == m.key then
			if expert and m.group ~= group then
				group = m.group
				items[#items + 1] = { text = group, title = true }
			end
			items[#items + 1] = {
				text = m.name, checked = self.cfg.mode == m.key, tip = m.desc, note = m.note,
				func = function() self:SetMode(m.key) end,
			}
		end
	end
	items[#items + 1] = { text = "Affichage", title = true }
	items[#items + 1] = {
		text = expert and "Revenir aux modes essentiels" or "Afficher tous les modes (expert)",
		tip = expert and "N'affiche que les mesures les plus utiles pour débuter."
			or "Ajoute les mesures avancées : atténuation, évitement, absorptions, dégâts subis par sort, menace...",
		func = function()
			Z.db.expert = not Z.db.expert
			Z:Fire("SETTINGS")
		end,
	}
	items[#items + 1] = { text = "Nouvelle fenêtre", tip = "Par exemple les dégâts dans une fenêtre et les soins dans une autre.", func = function() Z:NewWindow() end }
	if #Z.windows > 1 then
		items[#items + 1] = { text = "Fermer cette fenêtre", color = { 1, 0.45, 0.4 }, func = function() Z:CloseWindow(self) end }
	end
	UI.ShowMenu(anchor, items)
end

function Win:SegmentMenu(anchor)
	local shown = Z:GetSegment(self.segRef)
	local items = {
		{ text = "Segment affiché", title = true },
		{ text = "Combat actuel", checked = self.segRef == "current", func = function() self:SetSegment("current") end },
		{ text = "Total", checked = self.segRef == "total", func = function() self:SetSegment("total") end },
	}
	local segs = Z.char.segments
	if #segs > 0 then items[#items + 1] = { text = "Combats enregistrés", title = true } end
	for i = 1, #segs do
		local seg = segs[i]
		items[#items + 1] = {
			text = ("%d. %s (%s)%s"):format(i, Z:SegName(seg), Time(Z:SegDuration(seg)), seg.record and " - record" or ""),
			checked = self.segRef == seg or (self.segRef ~= "total" and self.segRef ~= "current" and shown == seg),
			color = seg.boss and { 1, 0.82, 0.3 } or nil,
			func = function() self:SetSegment(seg) end,
		}
	end
	UI.ShowMenu(anchor, items)
end

function Win:SetMode(key)
	self.cfg.mode = key
	if self.replayT and not Z.modeByKey[key].tl then self:StopReplay() end
	self.list.offset = 0
	self:Refresh()
end

function Win:SetSegment(ref)
	self.segRef = ref
	self:StopReplay()
	self.list.offset = 0
	self:Refresh()
end

-------------------------------------------------------------------------------
-- Relecture d'un combat
-------------------------------------------------------------------------------

function Win:StartReplay()
	local seg = Z:GetSegment(self.segRef)
	if not seg or seg == Z.char.total then
		Z:Print("choisissez un combat enregistré pour le rejouer (icône horloge).")
		return
	end
	if seg.active then
		Z:Print("la relecture est disponible une fois le combat terminé.")
		return
	end
	local mode = Z.modeByKey[self.cfg.mode]
	if not (mode and mode.tl) then self.cfg.mode = "damage" end
	self.segRef = seg
	self.replayT = 0
	self.replayDur = Z:SegDuration(seg)
	self.playing = true
	UI.SetIcon(self.playBtn, "pause")
	self.strip:Show()
	self:Layout()
	self:Refresh()
end

function Win:StopReplay()
	if not self.replayT then return end
	self.replayT, self.playing, self.dragging = nil, nil, nil
	self.strip:Hide()
	self:Layout()
	self.dirty = true
end

function Win:ReplayStep(elapsed)
	local dur = self.replayDur or 1
	if self.dragging then
		local x = GetCursorPosition() / self.track:GetEffectiveScale()
		local left = self.track:GetLeft() or 0
		local w = self.trackW or 1
		self.replayT = max(0, min(1, (x - left) / w)) * dur
	elseif self.playing then
		-- Un combat entier défile en une douzaine de secondes.
		self.replayT = self.replayT + elapsed * max(1, dur / 12)
		if self.replayT >= dur then
			self.replayT = dur
			self.playing = nil
			UI.SetIcon(self.playBtn, "play")
		end
	end
	self.replayAcc = (self.replayAcc or 0) + elapsed
	if self.replayAcc >= 0.05 then
		self.replayAcc = 0
		self:Refresh()
	end
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

function Win:SavePosition()
	local f = self.f
	local cfg = self.cfg
	cfg.x, cfg.y = f:GetLeft(), f:GetTop()
	cfg.w, cfg.h = f:GetWidth(), f:GetHeight()
end

function Win:Layout(w, h)
	local f = self.f
	w = w or self.cfg.w
	h = h or self.cfg.h
	self.cfg.w, self.cfg.h = w, h
	local footer = Z.db.footer and FOOTER or 0
	local strip = self.replayT and REPLAY or 0
	self.list.f:ClearAllPoints()
	self.list.f:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER - 1)
	self.list:SetSize(w, h - HEADER - 1 - footer - strip)
	self.strip:ClearAllPoints()
	self.strip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, footer)
	self.strip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, footer)
	self.trackW = max(10, w - 78)
	self.track:SetWidth(self.trackW)
	if footer > 0 then self.foot:Show() else self.foot:Hide() end
	self.footLeft:SetWidth(max(10, w * 0.55))
	self.dirty = true
end

function Win:Paint()
	local db = Z.db
	local f = self.f
	local r, g, b = UI.Accent()
	f:SetScale(db.scale)
	self.bg:SetTexture(db.bg[1], db.bg[2], db.bg[3], db.bgAlpha)
	self.head:SetTexture(db.header[1], db.header[2], db.header[3], min(1, db.bgAlpha + 0.1))
	self.line:SetGradientAlpha("HORIZONTAL", r, g, b, 1, r, g, b, 0.1)
	for i = 1, 4 do self.border[i]:SetTexture(0, 0, 0, min(1, db.bgAlpha + 0.1)) end
	UI.SetFont(self.title, 12)
	self.title:SetTextColor(1, 1, 1)
	UI.SetFont(self.footLeft, 10)
	UI.SetFont(self.footRight, 10)
	UI.SetFont(self.empty, 11)
	UI.SetFont(self.timeText, 10)
	self.knob:SetVertexColor(r, g, b)
	self.progress:SetVertexColor(r, g, b, 0.8)
	if db.locked then self.grip:Hide() else self.grip:Show() end
	self.tMode, self.fName = nil, nil
	self.list.styled = self.list.styled + 1
	self:Layout()
	self:Refresh()
end

local function NewWindow(id, cfg)
	local self = setmetatable({ id = id, cfg = cfg, rows = {}, count = 0, segRef = "current" }, Win)
	local f = CreateFrame("Frame", "ZenithWindow" .. id, UIParent)
	self.f = f
	f.win = self
	cfg.w, cfg.h = cfg.w or 260, cfg.h or 190
	f:SetWidth(cfg.w)
	f:SetHeight(cfg.h)
	if cfg.x and cfg.y then
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cfg.x, cfg.y)
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -60 - (id - 1) * 30, -120 + (id - 1) * 30)
	end
	f:SetFrameStrata("LOW")
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetMinResize(170, 62)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame)
		if not Z.db.locked then frame:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		frame:SetUserPlaced(false)
		self:SavePosition()
	end)
	f:SetScript("OnSizeChanged", function(_, w, h)
		if self.sizing then
			self:Layout(w, h)
			self:Refresh()
		end
	end)

	self.bg = UI.Solid(f, "BACKGROUND", 0, 0, 0, 1)
	self.bg:SetAllPoints(f)
	self.border = UI.Border(f, 0, 0, 0, 1)
	UI.Shadow(f, 6, 0.45)
	self.head = UI.Solid(f, "BORDER", 0, 0, 0, 1)
	self.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	self.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	self.head:SetHeight(HEADER)
	self.line = f:CreateTexture(nil, "ARTWORK")
	self.line:SetTexture(WHITE)
	self.line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	self.line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	self.line:SetHeight(2)

	-- Boutons de l'en-tête, de droite à gauche
	local function Icon(icon, tip, tipText, x, fn)
		local b = UI.IconButton(f, icon, 13, tip, fn)
		b.tipText = tipText
		b:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, -6)
		return b
	end
	Icon("gear", "Options", "Ouvrir le panneau d'options.", -6, function() Z:ToggleOptions() end)
	Icon("report", "Rapport", "Envoyer le classement dans une discussion.", -24, function() Z:OpenReport(self) end)
	Icon("reset", "Réinitialiser", "Efface toutes les données.\nMaj-clic : sans confirmation.", -42, function()
		if IsShiftKeyDown() then Z:ResetData() else StaticPopup_Show("ZENITH_RESET_ALL") end
	end)
	Icon("clock", "Segments", "Choisir le combat affiché.", -60, function(b) self:SegmentMenu(b) end)
	self.playBtn = Icon("play", "Relecture", "Rejoue le combat affiché : le classement évolue seconde par seconde.\nClic droit : quitter la relecture.", -78, function(_, button)
		if button == "RightButton" then
			self:StopReplay()
		elseif not self.replayT then
			self:StartReplay()
		else
			if self.replayT >= (self.replayDur or 0) then self.replayT = 0 end
			self.playing = not self.playing
			UI.SetIcon(self.playBtn, self.playing and "pause" or "play")
		end
	end)

	-- Titre : choix du mode
	local tb = CreateFrame("Button", nil, f)
	tb:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
	tb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -96, -HEADER)
	tb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	tb:RegisterForDrag("LeftButton")
	tb:SetScript("OnDragStart", function()
		if not Z.db.locked then f:StartMoving() end
	end)
	tb:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		f:SetUserPlaced(false)
		self:SavePosition()
	end)
	tb:SetScript("OnClick", function(b, button)
		if button == "RightButton" then self:SegmentMenu(b) else self:ModeMenu(b) end
	end)
	tb:SetScript("OnEnter", function(b)
		local mode = Z.modeByKey[self.cfg.mode]
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(mode and mode.name or "Zénith", UI.Accent())
		if mode and mode.desc then GameTooltip:AddLine(mode.desc, 0.9, 0.9, 0.9, 1) end
		if mode and mode.note then GameTooltip:AddLine(mode.note, 0.55, 0.75, 0.6, 1) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Clic : choisir une autre mesure", 0.6, 0.65, 0.72)
		GameTooltip:AddLine("Clic droit : choisir un autre combat", 0.6, 0.65, 0.72)
		GameTooltip:AddLine("Glisser : déplacer la fenêtre", 0.6, 0.65, 0.72)
		GameTooltip:Show()
	end)
	tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.title = UI.Text(tb, 12)
	self.title:SetPoint("LEFT", tb, "LEFT", 2, 0)
	self.title:SetPoint("RIGHT", tb, "RIGHT", 0, 0)
	self.title:SetJustifyH("LEFT")
	self.title:SetHeight(14)

	-- Liste
	self.list = UI.BarList(f)
	self.list.onScroll = function() self:Refresh() end
	self.list.onClick = function(d, button)
		if button == "RightButton" then
			self:ModeMenu(tb)
		elseif d.p and d.guid then
			Z:ShowDetail(Z:GetSegment(self.segRef), d.guid, Z.modeByKey[self.cfg.mode].tab)
		end
	end
	self.list.onEnter = function(d, row)
		local seg = Z:GetSegment(self.segRef)
		if not seg then return end
		GameTooltip:SetOwner(row, "ANCHOR_LEFT")
		GameTooltip:ClearLines()
		Z:RowTooltip(Z.modeByKey[self.cfg.mode], seg, d, GameTooltip)
		GameTooltip:Show()
	end
	self.empty = UI.Text(self.list.f, 11)
	self.empty:SetPoint("CENTER", self.list.f, "CENTER", 0, 0)
	self.empty:SetTextColor(0.5, 0.55, 0.62)
	self.empty:SetJustifyH("CENTER")

	-- Bandeau de relecture
	local strip = CreateFrame("Frame", nil, f)
	self.strip = strip
	strip:SetHeight(REPLAY)
	strip.bg = UI.Solid(strip, "BACKGROUND", 0, 0, 0, 0.35)
	strip.bg:SetAllPoints(strip)
	local track = CreateFrame("Button", nil, strip)
	self.track = track
	track:SetHeight(REPLAY)
	track:SetPoint("LEFT", strip, "LEFT", 8, 0)
	local rail = UI.Solid(track, "BORDER", 1, 1, 1, 0.15)
	rail:SetPoint("LEFT", track, "LEFT", 0, 0)
	rail:SetPoint("RIGHT", track, "RIGHT", 0, 0)
	rail:SetHeight(3)
	self.progress = UI.Solid(track, "ARTWORK", 1, 1, 1, 1)
	self.progress:SetPoint("LEFT", track, "LEFT", 0, 0)
	self.progress:SetHeight(3)
	self.knob = UI.Solid(track, "OVERLAY", 1, 1, 1, 1)
	self.knob:SetWidth(4)
	self.knob:SetHeight(11)
	self.knob:SetPoint("CENTER", self.progress, "RIGHT", 0, 0)
	track:SetScript("OnMouseDown", function()
		self.dragging = true
		self.playing = nil
		UI.SetIcon(self.playBtn, "play")
	end)
	track:SetScript("OnMouseUp", function() self.dragging = nil end)
	self.timeText = UI.Text(strip, 10)
	self.timeText:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
	strip:Hide()

	-- Pied de fenêtre
	local foot = CreateFrame("Frame", nil, f)
	self.foot = foot
	foot:SetHeight(FOOTER)
	foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	foot.bg = UI.Solid(foot, "BACKGROUND", 0, 0, 0, 0.3)
	foot.bg:SetAllPoints(foot)
	self.footLeft = UI.Text(foot, 10)
	self.footLeft:SetPoint("LEFT", foot, "LEFT", 5, 0)
	self.footLeft:SetJustifyH("LEFT")
	self.footLeft:SetHeight(12)
	self.footLeft:SetTextColor(0.62, 0.67, 0.74)
	self.footRight = UI.Text(foot, 10)
	self.footRight:SetPoint("RIGHT", foot, "RIGHT", -14, 0)
	self.footRight:SetJustifyH("RIGHT")
	self.footRight:SetTextColor(0.62, 0.67, 0.74)

	-- Poignée de redimensionnement
	local grip = CreateFrame("Button", nil, f)
	self.grip = grip
	grip:SetWidth(12)
	grip:SetHeight(12)
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	grip:SetFrameLevel(f:GetFrameLevel() + 5)
	local gt = grip:CreateTexture(nil, "OVERLAY")
	gt:SetAllPoints(grip)
	gt:SetTexture(Z.MEDIA .. "grip.tga")
	gt:SetVertexColor(1, 1, 1, 0.35)
	grip:SetScript("OnMouseDown", function()
		if Z.db.locked then return end
		self.sizing = true
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		f:SetUserPlaced(false)
		self.sizing = nil
		self:SavePosition()
		self:Layout()
		self:Refresh()
	end)

	self:Paint()
	return self
end

-------------------------------------------------------------------------------
-- Rafraîchissement
-------------------------------------------------------------------------------

function Win:Refresh()
	self.dirty = nil
	local db = Z.db
	local mode = Z.modeByKey[self.cfg.mode]
	if not mode then
		mode = Z.modes[1]
		self.cfg.mode = mode.key
	end
	local seg = Z:GetSegment(self.segRef)
	if self.replayT and (not seg or seg.active or not mode.tl) then
		self.replayT, self.playing, self.dragging = nil, nil, nil
		self.strip:Hide()
		self:Layout()
		self.dirty = true
		return
	end
	local rows = self.rows
	local n, sum, dur
	local replay = self.replayT
	if replay then
		n, sum = Z:CollectReplay(seg, mode.tl, replay, rows)
		dur = max(replay, 1)
	else
		n, sum = Z:Collect(mode, seg, rows)
		dur = seg and Z:SegDuration(seg) or 1
	end
	sort(rows, ByValue)
	self.count = n

	local top = mode.fixedMax or (n > 0 and rows[1].value) or 1
	if top <= 0 then top = 1 end
	local ar, ag, ab = UI.Accent()
	local me = Z.playerGUID
	-- Contexte gardé pour produire un texte de ligne à la demande (rapport).
	self.ctxMode, self.ctxDur, self.ctxSum, self.ctxReplay = mode, dur, sum, replay
	-- Seules les lignes visibles reçoivent leur texte : inutile de fabriquer
	-- des chaînes pour vingt-cinq joueurs quand huit barres sont affichées.
	local first, last = self.list:Range(n)
	for i = first, last do
		local row = rows[i]
		row.guid = row.id
		row.frac = row.value / top
		row.mark = row.id == me or nil
		if db.barColor == "accent" then
			row.r, row.g, row.b = ar, ag, ab
		elseif db.barColor == "rang" then
			local k = n > 1 and (i - 1) / (n - 1) or 0
			row.r, row.g, row.b = ar + (0.35 - ar) * k, ag + (0.38 - ag) * k, ab + (0.45 - ab) * k
		elseif row.class then
			row.r, row.g, row.b = Z.ClassColor(row.class)
		elseif mode.color then
			row.r, row.g, row.b = mode.color[1], mode.color[2], mode.color[3]
		else
			row.r, row.g, row.b = Z.ClassColor(nil)
		end
		do
			local name = row.name or "?"
			if row.mark then name = "|cffffffff" .. name .. "|r" end
			if db.showRank then
				row.label = (MEDALS[i] or "|cff8d97a6") .. i .. ".|r " .. name
			else
				row.label = name
			end
			row.text = self:RowText(row)
			local coords = row.class and CLASS_COORDS[row.class]
			if coords then
				row.icon, row.coords = CLASS_ICONS, coords
				-- Icône de spécialisation ou de rôle quand elle est connue.
				if db.iconMode ~= "classe" and row.p then
					local _, _, sicon, role = Z:SpecInfo(row.id, row.class, row.p)
					if db.iconMode == "role" then
						if role then row.icon, row.coords = Z.ROLE_TEX, Z.ROLE_COORDS[role] end
					elseif sicon then
						row.icon, row.coords = sicon, nil
					end
				end
			elseif type(row.spell) == "number" and row.spell >= 1 then
				local _, _, tex = GetSpellInfo(row.spell)
				row.icon, row.coords = tex, nil
			else
				row.icon, row.coords = nil, nil
			end
		end
	end
	self.list:SetData(rows, n)

	-- Titre (mesure + combat affiché) et message d'attente
	local where = (self.segRef == "total" and "Total") or (seg and seg.active and "Combat en cours")
		or (self.segRef == "current" and "Dernier combat") or (seg and Z:SegName(seg)) or ""
	if mode.threat then where = "" end
	if self.tMode ~= mode or self.tWhere ~= where then
		self.tMode, self.tWhere = mode, where
		self.title:SetText(mode.name .. (where ~= "" and ("  |cff7f8a9a" .. where .. "|r") or ""))
	end
	if n == 0 then
		if mode.threat then
			self.empty:SetText("Ciblez un ennemi en combat\npour voir qui a sa menace.")
		elseif mode.live and not (seg and seg.active) then
			self.empty:SetText("Cette mesure n'existe\nque pendant un combat.")
		elseif not seg then
			self.empty:SetText("Attaquez un ennemi :\nles barres apparaîtront ici.")
		else
			self.empty:SetText("Rien à afficher pour cette mesure\nsur ce combat.")
		end
		self.empty:Show()
	else
		self.empty:Hide()
	end

	-- Pied de fenêtre
	if db.footer then
		if mode.threat then
			self.fName, self.fSecs = nil, nil
			self.footLeft:SetText(UnitName("target") or "Aucune cible")
			self.footRight:SetText("")
		else
			local name = seg and Z:SegName(seg) or "Aucun combat"
			local secs = seg and floor(Z:SegDuration(seg) + 0.5) or -1
			if self.fName ~= name or self.fSecs ~= secs then
				self.fName, self.fSecs = name, secs
				self.footLeft:SetText(seg and (name .. "  " .. Time(secs)) or name)
			end
			local right = ""
			local delta = seg and seg.active and (mode.key == "damage" or mode.key == "dps") and Z:GetRecordDelta()
			if delta then
				right = "Record : " .. (delta >= 0 and "|cff55e07a+" or "|cffff6b5e-") .. Num(math.abs(delta)) .. "|r"
			elseif SUM_LABEL[mode.key] and n > 0 then
				right = SUM_LABEL[mode.key] .. " : " .. Num(sum)
			end
			self.footRight:SetText(right)
		end
	end

	if replay then
		local frac = replay / (self.replayDur or 1)
		self.progress:SetWidth(max(1, frac * (self.trackW or 1)))
		self.timeText:SetText(Time(replay) .. " / " .. Time(self.replayDur))
	end
end

-------------------------------------------------------------------------------
-- Gestion des fenêtres
-------------------------------------------------------------------------------

function Z:UpdateVisibility()
	local db = Z.db
	for _, w in ipairs(Z.windows) do
		local show = not w.cfg.hidden
		if show and db.hideOOC and not Z.current then show = false end
		if show and db.hideSolo and not Z:IsGrouped() then show = false end
		local was = w.visible
		w.visible = show
		if show then
			w.f:Show()
			if not was then w.dirty = true end
		else
			w.f:Hide()
		end
	end
end

function Z:ToggleWindows(force)
	local anyShown = false
	for _, w in ipairs(Z.windows) do
		if not w.cfg.hidden then anyShown = true end
	end
	local hide = anyShown
	if force ~= nil then hide = not force end
	for _, w in ipairs(Z.windows) do w.cfg.hidden = hide or nil end
	Z:UpdateVisibility()
end

function Z:NewWindow()
	if #Z.windows >= 5 then
		Z:Print("cinq fenêtres au maximum.")
		return
	end
	local cfg = { mode = (#Z.windows == 1) and "heal" or "damage", w = 260, h = 190 }
	Z.db.windows[#Z.db.windows + 1] = cfg
	-- Les cadres ne peuvent pas être détruits : un ancien cadre fermé est réutilisé.
	local id = #Z.windows + 1
	local old = _G["ZenithWindow" .. id]
	local w
	if old and old.win then
		w = old.win
		w.cfg, w.segRef = cfg, "current"
		w.list.offset = 0
		w.f:SetWidth(cfg.w)
		w.f:SetHeight(cfg.h)
		w.f:ClearAllPoints()
		w.f:SetPoint("RIGHT", UIParent, "RIGHT", -60 - (id - 1) * 30, -120 + (id - 1) * 30)
		w:Paint()
	else
		w = NewWindow(id, cfg)
	end
	Z.windows[id] = w
	Z:UpdateVisibility()
	return w
end

function Z:CloseWindow(win)
	if #Z.windows <= 1 then return end
	-- Seule la dernière fenêtre est libérée : les suivantes décalent leur réglage.
	local idx
	for i, w in ipairs(Z.windows) do
		if w == win then idx = i end
	end
	if not idx then return end
	local refs = {}
	for i, w in ipairs(Z.windows) do
		w:StopReplay()
		if i ~= idx then refs[#refs + 1] = w.segRef end
	end
	table.remove(Z.db.windows, idx)
	local last = table.remove(Z.windows)
	last.f:Hide()
	last.visible = nil
	for i, w in ipairs(Z.windows) do
		w.cfg = Z.db.windows[i]
		w.segRef = refs[i] or "current"
		w.list.offset = 0
		w.f:SetWidth(w.cfg.w)
		w.f:SetHeight(w.cfg.h)
		if w.cfg.x and w.cfg.y then
			w.f:ClearAllPoints()
			w.f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", w.cfg.x, w.cfg.y)
		end
		w:Paint()
	end
	Z:UpdateVisibility()
end

StaticPopupDialogs["ZENITH_RESET_ALL"] = {
	text = "Zénith : effacer toutes les données de combat ?",
	button1 = "Effacer",
	button2 = "Annuler",
	OnAccept = function() Z:ResetData() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function Z:InitWindows()
	if #Z.db.windows == 0 then Z.db.windows[1] = { mode = "damage", w = 260, h = 190 } end
	for i, cfg in ipairs(Z.db.windows) do
		cfg.hidden = cfg.hidden or nil
		Z.windows[i] = NewWindow(i, cfg)
	end

	local function Dirty()
		for _, w in ipairs(Z.windows) do w.dirty = true end
	end
	Z:On("SETTINGS", function()
		for _, w in ipairs(Z.windows) do w:Paint() end
		Z:UpdateVisibility()
	end)
	Z:On("COMBAT_START", function()
		for _, w in ipairs(Z.windows) do
			if w.segRef == "current" then w:StopReplay() end
		end
		Z:UpdateVisibility()
	end)
	Z:On("COMBAT_END", function()
		Dirty()
		Z:UpdateVisibility()
	end)
	Z:On("SPEC", Dirty)
	Z:On("SYNC", Dirty)
	Z:On("RESET", function()
		for _, w in ipairs(Z.windows) do
			w:StopReplay()
			if type(w.segRef) == "table" then w.segRef = "current" end
			w.dirty = true
		end
	end)

	local driver = CreateFrame("Frame", nil, UIParent)
	local acc, vis = 0, 0
	driver:SetScript("OnUpdate", function(_, elapsed)
		for i = 1, #Z.windows do
			local w = Z.windows[i]
			if w.replayT and (w.playing or w.dragging) then w:ReplayStep(elapsed) end
		end
		acc = acc + elapsed
		if acc < Z.db.updateRate then return end
		acc = 0
		vis = vis + 1
		if vis >= 8 and Z.db.hideSolo then
			vis = 0
			Z:UpdateVisibility()
		end
		local live = Z.current ~= nil
		for i = 1, #Z.windows do
			local w = Z.windows[i]
			if w.visible and not w.replayT then
				local mode = Z.modeByKey[w.cfg.mode]
				-- Un combat déjà terminé ne change plus : inutile de le recalculer en direct.
				local ref = w.segRef
				local moving = live and (ref == "current" or ref == "total" or ref == Z.current)
				if w.dirty or moving or (mode and mode.threat) then w:Refresh() end
			end
		end
	end)
	Z:UpdateVisibility()
end

-------------------------------------------------------------------------------
-- Rapport dans une discussion
-------------------------------------------------------------------------------

local CHANNELS = {
	{ key = "MOI", name = "Moi uniquement" },
	{ key = "DIRE", name = "Dire", chat = "SAY" },
	{ key = "GROUPE", name = "Groupe", chat = "PARTY" },
	{ key = "RAID", name = "Raid", chat = "RAID" },
	{ key = "GUILDE", name = "Guilde", chat = "GUILD" },
	{ key = "OFFICIER", name = "Officiers", chat = "OFFICER" },
	{ key = "CHUCHOTER", name = "Chuchoter à la cible", chat = "WHISPER" },
}

local function Strip(s)
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Z:Report(win, channelKey, lines)
	local ch = UI.Lookup(CHANNELS, channelKey)
	local mode = Z.modeByKey[win.cfg.mode]
	local seg = Z:GetSegment(win.segRef)
	if win.count == 0 or not win.ctxMode then
		Z:Print("rien à rapporter pour le moment.")
		return
	end
	local target
	if ch.chat == "WHISPER" then
		target = UnitIsPlayer("target") and UnitName("target")
		if not target then
			Z:Print("ciblez un joueur pour lui chuchoter le rapport.")
			return
		end
	elseif ch.chat == "RAID" and GetNumRaidMembers() == 0 then
		Z:Print("vous n'êtes pas en raid.")
		return
	elseif ch.chat == "PARTY" and GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
		Z:Print("vous n'êtes pas en groupe.")
		return
	end
	local function Send(text)
		if ch.chat then
			-- Coupe à 250 octets sans laisser un caractère accentué à moitié (UTF-8 invalide).
			if #text > 250 then text = text:sub(1, 250):gsub("[\192-\255][\128-\191]*$", "") end
			SendChatMessage(text, ch.chat, nil, target)
		else
			Z:Print(text)
		end
	end
	local head = "Zénith - " .. mode.name
	if seg and not mode.threat then head = head .. " - " .. Z:SegName(seg) .. " (" .. Time(Z:SegDuration(seg)) .. ")" end
	Send(head)
	for i = 1, min(lines, win.count) do
		local row = win.rows[i]
		Send(("%d. %s - %s"):format(i, row.name or "?", Strip(win:RowText(row))))
	end
end

local report

function Z:OpenReport(win)
	if not report then
		report = UI.Panel("ZenithReport", 300, 170, "Rapport")
		local f = report
		local l1 = UI.Text(f, 11)
		l1:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -46)
		l1:SetText("Destination")
		f.channel = UI.Button(f, "", 150, 22, function(b)
			local items = {}
			for _, c in ipairs(CHANNELS) do
				items[#items + 1] = { text = c.name, checked = Z.db.reportChannel == c.key, func = function()
					Z.db.reportChannel = c.key
					f:Update()
				end }
			end
			UI.ShowMenu(b, items)
		end)
		f.channel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -41)
		local l2 = UI.Text(f, 11)
		l2:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -80)
		l2:SetText("Nombre de lignes")
		f.minus = UI.Button(f, "-", 24, 22, function()
			Z.db.reportLines = max(1, Z.db.reportLines - 1)
			f:Update()
		end)
		f.plus = UI.Button(f, "+", 24, 22, function()
			Z.db.reportLines = min(25, Z.db.reportLines + 1)
			f:Update()
		end)
		f.plus:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -75)
		f.count = UI.Text(f, 12)
		f.count:SetPoint("RIGHT", f.plus, "LEFT", -14, 0)
		f.minus:SetPoint("RIGHT", f.count, "LEFT", -14, 0)
		f.send = UI.Button(f, "Envoyer", 272, 26, function()
			if f.win then Z:Report(f.win, Z.db.reportChannel, Z.db.reportLines) end
			f:Hide()
		end)
		f.send:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
		function f:Update()
			self:Paint()
			self.channel.label:SetText(UI.Lookup(CHANNELS, Z.db.reportChannel).name)
			self.count:SetText(("%d"):format(Z.db.reportLines))
			if self.win then self.sub:SetText(Z.modeByKey[self.win.cfg.mode].name) end
		end
	end
	if report:IsShown() and report.win == win then
		report:Hide()
		return
	end
	report.win = win
	report:Update()
	report:Show()
end

-------------------------------------------------------------------------------
-- Résumé de fin de combat
-------------------------------------------------------------------------------

function Z:InitToast()
	local t = CreateFrame("Frame", "ZenithToast", UIParent)
	t:SetWidth(270)
	t:SetHeight(44)
	t:SetFrameStrata("MEDIUM")
	t.bg = UI.Solid(t, "BACKGROUND", 0, 0, 0, 1)
	t.bg:SetAllPoints(t)
	UI.Border(t, 0, 0, 0, 0.9)
	UI.Shadow(t, 6, 0.45)
	t.line = t:CreateTexture(nil, "ARTWORK")
	t.line:SetTexture(WHITE)
	t.line:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
	t.line:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
	t.line:SetWidth(3)
	t.head = UI.Text(t, 12)
	t.head:SetPoint("TOPLEFT", t, "TOPLEFT", 12, -7)
	t.body = UI.Text(t, 11)
	t.body:SetPoint("TOPLEFT", t, "TOPLEFT", 12, -24)
	t.body:SetTextColor(0.8, 0.84, 0.9)
	t:Hide()
	local life = 0
	t:SetScript("OnUpdate", function(self, elapsed)
		life = life - elapsed
		if life <= 0 then
			self:Hide()
		elseif life < 1 then
			self:SetAlpha(life)
		end
	end)

	Z:On("COMBAT_END", function(seg, keep)
		if not keep or not Z.db.toast then return end
		local p = Z.playerGUID and seg.players[Z.playerGUID]
		if not p then return end
		local healer = (p.heal + p.absorb) > p.dmg
		local mine = healer and (p.heal + p.absorb) or p.dmg
		if mine <= 0 then return end
		local rank, count = 1, 0
		for _, o in pairs(seg.players) do
			local v = healer and (o.heal + o.absorb) or o.dmg
			if v > 0 then
				count = count + 1
				if v > mine then rank = rank + 1 end
			end
		end
		local db = Z.db
		t.bg:SetTexture(db.bg[1], db.bg[2], db.bg[3], 0.95)
		t.line:SetVertexColor(UI.Accent())
		UI.SetFont(t.head, 12)
		UI.SetFont(t.body, 11)
		t.head:SetText(("Combat terminé : %s (%s)"):format(seg.name or "Combat", Time(seg.dur)))
		local place = count > 1 and (("%s sur %d"):format(rank == 1 and "1er" or (rank .. "e"), count) .. "  -  ") or ""
		t.body:SetText(("Vous : %s%s %s%s"):format(place, Num(mine / seg.dur), healer and "SPS" or "DPS",
			seg.record and "  -  |cffffd24arecord personnel !|r" or ""))
		t:ClearAllPoints()
		local w = Z.windows[1]
		if w and w.visible then
			t:SetPoint("BOTTOMLEFT", w.f, "TOPLEFT", 0, 10)
		else
			t:SetPoint("TOP", UIParent, "TOP", 0, -140)
		end
		life = 8
		t:SetAlpha(1)
		t:Show()
	end)
end

-------------------------------------------------------------------------------
-- Présentation pour débuter
-------------------------------------------------------------------------------

local welcome
local STEPS = {
	{ "À quoi sert Zénith ?", "Il mesure ce que chaque joueur fait en combat : les dégâts infligés, les soins, les dégâts reçus et les morts. Rien à régler : la fenêtre se remplit toute seule dès que vous attaquez." },
	{ "Lire la fenêtre", "Chaque barre est un joueur. La plus longue est en tête. Votre barre porte un trait de couleur à gauche. À droite, le total, puis la valeur par seconde et la part du groupe." },
	{ "Changer de mesure", "Cliquez sur le titre de la fenêtre pour choisir quoi mesurer. Survolez une mesure : une phrase explique à quoi elle sert et si le chiffre est exact ou estimé." },
	{ "Comprendre un combat", "Cliquez sur une barre : l'onglet Analyse explique en phrases simples ce qui s'est bien ou mal passé. L'icône de lecture rejoue le combat seconde par seconde." },
	{ "Deux mots à connaître", "DPS : dégâts par seconde.  SPS : soins par seconde. Ce sont des vitesses, pratiques pour comparer deux combats de durées différentes." },
}

function Z:ShowWelcome()
	if not welcome then
		welcome = UI.Panel("ZenithWelcome", 460, 446, "Bienvenue dans Zénith")
		local y = 46
		welcome.texts = {}
		for i, step in ipairs(STEPS) do
			local num = UI.Text(welcome, 13)
			num:SetPoint("TOPLEFT", welcome, "TOPLEFT", 16, -y)
			num:SetText(i .. ".")
			local head = UI.Text(welcome, 13)
			head:SetPoint("TOPLEFT", welcome, "TOPLEFT", 36, -y)
			head:SetText(step[1])
			local body = UI.Text(welcome, 11)
			body:SetPoint("TOPLEFT", welcome, "TOPLEFT", 36, -y - 17)
			body:SetTextColor(0.8, 0.84, 0.9)
			local h = UI.SetBlock(body, step[2], 408, 11)
			welcome.texts[i] = { num, head }
			y = y + 17 + h + 12
		end
		local go = UI.Button(welcome, "C'est parti", 200, 26, function() welcome:Hide() end)
		go:SetPoint("BOTTOMLEFT", welcome, "BOTTOMLEFT", 16, 14)
		local opt = UI.Button(welcome, "Voir les options", 200, 26, function()
			welcome:Hide()
			Z:ToggleOptions()
		end)
		opt:SetPoint("BOTTOMRIGHT", welcome, "BOTTOMRIGHT", -16, 14)
		welcome.buttons = { go, opt }
	end
	Z.db.welcomed = true
	welcome:Paint()
	for _, pair in ipairs(welcome.texts) do
		pair[1]:SetTextColor(UI.Accent())
		pair[2]:SetTextColor(1, 1, 1)
	end
	for _, b in ipairs(welcome.buttons) do b:Paint(false) end
	welcome:Show()
end
