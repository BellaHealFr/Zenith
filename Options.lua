-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Panneau d'options (entièrement en français, sans bibliothèque externe).

local ADDON, ns = ...
local Z = ns.Z
local UI = Z.UI

local floor, max, min = math.floor, math.max, math.min
local Num, Time = Z.Num, Z.Time

local W, H = 640, 520
local NAV = 150
local PW = W - NAV - 36 -- largeur utile d'une page
local ROW = 30

local O
local pages = {}

local function Changed()
	Z:Fire("SETTINGS")
end

-------------------------------------------------------------------------------
-- Composants
-------------------------------------------------------------------------------

local function Row(page, label, tip)
	local r = CreateFrame("Frame", nil, page)
	r:SetWidth(PW)
	r:SetHeight(ROW)
	r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.y)
	page.y = page.y + ROW
	r.label = UI.Text(r, 12)
	r.label:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.label:SetText(label)
	if tip then
		r:EnableMouse(true)
		r:SetScript("OnEnter", function(self) UI.Tooltip(self, label, tip) end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	page.widgets[#page.widgets + 1] = r
	return r
end

local function Header(page, text)
	if page.y > 0 then page.y = page.y + 8 end
	local fs = UI.Text(page, 12)
	fs:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.y - 4)
	fs:SetText(text)
	fs.isHead = true -- les titres de section prennent la couleur d'accent
	local line = UI.Solid(page, "ARTWORK", 1, 1, 1, 0.12)
	line:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.y - 22)
	line:SetWidth(PW)
	line:SetHeight(1)
	page.heads[#page.heads + 1] = fs
	page.y = page.y + 28
end

local function Toggle(page, label, key, tip)
	local r = Row(page, label, tip)
	local b = CreateFrame("Button", nil, r)
	b:SetWidth(34)
	b:SetHeight(16)
	b:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	b.track = UI.Solid(b, "BACKGROUND", 1, 1, 1, 0.12)
	b.track:SetAllPoints(b)
	b.knob = UI.Solid(b, "ARTWORK", 1, 1, 1, 1)
	b.knob:SetWidth(14)
	b.knob:SetHeight(12)
	function r:Sync()
		local on = Z.db[key]
		local ar, ag, ab = UI.Accent()
		b.knob:ClearAllPoints()
		if on then
			b.knob:SetPoint("RIGHT", b, "RIGHT", -2, 0)
			b.knob:SetVertexColor(1, 1, 1)
			b.track:SetTexture(ar, ag, ab, 0.75)
		else
			b.knob:SetPoint("LEFT", b, "LEFT", 2, 0)
			b.knob:SetVertexColor(0.6, 0.63, 0.68)
			b.track:SetTexture(1, 1, 1, 0.12)
		end
	end
	b:SetScript("OnClick", function()
		Z.db[key] = not Z.db[key]
		r:Sync()
		Changed()
	end)
	if tip then
		b:SetScript("OnEnter", function() UI.Tooltip(r, label, tip) end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	return r
end

local function Slider(page, label, key, lo, hi, step, fmt, tip)
	local r = Row(page, label, tip)
	local TW = 170
	local t = CreateFrame("Button", nil, r)
	t:SetWidth(TW)
	t:SetHeight(16)
	t:SetPoint("RIGHT", r, "RIGHT", -52, 0)
	local rail = UI.Solid(t, "BACKGROUND", 1, 1, 1, 0.14)
	rail:SetPoint("LEFT", t, "LEFT", 0, 0)
	rail:SetWidth(TW)
	rail:SetHeight(3)
	local fill = UI.Solid(t, "BORDER", 1, 1, 1, 1)
	fill:SetPoint("LEFT", t, "LEFT", 0, 0)
	fill:SetHeight(3)
	local knob = UI.Solid(t, "ARTWORK", 1, 1, 1, 1)
	knob:SetWidth(5)
	knob:SetHeight(13)
	knob:SetPoint("CENTER", fill, "RIGHT", 0, 0)
	local value = UI.Text(r, 11)
	value:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	function r:Sync()
		local v = Z.db[key]
		local frac = (v - lo) / (hi - lo)
		if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
		fill:SetWidth(max(1, frac * TW))
		fill:SetVertexColor(UI.Accent())
		value:SetText((fmt(v):gsub("%.", ",")))
	end
	local function Drag()
		local x = GetCursorPosition() / t:GetEffectiveScale() - (t:GetLeft() or 0)
		local frac = max(0, min(1, x / TW))
		local v = lo + frac * (hi - lo)
		v = floor(v / step + 0.5) * step
		if v < lo then v = lo elseif v > hi then v = hi end
		if v ~= Z.db[key] then
			Z.db[key] = v
			r:Sync()
			Changed()
		end
	end
	t:SetScript("OnMouseDown", function(self) self:SetScript("OnUpdate", Drag) end)
	t:SetScript("OnMouseUp", function(self)
		Drag()
		self:SetScript("OnUpdate", nil)
	end)
	t:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	return r
end

-- values : liste de { key, name } ; onPick facultatif remplace l'affectation simple.
local function Choice(page, label, key, values, tip, onPick)
	local r = Row(page, label, tip)
	local b
	b = UI.Button(r, "", 170, 22, function(self)
		local items = {}
		for _, v in ipairs(values) do
			items[#items + 1] = { text = v.name, checked = Z.db[key] == v.key, func = function()
				if onPick then onPick(v.key) else Z.db[key] = v.key end
				Changed()
				if O then O:Sync() end
			end }
		end
		UI.ShowMenu(self, items)
	end)
	b:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	function r:Sync()
		b.label:SetText(UI.Lookup(values, Z.db[key]).name)
		b:Paint(false)
	end
	return r
end

local function Color(page, label, key, tip)
	local r = Row(page, label, tip)
	local b = CreateFrame("Button", nil, r)
	b:SetWidth(34)
	b:SetHeight(16)
	b:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	b.sw = UI.Solid(b, "ARTWORK", 1, 1, 1, 1)
	b.sw:SetAllPoints(b)
	UI.Border(b, 1, 1, 1, 0.35)
	function r:Sync()
		local c = Z.db[key]
		b.sw:SetTexture(c[1], c[2], c[3], 1)
	end
	b:SetScript("OnClick", function()
		local c = Z.db[key]
		local old = { c[1], c[2], c[3] }
		local function Apply(restore)
			local nr, ng, nb
			if restore then
				nr, ng, nb = old[1], old[2], old[3]
			else
				nr, ng, nb = ColorPickerFrame:GetColorRGB()
			end
			c[1], c[2], c[3] = nr, ng, nb
			r:Sync()
			Changed()
		end
		ColorPickerFrame:Hide()
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.opacityFunc = nil
		ColorPickerFrame.func = function() Apply(false) end
		ColorPickerFrame.cancelFunc = function() Apply(true) end
		ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
		ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
		ColorPickerFrame:Show()
	end)
	return r
end

local function Action(page, label, text, fn, tip)
	local r = Row(page, label, tip)
	local b = UI.Button(r, text, 170, 22, fn)
	b:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	function r:Sync() b:Paint(false) end
	return r
end

local function Paragraph(page, text)
	local fs = UI.Text(page, 12)
	fs:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.y)
	fs:SetTextColor(0.8, 0.83, 0.88)
	local h = UI.SetBlock(fs, text, PW, 12)
	page.heads[#page.heads + 1] = fs
	page.y = page.y + h + 10
	return fs
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------

local function Named(list)
	local out = {}
	for i, v in ipairs(list) do out[i] = { key = v.key, name = v.name } end
	return out
end

local function Int(v) return ("%d"):format(v) end

local function BuildAppearance(p)
	Header(p, "Thème")
	Choice(p, "Thème prédéfini", "theme", Named(Z.themes), "Applique un jeu de couleurs complet. Les couleurs restent modifiables ensuite.",
		function(key) Z:SetTheme(key) end)
	Color(p, "Couleur d'accent", "accent", "Couleur des lignes, des surbrillances et de votre nom.")
	Color(p, "Couleur de fond", "bg")
	Color(p, "Couleur de l'en-tête", "header")
	Slider(p, "Opacité du fond", "bgAlpha", 0, 1, 0.05, function(v) return ("%d %%"):format(v * 100 + 0.5) end)
	Slider(p, "Échelle des fenêtres", "scale", 0.6, 1.6, 0.05, function(v) return ("%d %%"):format(v * 100 + 0.5) end)
	Header(p, "Texte")
	Choice(p, "Police", "font", Named(UI.fonts))
	Slider(p, "Taille du texte", "fontSize", 8, 16, 1, Int)
	Toggle(p, "Contour du texte", "fontOutline")
end

local function BuildBars(p)
	Header(p, "Style des barres")
	Choice(p, "Texture", "barTexture", Named(UI.barTextures))
	Choice(p, "Couleur", "barColor", UI.barColors)
	Slider(p, "Hauteur", "barHeight", 10, 30, 1, Int)
	Slider(p, "Espacement", "barSpacing", 0, 4, 1, Int)
	Toggle(p, "Animation fluide", "animate", "Les barres glissent vers leur nouvelle taille au lieu de sauter.")
	Header(p, "Contenu")
	Toggle(p, "Numéro de classement", "showRank")
	Toggle(p, "Icône devant chaque barre", "showIcons")
	Choice(p, "Type d'icône", "iconMode", {
		{ key = "spe", name = "Spécialisation" }, { key = "role", name = "Rôle" }, { key = "classe", name = "Classe" },
	}, "Spécialisation : l'icône de l'arbre de talents du joueur. Rôle : tank, soigneur ou dégâts. Tant que la spécialisation d'un joueur est inconnue, l'icône de classe est affichée.")
	Toggle(p, "Valeur par seconde", "showPerSec")
	Toggle(p, "Pourcentage du total", "showPercent")
	Toggle(p, "Nombres complets", "fullNumbers", "Affiche 1 234 567 au lieu de 1,23 M.")
end

local function BuildWindows(p)
	Header(p, "Comportement")
	Toggle(p, "Mode expert : toutes les mesures", "expert", "Désactivé, le menu ne propose que les mesures essentielles pour débuter. Activé, il ajoute les mesures avancées.")
	Toggle(p, "Résumé à la fin de chaque combat", "toast", "Un petit bandeau indique votre classement et votre DPS ou SPS, puis disparaît tout seul.")
	Toggle(p, "Verrouiller les fenêtres", "locked", "Empêche de déplacer et de redimensionner les fenêtres.")
	Toggle(p, "Pied de fenêtre", "footer", "Affiche le combat, sa durée, le total du groupe et l'écart avec votre record.")
	Toggle(p, "Masquer hors combat", "hideOOC")
	Toggle(p, "Masquer hors groupe", "hideSolo")
	Toggle(p, "Bouton de la mini-carte", "minimapShow")
	Slider(p, "Fréquence de mise à jour", "updateRate", 0.1, 1, 0.05, function(v) return ("%.2f s"):format(v) end,
		"Intervalle entre deux rafraîchissements. Une valeur plus élevée économise le processeur.")
	Header(p, "Gestion")
	Action(p, "Fenêtre supplémentaire", "Créer", function() Z:NewWindow() end, "Par exemple une fenêtre de dégâts et une de soins côte à côte (5 au maximum).")
	Action(p, "Toutes les fenêtres", "Afficher / masquer", function() Z:ToggleWindows() end)
end

local function BuildCombat(p)
	Header(p, "Segments")
	Slider(p, "Combats conservés", "maxSegments", 3, 30, 1, Int)
	Slider(p, "Durée minimale d'un combat", "minFight", 0, 30, 1, function(v) return ("%d s"):format(v) end,
		"Les combats plus courts ne sont pas enregistrés comme segments (ils comptent tout de même dans le total).")
	Toggle(p, "Ne garder que les boss", "bossOnly", "Supprime automatiquement les combats contre les monstres ordinaires, sauf le dernier.")
	Toggle(p, "Conserver entre les sessions", "persist", "Les données survivent à une déconnexion ou à un rechargement de l'interface.")
	Choice(p, "En entrant dans une instance", "resetInstance", {
		{ key = "demander", name = "Demander" }, { key = "toujours", name = "Réinitialiser" }, { key = "jamais", name = "Ne rien faire" },
	})
	Header(p, "Calculs")
	Toggle(p, "DPS sur le temps d'activité", "activeTime", "Divise par le temps réellement passé à agir plutôt que par la durée du combat.")
	Toggle(p, "Suivre les améliorations et affaiblissements", "trackAuras", "Mesure le temps d'effet de chaque amélioration et de chaque affaiblissement (onglet Auras de la fiche d'un joueur). À désactiver sur une machine modeste : ce sont les événements les plus nombreux du jeu.")
	Header(p, "Assistance")
	Toggle(p, "Réparer le journal de combat", "fixLog", "Le client 3.3.5 cesse parfois d'envoyer les événements de combat : Zénith le détecte et relance le journal automatiquement.")
	Toggle(p, "Synchroniser avec le groupe", "sync", "Chaque joueur équipé de Zénith partage ses propres dégâts, soins et durée de combat : tout le groupe affiche les mêmes chiffres, même pour un joueur hors de portée de votre journal de combat.")
	Toggle(p, "Annoncer mes records", "announceRecord")
	Toggle(p, "Annoncer qui engage le boss", "announcePull")
end

local recordRows = {}

local function BuildRecords(p)
	Header(p, "Records personnels par boss")
	p.list = UI.BarList(p, { rowHeight = 20, spacing = 2, fontSize = 11, icons = false })
	p.list.f:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -p.y)
	p.list:SetSize(PW, 300)
	p.empty = UI.Text(p, 12)
	p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -p.y - 8)
	p.empty:SetWidth(PW)
	p.empty:SetJustifyH("LEFT")
	p.empty:SetTextColor(0.55, 0.6, 0.68)
	p.empty:SetText("Aucun record pour le moment. Tuez un boss : votre meilleur DPS est mémorisé, puis votre écart avec ce record s'affiche en direct lors des prochains affrontements.")
	p.y = p.y + 310
	-- Les records ne peuvent pas être reconstitués : confirmation obligatoire.
	Action(p, "Effacer tous les records", "Effacer", function() StaticPopup_Show("ZENITH_RESET_RECORDS") end)
	function p:Refresh()
		local keys = {}
		for k in pairs(Z.char.records) do keys[#keys + 1] = k end
		table.sort(keys)
		local top = 1
		for _, k in ipairs(keys) do top = max(top, Z.char.records[k].dps or 0) end
		for i, k in ipairs(keys) do
			local rec = Z.char.records[k]
			local d = recordRows[i]
			if not d then
				d = {}
				recordRows[i] = d
			end
			d.label = k
			local parts = {}
			if rec.dps then parts[#parts + 1] = Num(rec.dps) .. " DPS (" .. Time(rec.dur) .. ", " .. (rec.date or "?") .. ")" end
			if rec.hps then parts[#parts + 1] = Num(rec.hps) .. " SPS" end
			d.text = table.concat(parts, "  -  ")
			d.frac = (rec.dps or 0) / top
			d.r, d.g, d.b = UI.Accent()
		end
		self.list.styled = self.list.styled + 1
		self.list:SetData(recordRows, #keys)
		if #keys == 0 then self.empty:Show() else self.empty:Hide() end
	end
end

local function BuildHelp(p)
	Header(p, "Prise en main")
	Paragraph(p, "Clic sur le titre d'une fenêtre : changer de mode. Clic droit sur le titre ou icône horloge : changer de combat. Clic sur une barre : détails du joueur (sorts, cibles, graphique, morts, analyse).")
	Paragraph(p, "Icône lecture : rejoue le combat affiché. Records : votre meilleur DPS par boss est mémorisé, et le pied de fenêtre indique ensuite votre avance ou votre retard en direct.")
	Action(p, "Présentation pour débuter", "Revoir", function() Z:ShowWelcome() end)
	Header(p, "Petit lexique")
	Paragraph(p, "DPS : dégâts par seconde.   SPS : soins par seconde.\nAbsorption : dégâts annulés par un bouclier.   Excès de soins : soin lancé sur une cible déjà en pleine santé.\nAtténuation : dégâts réduits (absorbés, bloqués, résistés).   Évitement : attaques esquivées, parées ou ratées.")
	Header(p, "Commandes")
	Paragraph(p, "/zenith : ouvrir ces options   -   /zenith aide : revoir la présentation\n/zenith basculer : afficher ou masquer   -   /zenith reinit : effacer les données\n/zenith verrou : verrouiller   -   /zenith nouvelle : créer une fenêtre   -   /zenith memoire")
	p.stats = Paragraph(p, " \n \n ")
	function p:Refresh()
		self.stats:SetText(("Zénith %s  -  %d réparation(s) du journal de combat pendant cette session.\nÉtat : %s"):format(
			Z.version, Z.logFixes, Z:MemoryText()))
	end
end

local PAGES = {
	{ key = "apparence", name = "Apparence", build = BuildAppearance },
	{ key = "barres", name = "Barres", build = BuildBars },
	{ key = "fenetres", name = "Fenêtres", build = BuildWindows },
	{ key = "combat", name = "Combat", build = BuildCombat },
	{ key = "records", name = "Records", build = BuildRecords },
	{ key = "aide", name = "Aide", build = BuildHelp },
}

-------------------------------------------------------------------------------
-- Panneau
-------------------------------------------------------------------------------

local function Build()
	O = UI.Panel("ZenithOptions", W, H, "Zénith")
	O.sub:SetText("Options")
	O.navBg = UI.Solid(O, "BORDER", 0, 0, 0, 0.25)
	O.navBg:SetPoint("TOPLEFT", O, "TOPLEFT", 0, -30)
	O.navBg:SetPoint("BOTTOMLEFT", O, "BOTTOMLEFT", 0, 0)
	O.navBg:SetWidth(NAV)
	O.nav = {}
	for i, def in ipairs(PAGES) do
		local b = UI.Button(O, def.name, NAV - 20, 24, function()
			O.page = def.key
			O:Sync()
		end)
		b:SetPoint("TOPLEFT", O, "TOPLEFT", 10, -42 - (i - 1) * 28)
		O.nav[def.key] = b
		local p = CreateFrame("Frame", nil, O)
		p:SetPoint("TOPLEFT", O, "TOPLEFT", NAV + 18, -42)
		p:SetWidth(PW)
		p:SetHeight(H - 54)
		p.y, p.widgets, p.heads = 0, {}, {}
		def.build(p)
		p:Hide()
		pages[def.key] = p
	end
	O.page = "apparence"

	-- Signature, en bas de la colonne de navigation.
	O.creditName = UI.Text(O, 13)
	O.creditName:SetPoint("BOTTOMLEFT", O, "BOTTOMLEFT", 12, 26)
	O.creditName:SetText("BellaHealFr")
	O.creditLabel = UI.Text(O, 10)
	O.creditLabel:SetPoint("BOTTOMLEFT", O.creditName, "TOPLEFT", 0, 3)
	O.creditLabel:SetText("Créé par")
	O.creditLabel:SetTextColor(0.55, 0.6, 0.68)
	O.creditVersion = UI.Text(O, 10)
	O.creditVersion:SetPoint("BOTTOMLEFT", O, "BOTTOMLEFT", 12, 10)
	O.creditVersion:SetText("Zénith, version " .. Z.version)
	O.creditVersion:SetTextColor(0.42, 0.46, 0.53)

	function O:Sync()
		self:Paint()
		local ar, ag, ab = UI.Accent()
		UI.SetFont(self.creditLabel, 10)
		UI.SetFont(self.creditName, 13)
		UI.SetFont(self.creditVersion, 10)
		self.creditName:SetTextColor(ar, ag, ab)
		for key, p in pairs(pages) do
			local on = key == self.page
			self.nav[key].active = on
			self.nav[key]:Paint(false)
			if on then
				p:Show()
				for _, fs in ipairs(p.heads) do UI.SetFont(fs, 12) end
				for _, w in ipairs(p.widgets) do
					UI.SetFont(w.label, 12)
					if w.Sync then w:Sync() end
				end
				if p.Refresh then p:Refresh() end
			else
				p:Hide()
			end
		end
		for _, def in ipairs(PAGES) do
			local p = pages[def.key]
			for i = 1, #p.heads do
				if p.heads[i].isHead then p.heads[i]:SetTextColor(ar, ag, ab) end
			end
		end
	end
	O:SetScript("OnShow", function(self) self:Sync() end)
	Z:On("RESET", function()
		if O:IsShown() then O:Sync() end
	end)
	-- Un réglage changé ailleurs (menu d'une fenêtre, commande) se reflète ici.
	Z:On("SETTINGS", function()
		if O:IsShown() then O:Sync() end
	end)
end

StaticPopupDialogs["ZENITH_RESET_RECORDS"] = {
	text = "Zénith : effacer définitivement tous vos records personnels ?",
	button1 = "Effacer",
	button2 = "Annuler",
	OnAccept = function()
		Z.char.records = {}
		if O and O:IsShown() then O:Sync() end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function Z:ToggleOptions()
	if not O then Build() end
	if O:IsShown() then
		O:Hide()
	else
		O:Sync()
		O:Show()
	end
end
