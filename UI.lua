-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Briques d'interface : textures, polices, listes de barres animées,
-- boutons, menus, panneaux et bouton de la mini-carte.
-- Uniquement des appels disponibles dans le client 3.3.5.

local ADDON, ns = ...
local Z = ns.Z

local UI = {}
Z.UI = UI

local floor, max, min, unpack = math.floor, math.max, math.min, unpack
local WHITE = "Interface\\Buttons\\WHITE8X8"

UI.fonts = {
	{ key = "arialn", name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ key = "friz", name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ key = "skurri", name = "Skurri", path = "Fonts\\skurri.ttf" },
	{ key = "morpheus", name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
}

UI.barTextures = {
	{ key = "degrade", name = "Dégradé", path = WHITE },
	{ key = "plat", name = "Plat", path = WHITE },
	{ key = "brillant", name = "Brillant", path = Z.MEDIA .. "bar_gloss.tga" },
	{ key = "raye", name = "Rayé", path = Z.MEDIA .. "bar_stripe.tga" },
	{ key = "blizzard", name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
}

UI.barColors = {
	{ key = "classe", name = "Couleur de classe" },
	{ key = "accent", name = "Couleur d'accent" },
	{ key = "rang", name = "Selon le classement" },
}

local function Lookup(list, key)
	for i = 1, #list do
		if list[i].key == key then return list[i] end
	end
	return list[1]
end
UI.Lookup = Lookup

function UI.Accent()
	local a = Z.db.accent
	return a[1], a[2], a[3]
end

function UI.FontPath()
	return Lookup(UI.fonts, Z.db.font).path
end

function UI.SetFont(fs, size, forceOutline)
	fs:SetFont(UI.FontPath(), size or Z.db.fontSize, (forceOutline or Z.db.fontOutline) and "OUTLINE" or "")
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetShadowOffset(1, -1)
end

function UI.Text(parent, size, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	UI.SetFont(fs, size)
	fs:SetTextColor(0.92, 0.94, 0.97)
	return fs
end

-- Hauteur à réserver pour un texte renvoyé à la ligne dans une largeur donnée.
-- Estimation prudente (jamais trop petite) : elle ne dépend pas de la mesure
-- du client, qui peut valoir zéro tant que le texte n'a pas été dessiné.
function UI.TextHeight(text, width, size)
	local perLine = max(10, floor(width / (size * 0.47)))
	local lines = 0
	for part in (text .. "\n"):gmatch("(.-)\n") do
		lines = lines + max(1, math.ceil(#part / perLine))
	end
	return lines * (size + 2)
end

-- Fixe le texte d'un bloc multi-lignes et renvoie sa hauteur réservée.
function UI.SetBlock(fs, text, width, size)
	local h = UI.TextHeight(text, width, size)
	fs:SetWidth(width)
	fs:SetHeight(h)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetText(text)
	return h
end

function UI.Solid(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(r, g, b, a or 1)
	return t
end

-- Bordure d'un pixel autour d'un cadre.
function UI.Border(frame, r, g, b, a)
	local t = {}
	for i = 1, 4 do t[i] = UI.Solid(frame, "BORDER", r, g, b, a) end
	t[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
	t[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
	t[1]:SetHeight(1)
	t[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
	t[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
	t[2]:SetHeight(1)
	t[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
	t[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
	t[3]:SetWidth(1)
	t[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
	t[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
	t[4]:SetWidth(1)
	return t
end

-- Ombre portée douce : quatre dégradés noirs qui s'estompent vers l'extérieur.
function UI.Shadow(frame, size, alpha)
	size, alpha = size or 5, alpha or 0.45
	local function Edge()
		local t = frame:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(WHITE)
		return t
	end
	local top, bottom, left, right = Edge(), Edge(), Edge(), Edge()
	top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 1)
	top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 1)
	top:SetHeight(size)
	top:SetGradientAlpha("VERTICAL", 0, 0, 0, alpha, 0, 0, 0, 0)
	bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
	bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -1)
	bottom:SetHeight(size)
	bottom:SetGradientAlpha("VERTICAL", 0, 0, 0, 0, 0, 0, 0, alpha)
	left:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1, 0)
	left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -1, 0)
	left:SetWidth(size)
	left:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, alpha)
	right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, 0)
	right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 1, 0)
	right:SetWidth(size)
	right:SetGradientAlpha("HORIZONTAL", 0, 0, 0, alpha, 0, 0, 0, 0)
end

function UI.Tooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:ClearLines()
	local r, g, b = UI.Accent()
	GameTooltip:AddLine(title, r, g, b)
	if text then GameTooltip:AddLine(text, 0.85, 0.85, 0.85, 1) end
	GameTooltip:Show()
end

-- Bouton-icône monochrome qui prend la couleur d'accent au survol.
function UI.IconButton(parent, icon, size, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(size)
	b:SetHeight(size)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints(b)
	b.tex:SetTexture(Z.MEDIA .. icon .. ".tga")
	b.tex:SetVertexColor(0.62, 0.67, 0.74)
	b.tip = tip
	b:SetScript("OnEnter", function(self)
		self.tex:SetVertexColor(UI.Accent())
		if self.tip then UI.Tooltip(self, self.tip, self.tipText) end
	end)
	b:SetScript("OnLeave", function(self)
		self.tex:SetVertexColor(0.62, 0.67, 0.74)
		GameTooltip:Hide()
	end)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", onClick)
	return b
end

function UI.SetIcon(b, icon)
	b.tex:SetTexture(Z.MEDIA .. icon .. ".tga")
end

-- Bouton plat avec libellé.
function UI.Button(parent, text, w, h, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(w)
	b:SetHeight(h or 22)
	b.bg = UI.Solid(b, "BACKGROUND", 1, 1, 1, 0.07)
	b.bg:SetAllPoints(b)
	b.line = UI.Solid(b, "BORDER", 1, 1, 1, 1)
	b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	b.line:SetHeight(1)
	b.label = UI.Text(b, 11)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label:SetText(text)
	function b:Paint(hover)
		local r, g, bl = UI.Accent()
		self.line:SetVertexColor(r, g, bl, (self.active or hover) and 1 or 0.35)
		self.bg:SetTexture(r, g, bl, self.active and 0.22 or (hover and 0.14 or 0.06))
		if self.active then self.label:SetTextColor(1, 1, 1) else self.label:SetTextColor(0.85, 0.88, 0.92) end
	end
	b:SetScript("OnEnter", function(self)
		self:Paint(true)
		if self.tip then UI.Tooltip(self, text, self.tip) end
	end)
	b:SetScript("OnLeave", function(self)
		self:Paint(false)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", onClick)
	b:Paint(false)
	return b
end

-------------------------------------------------------------------------------
-- Liste de barres animées
-------------------------------------------------------------------------------

local List = {}
List.__index = List

local function Animate(f, elapsed)
	local L = f.list
	local busy = false
	local k = min(1, elapsed * 9)
	for i = 1, #L.rows do
		local row = L.rows[i]
		if row.shown then
			local d = row.target - row.cur
			if d > 0.002 or d < -0.002 then
				row.cur = row.cur + d * k
				busy = true
			else
				row.cur = row.target
			end
			local w = row.cur * row.fw
			if w < 1 then
				row.fill:Hide()
				row.edge:Hide()
			else
				row.fill:SetWidth(w)
				row.fill:Show()
				row.edge:Show()
			end
		end
	end
	if not busy then f:SetScript("OnUpdate", nil) end
end

local function RowEnter(self)
	local L = self.list
	if L.onEnter and self.data then L.onEnter(self.data, self) end
end

local function RowLeave(self)
	GameTooltip:Hide()
	local L = self.list
	if L.onLeave then L.onLeave(self.data, self) end
end

local function RowClick(self, button)
	local L = self.list
	if L.onClick and self.data then L.onClick(self.data, button, self) end
end

local function CreateRow(L)
	local b = CreateFrame("Button", nil, L.f)
	b.list = L
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.bg = UI.Solid(b, "BACKGROUND", 1, 1, 1, 0.045)
	b.fill = b:CreateTexture(nil, "BORDER")
	b.edge = UI.Solid(b, "ARTWORK", 1, 1, 1, 0.35)
	b.edge:SetWidth(1)
	b.edge:SetPoint("TOPRIGHT", b.fill, "TOPRIGHT", 0, 0)
	b.edge:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT", 0, 0)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
	b.mark = UI.Solid(b, "OVERLAY", 1, 1, 1, 1)
	b.mark:SetWidth(2)
	b.mark:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	b.mark:Hide()
	b.right = b:CreateFontString(nil, "OVERLAY")
	b.left = b:CreateFontString(nil, "OVERLAY")
	b.left:SetJustifyH("LEFT")
	b.right:SetJustifyH("RIGHT")
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints(b)
	b.hl:SetTexture(1, 1, 1, 0.08)
	b:SetScript("OnEnter", RowEnter)
	b:SetScript("OnLeave", RowLeave)
	b:SetScript("OnClick", RowClick)
	b.cur, b.target, b.fw = 0, 0, 1
	return b
end

-- opt : rowHeight, spacing, fontSize, icons (booléen) ; par défaut, réglages globaux.
function UI.BarList(parent, opt)
	local L = setmetatable({ rows = {}, n = 0, offset = 0, W = 100, H = 100, opt = opt or {}, styled = 0 }, List)
	local f = CreateFrame("Frame", nil, parent)
	f.list = L
	L.f = f
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta) L:Scroll(-delta) end)
	return L
end

function List:RowHeight() return self.opt.rowHeight or Z.db.barHeight end
function List:Spacing() return self.opt.spacing or Z.db.barSpacing end

function List:Visible()
	local rh, sp = self:RowHeight(), self:Spacing()
	return max(0, floor((self.H + sp) / (rh + sp)))
end

function List:SetSize(w, h)
	self.W, self.H = max(10, w), max(0, h)
	self.f:SetWidth(self.W)
	self.f:SetHeight(max(1, self.H))
	self.styled = self.styled + 1
	self:Refresh()
end

function List:StyleRow(row, i)
	local rh, sp = self:RowHeight(), self:Spacing()
	local icons = self.opt.icons
	if icons == nil then icons = Z.db.showIcons end
	local fs = self.opt.fontSize or Z.db.fontSize
	if fs > rh - 2 then fs = max(7, rh - 2) end
	row:SetWidth(self.W)
	row:SetHeight(rh)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.f, "TOPLEFT", 0, -(i - 1) * (rh + sp))
	local off = icons and rh or 0
	row.iconOn = icons
	row.icon:SetWidth(rh)
	row.icon:SetHeight(rh)
	row.fw = max(1, self.W - off)
	row.bg:ClearAllPoints()
	row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", off, 0)
	row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	row.fill:ClearAllPoints()
	row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", off, 0)
	row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", off, 0)
	row.fill:SetTexture(UI.Lookup(UI.barTextures, Z.db.barTexture).path)
	UI.SetFont(row.left, fs)
	UI.SetFont(row.right, fs)
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", row, "LEFT", off + 4, 0)
	row.left:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.left:SetHeight(fs + 2)
	row.styled = self.styled
end

function List:SetData(data, n)
	self.data, self.n = data, n or #data
	self:Refresh()
end

function List:Scroll(delta)
	self.offset = self.offset + delta
	-- Le propriétaire peut préparer les lignes nouvellement visibles.
	if self.onScroll then self.onScroll() else self:Refresh() end
end

-- Première et dernière ligne de données actuellement affichées pour n lignes.
function List:Range(n)
	local vis = self:Visible()
	local off = self.offset
	local maxOff = max(0, n - vis)
	if off > maxOff then off = maxOff end
	if off < 0 then off = 0 end
	return off + 1, min(n, off + vis)
end

function List:Refresh()
	local data, n = self.data, self.n
	local vis = self:Visible()
	local maxOff = max(0, n - vis)
	if self.offset > maxOff then self.offset = maxOff end
	if self.offset < 0 then self.offset = 0 end
	local rows = self.rows
	local gradient = Z.db.barTexture == "degrade"
	local animate = Z.db.animate and not self.opt.static
	local moving = false
	for i = 1, vis do
		local row = rows[i]
		if not row then
			row = CreateRow(self)
			rows[i] = row
		end
		if row.styled ~= self.styled then self:StyleRow(row, i) end
		local d = data and (i + self.offset) <= n and data[i + self.offset]
		if d then
			row.data = d
			local r, g, b = d.r or 0.5, d.g or 0.5, d.b or 0.5
			if gradient then
				row.fill:SetGradientAlpha("HORIZONTAL", r * 0.45, g * 0.45, b * 0.45, 0.9, r, g, b, 0.95)
			else
				row.fill:SetGradientAlpha("HORIZONTAL", r, g, b, 0.9, r, g, b, 0.9)
			end
			if row.iconOn and d.icon then
				row.icon:SetTexture(d.icon)
				if d.coords then
					row.icon:SetTexCoord(unpack(d.coords))
				else
					row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				end
				row.icon:Show()
			else
				row.icon:Hide()
			end
			if d.mark then
				row.mark:SetVertexColor(UI.Accent())
				row.mark:Show()
			else
				row.mark:Hide()
			end
			row.left:SetText(d.label or "")
			row.right:SetText(d.text or "")
			local frac = d.frac or 0
			if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
			row.target = frac
			if not animate or not row.shown then row.cur = frac end
			if not row.shown then
				row.shown = true
				row:Show()
			end
			moving = true
		elseif row.shown ~= false then
			row.shown = false
			row.data = nil
			row:Hide()
		end
	end
	for i = vis + 1, #rows do
		if rows[i].shown ~= false then
			rows[i].shown = false
			rows[i].data = nil
			rows[i]:Hide()
		end
	end
	if moving then
		Animate(self.f, 0.001)
		if animate then self.f:SetScript("OnUpdate", Animate) end
	end
end

-------------------------------------------------------------------------------
-- Menu contextuel
-------------------------------------------------------------------------------

local menu, catcher
local ITEM_H = 18

local function CloseMenu()
	if menu then
		menu:Hide()
		catcher:Hide()
	end
end
UI.CloseMenu = CloseMenu

local function CreateMenu()
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN")
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", CloseMenu)
	catcher:Hide()

	menu = CreateFrame("Frame", "ZenithMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu.bg = UI.Solid(menu, "BACKGROUND", 0, 0, 0, 1)
	menu.bg:SetAllPoints(menu)
	menu.border = UI.Border(menu, 1, 1, 1, 0.5)
	menu.items = {}
	menu:Hide()
end

local function MenuItem(i)
	local b = menu.items[i]
	if b then return b end
	b = CreateFrame("Button", nil, menu)
	b:SetHeight(ITEM_H)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints(b)
	b.hl:SetTexture(1, 1, 1, 0.1)
	b.check = UI.Solid(b, "ARTWORK", 1, 1, 1, 1)
	b.check:SetWidth(3)
	b.check:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	b.check:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, 3)
	b.label = b:CreateFontString(nil, "OVERLAY")
	b.label:SetPoint("LEFT", b, "LEFT", 12, 0)
	b.label:SetJustifyH("LEFT")
	b:SetScript("OnEnter", function(self)
		local item = self.item
		if not item or not item.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(item.text, UI.Accent())
		GameTooltip:AddLine(item.tip, 0.9, 0.9, 0.9, 1)
		if item.note then GameTooltip:AddLine(item.note, 0.55, 0.75, 0.6, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self)
		local item = self.item
		if not item or item.title then return end
		CloseMenu()
		if item.func then item.func(item.arg) end
	end)
	menu.items[i] = b
	return b
end

-- items : liste de { text, checked, func, arg, title, color }
function UI.ShowMenu(anchor, items)
	if not menu then CreateMenu() end
	if menu:IsShown() and menu.anchor == anchor then
		CloseMenu()
		return
	end
	menu.anchor = anchor
	local db = Z.db
	local ar, ag, ab = UI.Accent()
	menu.bg:SetTexture(db.bg[1], db.bg[2], db.bg[3], 0.97)
	for i = 1, 4 do menu.border[i]:SetTexture(ar, ag, ab, 0.55) end
	local width = 120
	for i = 1, #items do
		local item = items[i]
		local b = MenuItem(i)
		b.item = item
		UI.SetFont(b.label, 11)
		b.label:SetText(item.text)
		if item.title then
			b.label:SetTextColor(ar, ag, ab)
			b.hl:SetTexture(1, 1, 1, 0)
		elseif item.color then
			b.label:SetTextColor(item.color[1], item.color[2], item.color[3])
			b.hl:SetTexture(1, 1, 1, 0.1)
		else
			b.label:SetTextColor(0.9, 0.92, 0.95)
			b.hl:SetTexture(1, 1, 1, 0.1)
		end
		if item.checked then
			b.check:SetVertexColor(ar, ag, ab)
			b.check:Show()
		else
			b.check:Hide()
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * ITEM_H)
		b:Show()
		local w = (b.label:GetStringWidth() or 0) + 28
		if w > width then width = w end
	end
	for i = #items + 1, #menu.items do menu.items[i]:Hide() end
	for i = 1, #items do menu.items[i]:SetWidth(width) end
	menu:SetWidth(width + 4)
	menu:SetHeight(#items * ITEM_H + 4)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	catcher:Show()
	menu:Show()
end

-------------------------------------------------------------------------------
-- Panneau flottant (détails, options, rapport)
-------------------------------------------------------------------------------

function UI.Panel(name, w, h, title)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetWidth(w)
	f:SetHeight(h)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.bg = UI.Solid(f, "BACKGROUND", 0, 0, 0, 1)
	f.bg:SetAllPoints(f)
	f.border = UI.Border(f, 0, 0, 0, 1)
	UI.Shadow(f, 8, 0.5)
	f.head = UI.Solid(f, "BORDER", 0, 0, 0, 1)
	f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.head:SetHeight(30)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetTexture(WHITE)
	f.line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.line:SetHeight(2)
	f.title = UI.Text(f, 14)
	f.title:SetPoint("LEFT", f.head, "LEFT", 12, -1)
	f.title:SetText(title or "")
	f.sub = UI.Text(f, 11)
	f.sub:SetPoint("LEFT", f.title, "RIGHT", 10, -1)
	f.sub:SetTextColor(0.6, 0.65, 0.72)
	f.close = UI.IconButton(f, "close", 14, "Fermer", function() f:Hide() end)
	f.close:SetPoint("RIGHT", f.head, "RIGHT", -10, -1)
	function f:Paint()
		local db = Z.db
		local r, g, b = UI.Accent()
		self.bg:SetTexture(db.bg[1], db.bg[2], db.bg[3], 0.97)
		self.head:SetTexture(db.header[1], db.header[2], db.header[3], 1)
		self.line:SetGradientAlpha("HORIZONTAL", r, g, b, 1, r, g, b, 0.15)
		for i = 1, 4 do self.border[i]:SetTexture(0, 0, 0, 0.9) end
		UI.SetFont(self.title, 14)
		UI.SetFont(self.sub, 11)
	end
	f:Paint()
	if name then tinsert(UISpecialFrames, name) end
	f:Hide()
	return f
end

-------------------------------------------------------------------------------
-- Bouton de la mini-carte
-------------------------------------------------------------------------------

local function PlaceMinimap(b)
	local a = math.rad(Z.db.minimapAngle or 215)
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

function Z:InitMinimap()
	local b = CreateFrame("Button", "ZenithMinimapButton", Minimap)
	Z.minimapButton = b
	b:SetWidth(31)
	b:SetHeight(31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local back = UI.Solid(b, "BACKGROUND", 0.04, 0.05, 0.08, 1)
	back:SetWidth(20)
	back:SetHeight(20)
	back:SetPoint("CENTER", b, "CENTER", 0, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetWidth(18)
	b.icon:SetHeight(18)
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 1)
	b.icon:SetTexture(Z.MEDIA .. "logo.tga")
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetWidth(53)
	ring:SetHeight(53)
	ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	local function Drag()
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		Z.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
		PlaceMinimap(b)
	end
	b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Drag) end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then Z:ToggleOptions() else Z:ToggleWindows() end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Zénith", UI.Accent())
		GameTooltip:AddLine("Clic gauche : afficher ou masquer les fenêtres", 1, 1, 1)
		GameTooltip:AddLine("Clic droit : options", 1, 1, 1)
		GameTooltip:AddLine("Glisser : déplacer ce bouton", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local function Apply()
		b.icon:SetVertexColor(UI.Accent())
		PlaceMinimap(b)
		if Z.db.minimapShow then b:Show() else b:Hide() end
	end
	Z:On("SETTINGS", Apply)
	Apply()
end
