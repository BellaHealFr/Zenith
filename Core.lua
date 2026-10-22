-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Compteur de combat pour World of Warcraft 3.3.5
-- Noyau : espace de noms, réglages, outils, événements, commandes.

local ADDON, ns = ...

-- Sans parent : les minuteries continuent même quand l'interface est masquée (Alt+Z).
local Z = CreateFrame("Frame", "ZenithCore")
ns.Z = Z
_G.Zenith = Z

Z.name = ADDON
Z.version = "1.10.3"
Z.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
Z.SCHEMA = 2

local pairs, type, floor = pairs, type, math.floor
local tremove = table.remove

-------------------------------------------------------------------------------
-- Réglages par défaut
-------------------------------------------------------------------------------

Z.themes = {
	{ key = "neon",      name = "Néon",       bg = { 0.05, 0.06, 0.09 }, header = { 0.08, 0.10, 0.15 }, accent = { 0.20, 0.84, 1.00 } },
	{ key = "obsidienne", name = "Obsidienne", bg = { 0.04, 0.04, 0.04 }, header = { 0.09, 0.08, 0.06 }, accent = { 1.00, 0.78, 0.25 } },
	{ key = "braise",    name = "Braise",     bg = { 0.08, 0.04, 0.04 }, header = { 0.13, 0.06, 0.05 }, accent = { 1.00, 0.38, 0.25 } },
	{ key = "emeraude",  name = "Émeraude",   bg = { 0.03, 0.07, 0.06 }, header = { 0.05, 0.11, 0.09 }, accent = { 0.25, 0.95, 0.60 } },
	{ key = "amethyste", name = "Améthyste",  bg = { 0.06, 0.04, 0.09 }, header = { 0.10, 0.07, 0.15 }, accent = { 0.72, 0.48, 1.00 } },
	{ key = "givre",     name = "Givre",      bg = { 0.10, 0.12, 0.15 }, header = { 0.15, 0.18, 0.22 }, accent = { 0.86, 0.93, 1.00 } },
}

local defaults = {
	-- Apparence
	theme = "neon",
	bg = { 0.05, 0.06, 0.09 },
	header = { 0.08, 0.10, 0.15 },
	accent = { 0.20, 0.84, 1.00 },
	bgAlpha = 0.85,
	scale = 1,
	font = "arialn",
	fontSize = 11,
	fontOutline = false,
	-- Barres
	barHeight = 18,
	barSpacing = 1,
	barTexture = "degrade",
	barColor = "classe",
	showRank = true,
	showIcons = true,
	iconMode = "spe",
	showPercent = true,
	showPerSec = true,
	animate = true,
	fullNumbers = false,
	-- Fenêtres
	footer = true,
	locked = false,
	hideOOC = false,
	hideSolo = false,
	updateRate = 0.25,
	-- Combat
	maxSegments = 10,
	bossOnly = false,
	minFight = 5,
	persist = true,
	resetInstance = "demander",
	activeTime = false,
	fixLog = true,
	sync = true,
	announceRecord = true,
	announcePull = true,
	trackAuras = true,
	-- Accessibilité
	expert = false,
	toast = true,
	welcomed = false,
	-- Bouton de la mini-carte
	minimapShow = true,
	minimapAngle = 215,
	-- Rapport
	reportChannel = "GROUPE",
	reportLines = 5,
	windows = {
		{ mode = "damage", x = nil, y = nil, w = 260, h = 190 },
	},
}

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			-- Les listes (couleurs, fenêtres) ne sont complétées que si elles sont vides.
			if next(dst[k]) == nil then
				for i, sub in pairs(v) do
					if type(sub) == "table" then
						dst[k][i] = {}
						CopyDefaults(dst[k][i], sub)
					else
						dst[k][i] = sub
					end
				end
			end
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-------------------------------------------------------------------------------
-- Outils
-------------------------------------------------------------------------------

function Z:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33d6ffZénith|r : " .. tostring(msg))
end

local function Comma(s)
	return (s:gsub("%.", ","))
end
Z.Comma = Comma

-- Nombre au format français : 1,25 M / 12,3 k / 950
function Z.Num(n)
	n = n or 0
	if Z.db and Z.db.fullNumbers then
		local s = ("%.0f"):format(n)
		local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
		return (out:gsub("^ ", ""))
	end
	if n >= 1e6 then
		return Comma(("%.2f M"):format(n / 1e6))
	elseif n >= 1e4 then
		return Comma(("%.1f k"):format(n / 1e3))
	elseif n >= 1e3 then
		return Comma(("%.2f k"):format(n / 1e3))
	end
	return ("%.0f"):format(n)
end

function Z.Pct(n)
	return Comma(("%.1f %%"):format(n or 0))
end

function Z.Time(sec)
	sec = floor((sec or 0) + 0.5)
	if sec < 0 then sec = 0 end
	return ("%d:%02d"):format(floor(sec / 60), sec % 60)
end

local CLASS_FALLBACK = { r = 0.62, g = 0.66, b = 0.72 }
function Z.ClassColor(class)
	local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	c = c or CLASS_FALLBACK
	return c.r, c.g, c.b
end

function Z.Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-------------------------------------------------------------------------------
-- Messages internes
-------------------------------------------------------------------------------

local listeners = {}

function Z:On(msg, fn)
	local l = listeners[msg]
	if not l then
		l = {}
		listeners[msg] = l
	end
	l[#l + 1] = fn
end

function Z:Fire(msg, ...)
	local l = listeners[msg]
	if l then
		for i = 1, #l do
			l[i](...)
		end
	end
end

-------------------------------------------------------------------------------
-- Minuteries (le client 3.3.5 n'a pas C_Timer)
-------------------------------------------------------------------------------

local timers, tickers = {}, {}

function Z:After(delay, fn)
	timers[#timers + 1] = { t = delay, fn = fn }
end

function Z:Every(interval, fn)
	tickers[#tickers + 1] = { i = interval, t = 0, fn = fn }
end

local function Safe(fn)
	local ok, err = pcall(fn)
	if not ok then geterrorhandler()(err) end
end

Z:SetScript("OnUpdate", function(_, elapsed)
	for i = 1, #tickers do
		local tk = tickers[i]
		tk.t = tk.t + elapsed
		if tk.t >= tk.i then
			tk.t = 0
			Safe(tk.fn)
		end
	end
	local n = #timers
	if n > 0 then
		for i = n, 1, -1 do
			local tm = timers[i]
			tm.t = tm.t - elapsed
			if tm.t <= 0 then
				tremove(timers, i)
				Safe(tm.fn)
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- Événements
-------------------------------------------------------------------------------

Z:SetScript("OnEvent", function(self, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		return Z.CLEU(...)
	end
	local f = self[event]
	if f then f(self, ...) end
end)

Z:RegisterEvent("ADDON_LOADED")
Z:RegisterEvent("PLAYER_LOGIN")
Z:RegisterEvent("PLAYER_LOGOUT")

function Z:ADDON_LOADED(name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")

	if type(ZenithDB) ~= "table" or ZenithDB.schema ~= Z.SCHEMA then ZenithDB = {} end
	CopyDefaults(ZenithDB, defaults)
	ZenithDB.schema = Z.SCHEMA
	Z.db = ZenithDB

	if type(ZenithCharDB) ~= "table" or ZenithCharDB.schema ~= Z.SCHEMA then
		ZenithCharDB = { schema = Z.SCHEMA }
	end
	local c = ZenithCharDB
	if type(c.segments) ~= "table" then c.segments = {} end
	if type(c.records) ~= "table" then c.records = {} end
	Z.char = c

	if Z.InitCombatData then Z:InitCombatData() end
end

-- Le client 3.3.5 ne lit que les fichiers présents à son lancement : un addon mis à
-- jour pendant que le jeu tourne peut se retrouver avec un fichier manquant, même
-- après /reload. Plutôt qu'une cascade d'erreurs, Zénith le dit et reste inactif.
local function MissingFiles()
	local parts = {
		{ "Bosses.lua", Z.BOSS }, { "Spec.lua", Z.InitSpec }, { "Combat.lua", Z.InitCombat }, { "Sync.lua", Z.InitSync },
		{ "Modes.lua", Z.modes }, { "UI.lua", Z.UI }, { "Window.lua", Z.InitWindows },
		{ "Detail.lua", Z.ShowDetail }, { "Options.lua", Z.ToggleOptions },
	}
	local missing
	for i = 1, #parts do
		if not parts[i][2] then missing = (missing and (missing .. ", ") or "") .. parts[i][1] end
	end
	return missing
end

local function WarnBroken()
	Z:Print("|cffff6b5einstallation incomplète|r : le jeu n'a pas chargé " .. Z.broken .. ".")
	Z:Print("Quittez complètement le jeu puis relancez-le (un simple /reload ne suffit pas quand un addon reçoit un nouveau fichier).")
end

function Z:PLAYER_LOGIN()
	Z.broken = MissingFiles()
	if Z.broken then
		WarnBroken()
		-- Le message de connexion défile vite : il est répété une fois.
		Z:After(8, WarnBroken)
		return
	end
	Z:InitCombat()
	Z:InitSync()
	Z:InitSpec()
	Z:InitWindows()
	Z:InitMinimap()
	Z:InitToast()
	if not Z.db.welcomed then Z:After(4, function() Z:ShowWelcome() end) end
	Z:Print("version " .. Z.version .. " chargée. Tapez |cffffffff/zenith|r pour les options.")
end

function Z:PLAYER_LOGOUT()
	if Z.broken then return end
	if Z.EndCombat then Z:EndCombat(true) end
	if not Z.db.persist then
		Z.char.segments = {}
		Z.char.total = nil
	end
end

function Z:MemoryText()
	UpdateAddOnMemoryUsage()
	local kb = GetAddOnMemoryUsage(Z.name) or 0
	local players = 0
	for _ in pairs(Z.char.total.players) do players = players + 1 end
	return ("mémoire utilisée : %s Ko (%d combat(s) en mémoire, %d joueur(s) dans le total)."):format(
		Z.Num(kb), #Z.char.segments, players)
end

-- Applique un thème prédéfini (copie des couleurs pour rester modifiables).
function Z:SetTheme(key)
	for _, t in ipairs(Z.themes) do
		if t.key == key then
			local db = Z.db
			db.theme = key
			db.bg = { t.bg[1], t.bg[2], t.bg[3] }
			db.header = { t.header[1], t.header[2], t.header[3] }
			db.accent = { t.accent[1], t.accent[2], t.accent[3] }
			Z:Fire("SETTINGS")
			return
		end
	end
end

-------------------------------------------------------------------------------
-- Commandes
-------------------------------------------------------------------------------

SLASH_ZENITH1 = "/zenith"
SLASH_ZENITH2 = "/zn"

SlashCmdList["ZENITH"] = function(msg)
	if Z.broken then
		WarnBroken()
		return
	end
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" or msg == "options" or msg == "config" then
		Z:ToggleOptions()
	elseif msg == "afficher" or msg == "masquer" or msg == "basculer" then
		Z:ToggleWindows(msg == "afficher" and true or (msg == "masquer" and false or nil))
	elseif msg == "reinit" or msg == "reset" then
		Z:ResetData()
		Z:Print("données réinitialisées.")
	elseif msg == "verrou" then
		Z.db.locked = not Z.db.locked
		Z:Fire("SETTINGS")
		Z:Print(Z.db.locked and "fenêtres verrouillées." or "fenêtres déverrouillées.")
	elseif msg == "nouvelle" then
		Z:NewWindow()
	elseif msg == "bienvenue" or msg == "aide" then
		Z:ShowWelcome()
	elseif msg == "memoire" or msg == "mémoire" then
		Z:Print(Z:MemoryText())
	else
		Z:Print("commandes disponibles :")
		Z:Print("  |cffffffff/zenith|r - ouvrir les options")
		Z:Print("  |cffffffff/zenith basculer|r - afficher ou masquer les fenêtres")
		Z:Print("  |cffffffff/zenith reinit|r - effacer toutes les données")
		Z:Print("  |cffffffff/zenith verrou|r - verrouiller ou déverrouiller les fenêtres")
		Z:Print("  |cffffffff/zenith nouvelle|r - créer une fenêtre supplémentaire")
		Z:Print("  |cffffffff/zenith aide|r - revoir la présentation pour débuter")
		Z:Print("  |cffffffff/zenith memoire|r - mémoire utilisée par l'addon")
	end
end
