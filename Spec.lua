-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Spécialisation et rôle des joueurs.
-- Trois sources, de la plus sûre à la moins sûre :
--   1. les talents du joueur lui-même (exact) ;
--   2. l'inspection des membres du groupe, hors combat et à portée (exact) ;
--   3. à défaut, les sorts caractéristiques vus dans le journal de combat (déduit).

local ADDON, ns = ...
local Z = ns.Z

local GetTime, pairs, rawget = GetTime, pairs, rawget

local specOf = {}   -- guid -> numéro d'arbre de talents (1 à 3)
local specSure = {} -- guid -> heure de la dernière lecture exacte des talents
local tanking = {}  -- guid -> porte une posture de tank (présence de givre, forme d'ours)
Z.specOf = specOf

local NAMES = {
	WARRIOR = { "Armes", "Fureur", "Protection" },
	PALADIN = { "Sacré", "Protection", "Vindicte" },
	HUNTER = { "Maîtrise des bêtes", "Précision", "Survie" },
	ROGUE = { "Assassinat", "Combat", "Finesse" },
	PRIEST = { "Discipline", "Sacré", "Ombre" },
	DEATHKNIGHT = { "Sang", "Givre", "Impie" },
	SHAMAN = { "Élémentaire", "Amélioration", "Restauration" },
	MAGE = { "Arcanes", "Feu", "Givre" },
	WARLOCK = { "Affliction", "Démonologie", "Destruction" },
	DRUID = { "Équilibre", "Combat farouche", "Restauration" },
}

-- T : tank, H : soigneur, D : dégâts.
local ROLES = {
	WARRIOR = { "D", "D", "T" }, PALADIN = { "H", "T", "D" }, HUNTER = { "D", "D", "D" },
	ROGUE = { "D", "D", "D" }, PRIEST = { "H", "H", "D" }, DEATHKNIGHT = { "D", "D", "D" },
	SHAMAN = { "D", "D", "H" }, MAGE = { "D", "D", "D" }, WARLOCK = { "D", "D", "D" },
	DRUID = { "D", "D", "H" },
}
local ROLE_NAMES = { T = "tank", H = "soigneur", D = "dégâts" }
Z.ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
Z.ROLE_COORDS = {
	T = { 0, 19 / 64, 22 / 64, 41 / 64 },
	H = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
	D = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

-- Postures qui font d'un chevalier de la mort ou d'un druide farouche un tank.
local TANK_AURAS = { [48263] = "DEATHKNIGHT", [9634] = "DRUID", [5487] = "DRUID" }
Z.TANK_AURAS = TANK_AURAS

-- Sorts accessibles uniquement par un arbre de talents (rang 1 ; la comparaison se
-- fait sur le nom, identique pour tous les rangs). Liste vérifiée sort par sort.
local SIG_IDS = {
	WARRIOR = { [12294] = 1, [46924] = 1, [56638] = 1, [64976] = 1, [23881] = 2, [29801] = 2, [12809] = 3, [47498] = 3, [50227] = 3, [46968] = 3 },
	PALADIN = { [20473] = 1, [53563] = 1, [31935] = 2, [53595] = 2, [35395] = 3, [53385] = 3, [20066] = 3 },
	HUNTER = { [19577] = 1, [19574] = 1, [19506] = 2, [34490] = 2, [53209] = 2, [53301] = 3, [19386] = 3, [3674] = 3 },
	ROGUE = { [1329] = 1, [51662] = 1, [58427] = 1, [51690] = 2, [13877] = 2, [13750] = 2, [36554] = 3, [16511] = 3, [51713] = 3 },
	PRIEST = { [47540] = 1, [10060] = 1, [33206] = 1, [52795] = 1, [47753] = 1, [47788] = 2, [34861] = 2, [15473] = 3, [15286] = 3, [34914] = 3 },
	DEATHKNIGHT = { [49016] = 1, [53138] = 1, [55050] = 1, [49203] = 2, [49143] = 2, [49184] = 2, [49222] = 3, [55090] = 3, [49206] = 3 },
	SHAMAN = { [51490] = 1, [16166] = 1, [51470] = 1, [51533] = 2, [30823] = 2, [17364] = 2, [30802] = 2, [61295] = 3, [51886] = 3, [974] = 3 },
	MAGE = { [44425] = 1, [31583] = 1, [12042] = 1, [11129] = 2, [44457] = 2, [31661] = 2, [11113] = 2, [11426] = 3, [44572] = 3, [31687] = 3 },
	WARLOCK = { [48181] = 1, [30108] = 1, [59672] = 2, [30146] = 2, [50796] = 3, [30283] = 3, [17962] = 3 },
	DRUID = { [24907] = 1, [48505] = 1, [50516] = 1, [24858] = 1, [24932] = 2, [33876] = 2, [33878] = 2, [33891] = 3, [48438] = 3, [18562] = 3 },
}
local SIG, SIG_CLASS = {}, {} -- nom du sort -> arbre ; nom du sort -> classe
for class, ids in pairs(SIG_IDS) do
	for id, idx in pairs(ids) do
		local name = GetSpellInfo(id)
		if name and not SIG[name] then
			SIG[name], SIG_CLASS[name] = idx, class
		end
	end
end
SIG_IDS = nil

-- Appelé pour chaque sort lancé par un membre du groupe : doit rester très léger.
function Z.SpecHint(guid, name)
	local idx = SIG[name]
	if idx and not specSure[guid] then
		local r = Z.roster[guid]
		if r and r.class == SIG_CLASS[name] then specOf[guid] = idx end
	end
end

function Z.SetTanking(guid, on)
	tanking[guid] = on or nil
end

-- Un joueur vient de changer de double spécialisation : ses talents sont à relire.
function Z.SpecChanged(guid)
	specSure[guid] = nil
	specOf[guid] = nil
	if guid == Z.playerGUID then Z:ReadOwnSpec() end
end

-- Renvoie arbre, nom, icône, rôle ("T", "H", "D") ; p : fiche enregistrée du joueur.
function Z:SpecInfo(guid, class, p)
	local idx = specOf[guid] or (p and p.sp)
	local names = class and NAMES[class]
	if not idx or not names then return nil end
	local role = ROLES[class][idx]
	if tanking[guid] or (p and p.ro == "T" and not specOf[guid]) then
		if class == "DEATHKNIGHT" or (class == "DRUID" and idx == 2) then role = "T" end
	end
	local icons = Z.db.specIcons and Z.db.specIcons[class]
	return idx, names[idx], icons and icons[idx] or nil, role
end

function Z.RoleName(role)
	return ROLE_NAMES[role]
end

-- Lit les trois arbres (les siens, ou ceux du joueur inspecté) et retient le plus fourni.
local function ReadTabs(guid, class, inspect)
	if not guid or not class then return false end
	local group = GetActiveTalentGroup(inspect)
	local prefix = class:lower()
	local best, bestPts, total, read = nil, -1, 0, {}
	for i = 1, 3 do
		local _, icon, points, background = GetTalentTabInfo(i, inspect, false, group)
		-- Le fond de l'arbre, jamais traduit, commence par la classe (« ShamanRestoration »,
		-- « DruidRestoration ») : des talents d'une autre classe sont ceux d'un autre joueur,
		-- reçus en retard ou demandés entre-temps par un autre addon.
		if type(background) == "string" and background ~= ""
			and background:lower():sub(1, #prefix) ~= prefix then return false end
		points = points or 0
		total = total + points
		if points > bestPts then best, bestPts = i, points end
		if type(icon) == "string" and icon ~= "" then read[i] = icon end
	end
	if total <= 0 then return false end
	local icons = Z.db.specIcons[class]
	if not icons then
		icons = {}
		Z.db.specIcons[class] = icons
	end
	for i, icon in pairs(read) do icons[i] = icon end
	specOf[guid] = best
	specSure[guid] = GetTime()
	return true
end

function Z:ReadOwnSpec()
	local guid = Z.playerGUID or UnitGUID("player")
	local _, class = UnitClass("player")
	if ReadTabs(guid, class, false) then Z:Fire("SPEC") end
end

-------------------------------------------------------------------------------
-- Inspection des membres du groupe
-------------------------------------------------------------------------------

local pending          -- inspection en attente de réponse : { guid, unit, t }
local lastNotify       -- dernier joueur inspecté, par Zénith ou par un autre addon
local answered = true  -- la dernière inspection demandée a reçu sa réponse
local mixed = false    -- deux joueurs inspectés coup sur coup : la prochaine réponse est ambiguë
local lastTry = {}     -- guid -> heure du dernier essai
local REFRESH = 900    -- les talents sont relus au bout d'un quart d'heure
local RETRY = 30

local function TankAuraCheck(unit, guid, class)
	if class ~= "DEATHKNIGHT" and class ~= "DRUID" then return end
	local on = false
	for id, c in pairs(TANK_AURAS) do
		if c == class then
			local name = GetSpellInfo(id)
			if name and UnitBuff(unit, name) then on = true end
		end
	end
	tanking[guid] = on or nil
end

-- Retient l'arbre le plus fourni à partir du nombre de points par arbre.
local function FromPoints(guid, n1, n2, n3)
	if type(n1) ~= "number" or type(n2) ~= "number" or type(n3) ~= "number" then return false end
	if n1 + n2 + n3 <= 0 then return false end
	local idx = 1
	if n2 > n1 and n2 >= n3 then idx = 2 elseif n3 > n1 and n3 > n2 then idx = 3 end
	if specOf[guid] ~= idx or not specSure[guid] then
		specOf[guid] = idx
		specSure[guid] = GetTime()
		Z:Fire("SPEC")
	end
	return true
end

-- LibGroupTalents, quand un autre addon l'a chargée (WeakAuras, Details, Skada...),
-- connaît déjà les talents du groupe : elle les échange entre joueurs par
-- messages d'addon et gère sa propre file d'inspection.
local function AskLibrary(guid)
	local lgt = Z.lgt
	if not lgt then return false end
	local ok, _, n1, n2, n3 = pcall(lgt.GetGUIDTalentSpec, lgt, guid)
	return ok and FromPoints(guid, n1, n2, n3)
end

local function InspectTick()
	-- Jamais en combat : l'inspection est un service, pas une urgence.
	if Z.current or InCombatLockdown() then return end
	local now = GetTime()
	if pending and now - pending.t < 3 then return end
	pending = nil
	-- La fenêtre d'inspection du joueur a la priorité.
	local frame = rawget(_G, "InspectFrame")
	local busy = frame and frame.IsShown and frame:IsShown()
	for guid, r in pairs(Z.roster) do
		local unit = r.unit
		if unit and guid ~= Z.playerGUID then
			TankAuraCheck(unit, guid, r.class)
			local sure = specSure[guid]
			if not sure or now - sure > REFRESH then
				if Z.lgt then
					-- La bibliothèque inspecte déjà : deux files concurrentes se gêneraient.
					AskLibrary(guid)
				elseif not busy and now - (lastTry[guid] or -RETRY) >= RETRY
					and UnitIsVisible(unit) and UnitIsConnected(unit)
					and not UnitCanAttack("player", unit) and CanInspect(unit) then
					lastTry[guid] = now
					pending = { guid = guid, unit = unit, t = now }
					NotifyInspect(unit)
					return
				end
			end
		end
	end
end

local function InspectReady()
	local ours = pending
	pending = nil
	-- Le jeu ne dit pas à qui appartiennent les talents reçus : ce sont ceux du
	-- dernier joueur inspecté, que la demande vienne de Zénith, du joueur ou d'un
	-- autre addon. Une inspection lancée par ailleurs profite donc aussi à Zénith.
	-- Si un autre joueur a été inspecté avant que la réponse précédente n'arrive,
	-- celle-ci peut concerner l'un comme l'autre : elle est ignorée.
	local ambiguous = mixed
	mixed, answered = false, true
	local guid = lastNotify or (ours and ours.guid)
	if ambiguous or not guid or guid == Z.playerGUID then return end
	local r = Z.roster[guid]
	if not r or not r.class then return end
	if r.unit and UnitGUID(r.unit) ~= guid then return end
	if ReadTabs(guid, r.class, true) then Z:Fire("SPEC") end
	-- On ne libère l'inspection que si elle venait de Zénith : celle d'un autre
	-- addon ou du joueur est peut-être encore en cours d'utilisation.
	if ours and ours.guid == guid and not Z.lgt then
		local frame = rawget(_G, "InspectFrame")
		if not (frame and frame.IsShown and frame:IsShown()) then ClearInspectPlayer() end
	end
end

function Z:InitSpec()
	-- Avant 1.10.4, une inspection mal attribuée pouvait ranger les icônes d'une classe
	-- sous une autre (un chaman Restauration affiché avec l'icône du druide) : elles
	-- sont relues une fois.
	if type(Z.db.specIcons) ~= "table" or Z.db.specIconsRev ~= 1 then Z.db.specIcons = {} end
	Z.db.specIconsRev = 1
	-- Profiter aussi des inspections lancées par le joueur ou par d'autres addons.
	hooksecurefunc("NotifyInspect", function(unit)
		local guid = unit and UnitGUID(unit) or nil
		if not answered and guid ~= lastNotify then mixed = true end
		lastNotify, answered = guid, false
	end)
	Z.INSPECT_TALENT_READY = InspectReady
	Z.PLAYER_TALENT_UPDATE = Z.ReadOwnSpec
	Z.ACTIVE_TALENT_GROUP_CHANGED = Z.ReadOwnSpec
	Z:RegisterEvent("INSPECT_TALENT_READY")
	Z:RegisterEvent("PLAYER_TALENT_UPDATE")
	Z:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	Z:ReadOwnSpec()
	-- À la connexion, les talents ne sont pas toujours déjà disponibles.
	Z:After(6, function()
		if not specSure[Z.playerGUID] then Z:ReadOwnSpec() end
	end)
	local _, class = UnitClass("player")
	TankAuraCheck("player", Z.playerGUID, class)

	local LS = rawget(_G, "LibStub")
	if type(LS) == "table" and LS.GetLibrary then
		local ok, lgt = pcall(LS.GetLibrary, LS, "LibGroupTalents-1.0", true)
		if ok and type(lgt) == "table" and type(lgt.GetGUIDTalentSpec) == "function" then
			Z.lgt = lgt
			if type(lgt.RegisterCallback) == "function" then
				pcall(lgt.RegisterCallback, {}, "LibGroupTalents_Update", function(_, guid, _, _, n1, n2, n3)
					if type(guid) == "string" then FromPoints(guid, n1, n2, n3) end
				end)
			end
		end
	end
	Z:Every(2, InspectTick)
end

-- Les joueurs partis du groupe ne sont plus suivis.
function Z.SpecForget(guid)
	specOf[guid], specSure[guid], tanking[guid], lastTry[guid] = nil, nil, nil, nil
end
