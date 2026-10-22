-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Analyse du journal de combat (client 3.3.5)
-- Segments, familiers, absorptions, morts, records, réparation du journal.

local ADDON, ns = ...
local Z = ns.Z

local SpecHint, SetTanking, TANK_AURAS = Z.SpecHint, Z.SetTanking, Z.TANK_AURAS

local band = bit.band
local GetTime, floor, max, min, pairs, next, wipe = GetTime, math.floor, math.max, math.min, pairs, next, wipe
local tinsert, tremove = table.insert, table.remove
local UnitGUID, UnitName, UnitClass, UnitExists = UnitGUID, UnitName, UnitClass, UnitExists
local UnitHealth, UnitHealthMax, UnitAffectingCombat = UnitHealth, UnitHealthMax, UnitAffectingCombat
local GetNumRaidMembers, GetNumPartyMembers = GetNumRaidMembers, GetNumPartyMembers

-- Drapeaux du journal de combat
local GROUP = 0x7 -- moi, groupe, raid
local MINE = 0x1
local HOSTILE_OR_NEUTRAL = 0x60
local TYPE_PLAYER = 0x400
local HOSTILE = 0x40

local BUCKET = 3 -- secondes par tranche de chronologie
Z.BUCKET = BUCKET
local LOG_SIZE = 25 -- événements gardés avant une mort
local ACTIVE_GAP = 3.5

local PET_KEY, ABSORB_KEY = 1e7, 2e7
local MELEE = "Attaque automatique"
local UNKNOWN = "Inconnu"
local ENVIRONMENT = "Environnement"
-- Identifiants fictifs (inférieurs à 1, donc jamais confondus avec un vrai sort).
local ENV_IDS = { FALLING = 0.1, DROWNING = 0.2, FIRE = 0.3, LAVA = 0.4, SLIME = 0.5, FATIGUE = 0.6 }
local ENV_NAMES = {
	FALLING = "Chute", DROWNING = "Noyade", FIRE = "Feu", LAVA = "Lave",
	SLIME = "Gelée", FATIGUE = "Fatigue",
}

-- Boucliers d'absorption.
-- pri  : ordre de consommation appliqué par le serveur (le plus petit absorbe en
--        premier ; à égalité, le bouclier posé le plus tôt). Les gardes passent
--        avant tout, puis Bouclier saint, Egide divine, Barrière de glace,
--        Sacrifice, Carapace anti-magie, enfin les autres par ancienneté.
-- mask : écoles de dégâts que le bouclier peut absorber.
-- dur  : durée maximale (un bouclier dont la disparition n'a pas été vue expire).
-- cap  : capacité typique au niveau 80, affinée ensuite par observation.
local ALL, MAGIC = 127, 126
local SHIELDS = {}
local function Shield(ids, pri, mask, dur, cap)
	for i = 1, #ids do
		SHIELDS[ids[i]] = { pri = pri, mask = mask, dur = dur, cap = (i == #ids) and cap or nil }
	end
end
-- Essences des jumelles Val'kyr : mécanique de boss, jamais créditée à un joueur.
Shield({ 65686, 67222, 67223, 67224 }, 1, 4, 86400)
Shield({ 65684, 67176, 67177, 67178 }, 1, 32, 86400)
for _, id in ipairs({ 65686, 67222, 67223, 67224, 65684, 67176, 67177, 67178 }) do SHIELDS[id].ignore = true end
Shield({ 6143, 8461, 8462, 10177, 28609, 32796, 43012 }, 2, 16, 30, 5200) -- Gardien de givre
Shield({ 543, 8457, 8458, 10223, 10225, 27128, 43010 }, 3, 4, 30, 5200) -- Gardien de feu
Shield({ 6229, 11739, 11740, 28610, 47890, 47891 }, 4, 32, 30, 3300) -- Gardien de l'ombre
Shield({ 58597 }, 5, ALL, 6, 4400) -- Bouclier saint
Shield({ 28527 }, 6, ALL, 15, 1000) -- Fleur gangrenée
Shield({ 47753 }, 7, ALL, 12) -- Egide divine (capacité déduite du soin critique)
Shield({ 11426, 13031, 13032, 13033, 27134, 33405, 43038, 43039 }, 8, ALL, 60, 6500) -- Barrière de glace
Shield({ 7812, 19438, 19440, 19441, 19442, 19443, 27273, 47985, 47986 }, 9, ALL, 30, 8350) -- Sacrifice
Shield({ 48707 }, 10, MAGIC, 5) -- Carapace anti-magie (50 % des PV max)
Shield({ 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, 25217, 25218, 48065, 48066 }, 20, ALL, 30, 10000) -- Mot de pouvoir : Bouclier
Shield({ 1463, 8494, 8495, 10191, 10192, 10193, 27131, 43019, 43020 }, 20, ALL, 60, 4500) -- Bouclier de mana
Shield({ 50461 }, 20, MAGIC, 10) -- Zone anti-magie
Shield({ 51052 }, 20, MAGIC, 10)
Shield({ 62606 }, 20, 1, 10, 1600) -- Défense sauvage
Shield({ 64413 }, 20, ALL, 8) -- Val'anyr (capacité déduite des soins)
Shield({ 70845 }, 20, ALL, 10) -- Stoïcisme, guerrier protection T10 (20 % des PV max)
Shield({ 71586 }, 21, ALL, 10, 6400) -- Peau durcie
Shield({ 57350 }, 20, ALL, 6, 1500)
Shield({ 60218 }, 20, ALL, 10, 4000)
Shield({ 55019 }, 20, ALL, 12, 1100)
Shield({ 54808 }, 20, ALL, 12, 1100)
Shield({ 29506 }, 20, ALL, 20, 900)
Shield({ 53915 }, 20, 32, 120, 5100)
Shield({ 53914 }, 20, 8, 120, 5100)
Shield({ 53913 }, 20, 16, 120, 5100)
Shield({ 53911 }, 20, 4, 120, 5100)
Shield({ 53910 }, 20, 64, 120, 5100)
local STACKING = { [47753] = 0.30, [64413] = 0.15 } -- part du soin convertie en bouclier
local STACK_CAP = { [47753] = 10000, [64413] = 20000 }
local HP_RATIO = { [48707] = 0.5, [70845] = 0.2 } -- capacité = part des PV max de la cible

-- Talents passifs qui absorbent sans jamais poser d'aura visible dans le journal :
-- l'absorption est créditée au joueur protégé lui-même, sous le nom du talent.
local PASSIVE_ABSORB = {
	DEATHKNIGHT = { 52286, 49497 }, -- Volonté de la nécropole (physique), Déviation de sort (magie)
	PALADIN = { 66233, 66233 },     -- Défenseur ardent
	ROGUE = { 31230, 31230 },       -- Trompe-la-mort
	WARLOCK = { 25228, 25228 },     -- Lien spirituel
}
local SELF_ABSORB = "Absorption personnelle (origine inconnue)"
local passiveName = {} -- identifiant de talent -> nom affiché par le client
local AUTO_LEARN = 3 -- coïncidences requises avant de reconnaître un bouclier inconnu

-- Effets permanents (auras, armures) : leurs dégâts ne comptent pas comme activité.
local PASSIVE = {}
for _, id in ipairs({
	7294, 10298, 10299, 10300, 10301, 27150, 54043, -- Aura de vindicte
	34913, 43043, 43044, -- Armure de la fournaise
	26364, 26365, 26366, 26367, 26370, 26363, 26371, 26372, 49278, 49279, -- Bouclier de foudre
	2947, 8316, 8317, 11770, 11771, 27269, 47983, -- Bouclier de feu
}) do PASSIVE[id] = true end

-- Sorts que le journal découpe en deux identifiants (main gauche, etc.).
local MERGE = {
	[32175] = 17364, [32176] = 17364, -- Frappe-tempête (main droite, main gauche)
	[27576] = 5374,                   -- Mutilation (main gauche)
}

local MARK_OF_BLOOD, MARK_HEAL = 49005, 50424

-- État de session (non sauvegardé)
local roster = {}  -- guid -> { name, class, unit }
local pets = {}    -- guid du familier -> guid du maître
local shields = {} -- guid de la cible -> liste de boucliers actifs
local dlog = {}    -- guid -> tampon circulaire des derniers événements
local playerGUID, playerName
local lastEvent, lastCLEU, lastFix, castAt = 0, 0, 0, nil
local lastEndAt -- fin du dernier combat clos, gardé ou non (heure GetTime())
local lastTs = 0 -- horodatage du dernier événement du journal (échelle des boucliers)

-- Alignement des durées sur les coéquipiers (synchronisation de groupe).
local SYNC_EARLY = 30 -- avance maximale du début d'un combat sur annonce d'un coéquipier
local SYNC_LATE = 10  -- prolongation maximale de sa fin
-- Le délai d'acheminement retarde les heures annoncées : un écart plus petit que
-- ce seuil n'est que de la latence et ne modifie pas la durée.
local SYNC_SLACK = 1
local NOW = 0 -- heure de l'événement en cours, lue une seule fois par événement
local lastRescan = 0
local deathAt = {} -- guid -> heure de la dernière mort (session)
local learned = {}  -- guid du lanceur -> { sort = capacité observée }
local lastHeal = {} -- guid de la cible -> { guid du soigneur = { t, a } }
local marks = {}    -- guid de l'ennemi marqué -> guid du chevalier de la mort
local noOwner = {}  -- guid d'un familier sans maître trouvé -> heure de l'essai
local bossChecked = {} -- guid d'ennemi déjà comparé à la liste des boss (par combat)
local cidName = {}     -- identifiant de boss -> nom affiché par le client (session)
local pendingBoss      -- boss annoncé avant le premier coup (DBM ou coéquipier) : { name, t, id, dbm }
local lastPull = -100  -- heure du dernier engagement de boss connu (doublons ignorés)
local reflects = {}    -- guid de l'ennemi -> sort renvoyé et joueur qui l'a renvoyé
local lastRemoved = {} -- guid de la cible -> dernière amélioration retirée (détection de boucliers inconnus)
local autoSeen = {}    -- sort -> nombre de fois où son retrait a précédé une absorption inexpliquée
local petCount = 0

local byName = {} -- nom -> guid des membres actuels du groupe
Z.roster, Z.rosterByName = roster, byName
Z.logFixes = 0

-------------------------------------------------------------------------------
-- Segments
-------------------------------------------------------------------------------

local function NewSegment()
	return { dur = 0, stamp = time(), players = {}, enemies = {}, deaths = {} }
end

function Z:InitCombatData()
	local c = Z.char
	-- Les valeurs basées sur GetTime() ne survivent pas à une reconnexion.
	local function Clean(seg)
		seg.active = nil
		seg.start = nil
		seg.t0, seg.t1 = nil, nil
		seg.dur = seg.dur or 1
		seg.players = seg.players or {}
		seg.enemies = seg.enemies or {}
		seg.deaths = seg.deaths or {}
		for _, p in pairs(seg.players) do p.last = nil end
	end
	for i = #c.segments, 1, -1 do
		local seg = c.segments[i]
		if type(seg) ~= "table" then
			tremove(c.segments, i)
		else
			Clean(seg)
			seg.name = seg.name or "Combat"
		end
	end
	if type(c.total) ~= "table" then c.total = NewSegment() end
	if type(c.tries) ~= "table" then c.tries = {} end
	Clean(c.total)
	c.total.name = "Total"
	Z.current = nil
end

function Z:ResetData()
	Z.current = nil
	Z.char.segments = {}
	Z.char.total = NewSegment()
	Z.char.total.name = "Total"
	Z.char.tries = {}
	wipe(dlog)
	wipe(deathAt)
	Z:Fire("RESET")
end

-- Résout une référence de segment : "current", "total" ou la table elle-même.
function Z:GetSegment(ref)
	if ref == "total" then return Z.char.total end
	if type(ref) == "table" then
		local segs = Z.char.segments
		for i = 1, #segs do
			if segs[i] == ref then return ref end
		end
	end
	return Z.current or Z.char.segments[1]
end

function Z:SegDuration(seg)
	if seg == Z.char.total then
		local cur = Z.current
		return max(1, seg.dur + (cur and (GetTime() - cur.t0) or 0))
	elseif seg.active then
		return max(1, GetTime() - seg.t0)
	end
	return max(1, seg.dur or 1)
end

function Z:SegName(seg)
	if seg == Z.char.total then return "Total" end
	if seg.active then return seg.boss or "Combat en cours" end
	return seg.name or "Combat"
end

-------------------------------------------------------------------------------
-- Effectif du groupe et familiers
-------------------------------------------------------------------------------

local RAID, RAIDPET, RAIDTARGET, PARTY, PARTYPET, PARTYTARGET = {}, {}, {}, {}, {}, {}
for i = 1, 40 do
	RAID[i], RAIDPET[i], RAIDTARGET[i] = "raid" .. i, "raid" .. i .. "pet", "raid" .. i .. "target"
end
for i = 1, 4 do
	PARTY[i], PARTYPET[i], PARTYTARGET[i] = "party" .. i, "party" .. i .. "pet", "party" .. i .. "target"
end

Z.RAID, Z.PARTY = RAID, PARTY

local function AddUnit(unit, petUnit)
	local guid = UnitGUID(unit)
	if not guid then return end
	local r = roster[guid]
	if not r then
		r = {}
		roster[guid] = r
	end
	local _, class = UnitClass(unit)
	r.name, r.class, r.unit = UnitName(unit), class, unit
	r.hpT = nil
	if r.name then byName[r.name] = guid end
	local pg = UnitGUID(petUnit)
	if pg and not pets[pg] then
		pets[pg] = guid
		petCount = petCount + 1
	elseif pg then
		pets[pg] = guid
	end
end

function Z:UpdateRoster()
	for _, r in pairs(roster) do r.unit = nil end
	wipe(byName)
	AddUnit("player", "pet")
	local n = GetNumRaidMembers()
	if n > 0 then
		for i = 1, n do AddUnit(RAID[i], RAIDPET[i]) end
	else
		for i = 1, GetNumPartyMembers() do AddUnit(PARTY[i], PARTYPET[i]) end
	end
	-- Les joueurs partis ne sont plus suivis : leurs tampons de session sont libérés.
	for guid, r in pairs(roster) do
		if not r.unit then
			roster[guid] = nil
			Z.SpecForget(guid)
			dlog[guid] = nil
			deathAt[guid] = nil
			learned[guid] = nil
		end
	end
end

function Z:IsGrouped()
	return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

local function GroupInCombat()
	if UnitAffectingCombat("player") or UnitAffectingCombat("pet") then return true end
	local n = GetNumRaidMembers()
	if n > 0 then
		for i = 1, n do
			if UnitAffectingCombat(RAID[i]) then return true end
		end
	else
		for i = 1, GetNumPartyMembers() do
			if UnitAffectingCombat(PARTY[i]) then return true end
		end
	end
	return false
end

-- Dernier recours pour un familier : son infobulle indique "Familier de X".
local scanTip, ownerPatterns
local function TooltipOwner(guid)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "ZenithScanTip", nil, "GameTooltipTemplate")
		ownerPatterns = {}
		local i = 1
		while true do
			local title = rawget(_G, "UNITNAME_SUMMON_TITLE" .. i)
			if type(title) ~= "string" or title == "%s" or not title:find("%%s") then break end
			ownerPatterns[#ownerPatterns + 1] = title
			i = i + 1
		end
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:ClearLines()
	scanTip:SetHyperlink("unit:" .. guid)
	local line = rawget(_G, "ZenithScanTipTextLeft2")
	local text = line and line:GetText()
	if not text or text == "" then return nil end
	for og, r in pairs(roster) do
		if r.unit and r.name then
			for i = 1, #ownerPatterns do
				if ownerPatterns[i]:format(r.name) == text then return og end
			end
		end
	end
	return nil
end

-- Renvoie le maître d'une source : guid, nom, nom du familier (ou nil).
local function Owner(guid, name, flags)
	if band(flags, TYPE_PLAYER) ~= 0 then return guid, name end
	local og = pets[guid]
	local hops = 0
	-- Un élémentaire invoqué par un totem remonte jusqu'au chaman.
	while og and pets[og] and hops < 3 do
		og = pets[og]
		hops = hops + 1
	end
	if og then
		local r = roster[og]
		if r then return og, r.name, name end
	end
	if band(flags, MINE) ~= 0 and playerGUID then return playerGUID, playerName, name end
	if not guid then return nil end
	-- Familier du groupe encore inconnu (invoqué hors de portée du journal).
	local now = GetTime()
	local tried = noOwner[guid]
	if tried and now >= tried and now - tried < 5 then return nil end
	if now - lastRescan > 2 then
		lastRescan = now
		Z:UpdateRoster()
		og = pets[guid]
		local r = og and roster[og]
		if r then return og, r.name, name end
	end
	local ok, found = pcall(TooltipOwner, guid)
	if ok and found and roster[found] then
		pets[guid] = found
		petCount = petCount + 1
		return found, roster[found].name, name
	end
	noOwner[guid] = now
	return nil
end

-- Indicateurs de fiabilité d'un segment.
local function Quality(seg)
	local q = seg.q
	if not q then
		q = { pet = 0, abs = 0, fix = 0 }
		seg.q = q
	end
	return q
end

local function GetP(seg, guid, name)
	local p = seg.players[guid]
	if not p then
		local r = roster[guid]
		local class = r and r.class
		if not class and GetPlayerInfoByGUID then
			local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
			if ok then class = c end
		end
		p = {
			name = name or UNKNOWN, class = class,
			dmg = 0, taken = 0, heal = 0, over = 0, absorb = 0, ff = 0,
			int = 0, disp = 0, deaths = 0, act = 0,
			tAbs = 0, tBlk = 0, tRes = 0, -- dégâts subis atténués : absorbés, bloqués, résistés
			spells = {}, heals = {}, takenBy = {}, targets = {}, healed = {},
		}
		seg.players[guid] = p
	elseif not p.class then
		local r = roster[guid]
		if r then p.class = r.class end
	end
	return p
end

local function Active(p, now)
	local d = now - (p.last or 0)
	if d >= 0 and d < ACTIVE_GAP then
		p.act = p.act + d
	else
		p.act = p.act + 1
	end
	p.last = now
end

local function Timeline(seg, p, field, now, amount)
	local b = floor((now - seg.start) / BUCKET) + 1
	local t = p[field]
	if not t then
		t = {}
		p[field] = t
	end
	for i = #t + 1, b - 1 do t[i] = 0 end
	t[b] = (t[b] or 0) + amount
end

-------------------------------------------------------------------------------
-- Journal des morts
-------------------------------------------------------------------------------

-- Points de vie maximum d'un membre du groupe. Ils changent rarement : la valeur
-- est gardée cinq secondes au lieu d'être redemandée au client à chaque coup.
local function HpMax(r, now)
	if not r or not r.unit then return nil end
	if not r.hpM or now - (r.hpT or 0) > 5 or now < (r.hpT or 0) then
		r.hpM, r.hpT = UnitHealthMax(r.unit) or 0, now
	end
	return r.hpM
end

local function LogPush(guid, now, amount, spell, src, hpMax)
	local L = dlog[guid]
	if not L then
		L = { pos = 0 }
		dlog[guid] = L
	end
	local pos = L.pos % LOG_SIZE + 1
	L.pos = pos
	local e = L[pos]
	if not e then
		e = {}
		L[pos] = e
	end
	local hp = 0
	local r = roster[guid]
	if r and r.unit then
		local m = hpMax or HpMax(r, now) or 0
		if m > 0 then
			hp = floor((UnitHealth(r.unit) or 0) / m * 100 + 0.5)
			if hp > 100 then hp = 100 end
		end
	end
	e.t, e.a, e.s, e.f, e.hp = now, amount, spell, src, hp
end

-- Derniers événements avant une mort, limités au combat en cours.
local function LogSnapshot(guid, now, since)
	local L = dlog[guid]
	local out = {}
	if not L then return out end
	for i = 1, LOG_SIZE do
		local e = L[(L.pos + i - 1) % LOG_SIZE + 1]
		if e and e.t and e.t > 0 and now - e.t <= 20 and e.t >= since then
			out[#out + 1] = { t = e.t - now, a = e.a, s = e.s, f = e.f, hp = e.hp }
			e.t = 0
		end
	end
	return out
end

-------------------------------------------------------------------------------
-- Début et fin de combat
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Améliorations et affaiblissements : temps d'effet par combat
-------------------------------------------------------------------------------
-- buffs   : améliorations portées par le joueur ;
-- debuffs : affaiblissements qu'il a subis ;
-- dots    : affaiblissements qu'il a posés sur des ennemis (actif = sur au moins une cible).
-- Chaque entrée : n (nom), up (secondes d'effet), c (applications) ; t et on ne
-- servent que pendant le combat et sont effacés à sa fin.

local trackAuras = true
local AURA_FIELDS = { "buffs", "debuffs", "dots" }
local AURA_IGNORE = {}
for _, id in ipairs({ 57819, 57820, 57821, 57822, 57940, 72968, 57723, 57724 }) do AURA_IGNORE[id] = true end

local function AuraOn(seg, guid, pname, field, id, name, now)
	local p = GetP(seg, guid, pname)
	local t = p[field]
	if not t then
		t = {}
		p[field] = t
	end
	local a = t[id]
	if not a then
		a = { n = name or UNKNOWN, up = 0, c = 0 }
		t[id] = a
	end
	a.c = a.c + 1
	local on = (a.on or 0) + 1
	a.on = on
	if on == 1 then a.t = now end
end

local function AuraOff(seg, guid, field, id, now)
	local p = seg.players[guid]
	local t = p and p[field]
	local a = t and t[id]
	if not a or not a.t then return end
	local on = (a.on or 1) - 1
	if on <= 0 then
		if now > a.t then a.up = a.up + (now - a.t) end
		a.t, a.on = nil, nil
	else
		a.on = on
	end
end

-- Au début du combat : ce que chaque membre du groupe porte déjà.
local function ScanAuras(seg, now)
	for guid, r in pairs(roster) do
		local unit = r.unit
		if unit then
			for i = 1, 40 do
				local name, _, _, _, _, _, _, _, _, _, id = UnitBuff(unit, i)
				if not name then break end
				if id then
					if not AURA_IGNORE[id] then AuraOn(seg, guid, r.name, "buffs", id, name, now) end
					if TANK_AURAS[id] == r.class then SetTanking(guid, true) end
				end
			end
			for i = 1, 40 do
				local name, _, _, _, _, _, _, _, _, _, id = UnitDebuff(unit, i)
				if not name then break end
				if id and not AURA_IGNORE[id] then AuraOn(seg, guid, r.name, "debuffs", id, name, now) end
			end
		end
	end
end

-- À la fin du combat : les effets encore actifs sont comptés jusqu'au dernier événement.
local function CloseAuras(seg, now)
	for _, p in pairs(seg.players) do
		for i = 1, 3 do
			local t = p[AURA_FIELDS[i]]
			if t then
				for _, a in pairs(t) do
					if a.t and now > a.t then a.up = a.up + (now - a.t) end
					a.t, a.on = nil, nil
				end
			end
		end
	end
end

-- Secondes d'effet d'une aura, combat en cours compris.
function Z.AuraUp(seg, a)
	if a.t and seg.active then
		local extra = GetTime() - a.t
		if extra > 0 then return a.up + extra end
	end
	return a.up
end

local function DiffLabel()
	local _, itype, diff, _, _, dyn, isDyn = GetInstanceInfo()
	if itype == "raid" then
		local size = (diff == 2 or diff == 4) and 25 or 10
		local heroic = diff == 3 or diff == 4 or (isDyn and dyn == 1)
		return size .. (heroic and " H" or " N")
	elseif itype == "party" then
		return diff == 2 and "5 H" or "5 N"
	elseif itype == "pvp" or itype == "arena" then
		return "JcJ"
	end
	return "Extérieur"
end

local function DiffLabelSafe()
	local ok, label = pcall(DiffLabel)
	return ok and label or "?"
end

local function Start(now, who, spell, target)
	local seg = NewSegment()
	seg.active = true
	seg.tl = true
	-- start : origine de la chronologie, fixe. t0 : début retenu pour la durée, qu'un
	-- coéquipier peut avancer (Sync.lua) ; t1 : fin. Heures GetTime(), non sauvegardées.
	seg.start, seg.t0 = now, now
	seg.pullBy, seg.pullSpell, seg.pullTarget = who, spell, target
	local inInstance, itype = IsInInstance()
	if inInstance and (itype == "pvp" or itype == "arena") then
		seg.pvp = itype
		seg.zone = GetInstanceInfo()
	end
	Z.current = seg
	tinsert(Z.char.segments, 1, seg)
	lastEvent = now
	if trackAuras then ScanAuras(seg, now) end
	local pb = pendingBoss
	if pb and now - pb.t < 10 and not seg.pvp then
		Z.SetBoss(seg, pb.name, pb.dbm)
		if pb.dbm then
			seg.dbmId = pb.id
		elseif pb.id then
			-- Relayé par un coéquipier : la créature a été vue dans son journal.
			if Z.ENC[pb.id] then seg.enc = Z.ENC[pb.id] else seg.bossId = pb.id end
		end
	end
	pendingBoss = nil
	Z:Fire("COMBAT_START", seg)
	return seg
end

-- Nombre de membres du groupe morts, et effectif.
local function GroupDead()
	local dead, n = 0, 0
	local raid = GetNumRaidMembers()
	if raid > 0 then
		for i = 1, raid do
			n = n + 1
			if UnitIsDeadOrGhost(RAID[i]) then dead = dead + 1 end
		end
	else
		n = 1
		if UnitIsDeadOrGhost("player") then dead = 1 end
		for i = 1, GetNumPartyMembers() do
			n = n + 1
			if UnitIsDeadOrGhost(PARTY[i]) then dead = dead + 1 end
		end
	end
	return dead, n
end

local pruneBuf = {}
local function ByKept(a, b) return a.v > b.v end

-- Ramène une table { nom = valeur } à `keep` entrées, les plus importantes,
-- dès qu'elle dépasse `cap`. `value` extrait la valeur d'une entrée.
local function Prune(map, cap, keep, value)
	if not map then return end
	local n = 0
	for _ in pairs(map) do n = n + 1 end
	if n <= cap then return end
	local i = 0
	for k, v in pairs(map) do
		i = i + 1
		local e = pruneBuf[i]
		if not e then
			e = {}
			pruneBuf[i] = e
		end
		e.k, e.v = k, value and value(k, v) or v
	end
	for j = i + 1, #pruneBuf do pruneBuf[j] = nil end
	table.sort(pruneBuf, ByKept)
	for j = keep + 1, i do map[pruneBuf[j].k] = nil end
	for j = #pruneBuf, 1, -1 do pruneBuf[j] = nil end
end

local function FoeValue(_, f) return f.d + f.h end
local function PlayerValue(guid, p)
	-- Les membres actuels du groupe ne sont jamais retirés du total.
	if roster[guid] then return math.huge end
	return p.dmg + p.heal + p.absorb + p.taken
end

-- Le total accumule tout depuis la dernière réinitialisation : sans limite, il
-- finirait par contenir chaque monstre et chaque joueur croisés pendant des mois.
local function PruneTotal(total)
	Prune(total.enemies, 400, 300)
	Prune(total.foes, 400, 300, FoeValue)
	Prune(total.players, 300, 250, PlayerValue)
	if total.eclass then
		local n = 0
		for _ in pairs(total.eclass) do n = n + 1 end
		if n > 400 then total.eclass = nil end
	end
	for guid, p in pairs(total.players) do
		if roster[guid] then
			Prune(p.targets, 250, 200)
			Prune(p.healed, 250, 200)
			Prune(p.healIn, 250, 200)
			Prune(p.absIn, 250, 200)
		end
	end
end
Z.PruneTotal = PruneTotal

local function TopFoe(seg)
	local best, bestV = nil, 0
	if seg.foes then
		for name, f in pairs(seg.foes) do
			if f.d > bestV then best, bestV = name, f.d end
		end
	end
	return best
end

local function TopEnemy(seg)
	local best, bestV = nil, 0
	for name, v in pairs(seg.enemies) do
		if v > bestV then best, bestV = name, v end
	end
	return best
end

local function Cumulative(t)
	local out, sum = {}, 0
	if t then
		for i = 1, #t do
			sum = sum + (t[i] or 0)
			out[i] = sum
		end
	end
	return out
end

local function CheckRecord(seg)
	if not (seg.boss and seg.kill and playerGUID) then return end
	local me = seg.players[playerGUID]
	if not me then return end
	local key = seg.boss .. " (" .. (seg.diff or "?") .. ")"
	local rec = Z.char.records[key]
	if not rec then
		rec = { boss = seg.boss, diff = seg.diff }
		Z.char.records[key] = rec
	end
	local dps, hps = me.dmg / seg.dur, (me.heal + me.absorb) / seg.dur
	if dps > 0 and dps > (rec.dps or 0) then
		local old = rec.dps
		rec.dps, rec.dmg, rec.dur, rec.date = dps, me.dmg, seg.dur, date("%d/%m/%Y")
		rec.tl = Cumulative(me.td)
		seg.record = true
		if Z.db.announceRecord and me.dmg >= me.heal then
			Z:Print(("|cffffd633Nouveau record personnel|r sur %s : %s DPS%s"):format(
				key, Z.Num(dps), old and (" (ancien : " .. Z.Num(old) .. ")") or ""))
		end
	end
	if hps > 0 and hps > (rec.hps or 0) then
		local old = rec.hps
		rec.hps, rec.hdate = hps, date("%d/%m/%Y")
		if Z.db.announceRecord and me.heal > me.dmg then
			Z:Print(("|cffffd633Nouveau record personnel|r sur %s : %s SPS%s"):format(
				key, Z.Num(hps), old and (" (ancien : " .. Z.Num(old) .. ")") or ""))
		end
	end
end

function Z:EndCombat()
	local seg = Z.current
	if not seg then return end
	Z.current = nil
	-- Fin : le dernier événement vu, ou la fin annoncée par un coéquipier qui a vu
	-- le combat se prolonger hors de portée de notre journal.
	local last = lastEvent
	local se = seg.syncEnd
	if se and se - last > SYNC_SLACK and se - last <= SYNC_LATE then last = se end
	seg.syncEnd = nil
	local dur = max(1, last - seg.t0)
	CloseAuras(seg, lastEvent)
	seg.active, seg.start, seg.dur, seg.t1 = nil, nil, dur, last
	lastEndAt = last
	if seg.pvp == "arena" then
		seg.name = "Arène : " .. (seg.zone or "?")
	elseif seg.pvp == "pvp" then
		seg.name = "Champ de bataille : " .. (seg.zone or "?")
	elseif seg.pvp and not seg.boss then
		seg.name = "JcJ : " .. (TopEnemy(seg) or TopFoe(seg) or "?")
	else
		-- Instance que ni le jeu ni DBM ne signalent (serveur personnalisé, boss sans
		-- cadre) : un combat long concentré sur un seul ennemi est traité comme un boss.
		if not seg.boss then
			local inInstance, itype = IsInInstance()
			if inInstance and (itype == "party" or itype == "raid") and dur >= 40 then
				local best, bestV, sum = nil, 0, 0
				for name, v in pairs(seg.enemies) do
					sum = sum + v
					if v > bestV then best, bestV = name, v end
				end
				if best and bestV >= sum * 0.7 then
					seg.boss, seg.diff, seg.inst, seg.guess = best, DiffLabelSafe(), true, true
					local diedAt = seg.dead and seg.dead[best]
					if diedAt then seg.kill, seg.killAt = true, diedAt end
				end
			end
		end
		seg.name = seg.boss or TopEnemy(seg) or TopFoe(seg) or "Combat"
	end
	seg.dead, seg.encDead = nil, nil
	local total = Z.char.total
	total.dur = total.dur + dur
	for guid, p in pairs(seg.players) do
		p.last = nil
		-- Spécialisation et rôle connus à ce moment, gardés avec le combat.
		local idx, _, _, role = Z:SpecInfo(guid, p.class, p)
		if idx then
			p.sp, p.ro = idx, role
			local tp = total.players[guid]
			if tp then tp.sp, tp.ro = idx, role end
		end
	end
	for _, p in pairs(total.players) do p.last = nil end

	local segs = Z.char.segments
	local keep = dur >= Z.db.minFight and next(seg.players) ~= nil
	if not keep then
		for i = 1, #segs do
			if segs[i] == seg then
				tremove(segs, i)
				break
			end
		end
	else
		if seg.boss then
			-- Victoire : le boss est mort juste avant la fin, ou plus tôt sans que
			-- le groupe soit décimé. Échec : au moins la moitié du groupe est morte.
			-- Sinon l'issue est inconnue (boss qui s'enfuit, combat interrompu).
			local dead, n = GroupDead()
			local wiped = dead * 2 >= n
			local recent = seg.killAt and lastEvent - seg.killAt < 30
			local result
			if seg.kill and (recent or not wiped) then
				result = "kill"
			elseif wiped then
				result = "wipe"
			end
			-- DBM sait précisément si la rencontre est gagnée ou perdue.
			if seg.dbmResult then result = seg.dbmResult end
			seg.dbmResult = nil
			seg.kill = result == "kill" or nil
			-- Compteur d'essais par boss, en instance seulement (pas sur un mannequin).
			if result == "kill" and not seg.inst then
				seg.name = seg.boss .. " (vaincu)"
			elseif seg.inst and result then
				local key = seg.boss .. " (" .. (seg.diff or "?") .. ")"
				local tries = Z.char.tries
				if result == "kill" then
					tries[key] = nil
					seg.name = seg.boss .. " (vaincu)"
				else
					tries[key] = (tries[key] or 0) + 1
					seg.try = tries[key]
					seg.name = ("%s (échec n° %d)"):format(seg.boss, seg.try)
				end
			end
		end
		seg.killAt = nil
		CheckRecord(seg)
		if Z.db.bossOnly then
			for i = #segs, 2, -1 do
				if not segs[i].boss then tremove(segs, i) end
			end
		end
		while #segs > Z.db.maxSegments do tremove(segs) end
	end

	-- Les boucliers encore actifs sont conservés pour le combat suivant ; ceux dont
	-- la disparition n'a pas été vue (hors de portée) sont oubliés à expiration.
	for guid, list in pairs(shields) do
		for i = #list, 1, -1 do
			if list[i].gone or lastTs > list[i].exp then tremove(list, i) end
		end
		if #list == 0 then shields[guid] = nil end
	end
	PruneTotal(total)
	wipe(lastHeal)
	wipe(noOwner)
	wipe(lastRemoved)
	wipe(reflects)
	wipe(bossChecked)
	if petCount > 600 then
		wipe(pets)
		petCount = 0
		Z:UpdateRoster()
	end
	Z:Fire("COMBAT_END", seg, keep)
end

-- Désigne le boss d'un segment. `dbm` : annoncé par DBM, qui fait alors autorité.
function Z.SetBoss(seg, name, dbm)
	if not name or (seg.boss and not dbm) then return end
	local first = not seg.boss
	seg.boss = name
	seg.diff = DiffLabelSafe()
	local inInstance, itype = IsInInstance()
	seg.inst = (inInstance and (itype == "raid" or itype == "party")) or nil
	if dbm then seg.dbm = true end
	if first then
		if Z.db.announcePull and seg.pullBy then
			Z:Print(("%s engagé par |cffffffff%s|r (%s sur %s)."):format(
				name, seg.pullBy, seg.pullSpell or "?", seg.pullTarget or "?"))
		end
		Z:Fire("BOSS", seg)
	end
end

-- Compare un ennemi à la liste intégrée des boss, dès son premier coup.
local function CheckBoss(seg, guid, name)
	if seg.pvp == "pvp" or seg.pvp == "arena" then return end
	local cid = Z.CreatureId(guid)
	if not cid then return end
	local known = seg.enc or seg.bossId
	local idx = Z.ENC[cid]
	if idx then
		-- Créature d'une rencontre à plusieurs : le combat porte le nom de la rencontre.
		local name2 = Z.ENCS[idx].name
		if not seg.boss then
			Z.SetBoss(seg, name2)
		elseif not seg.enc then
			seg.boss = name2
		end
		seg.enc = seg.enc or idx
	elseif Z.BOSS[cid] then
		cidName[cid] = name
		if not seg.boss then
			Z.SetBoss(seg, name)
			seg.bossId = cid
		elseif seg.dbm and seg.dbmId == cid then
			-- DBM a annoncé ce boss : on garde le nom tel que le client l'affiche.
			seg.boss, seg.bossId = name, cid
		elseif not seg.bossId and seg.boss == name then
			seg.bossId = cid
		end
	end
	-- Premier boss vu dans le journal pour ce combat : le groupe est prévenu
	-- (utile à un coéquipier trop loin pour avoir vu ce coup).
	if not known and (seg.enc or seg.bossId) then
		lastPull = NOW
		Z:Fire("PULL", seg.boss, cid)
	end
end

-- Premier coup échangé avec une créature de boss alors qu'un combat dure depuis
-- plus de 3 s sans boss vu dans le journal (monstres enchaînés sur le boss) :
-- le boss ouvre son propre combat. Chaque client voit ce même premier coup et
-- découpe au même instant, sans dépendre de DBM ; un client trop loin pour
-- l'avoir vu est prévenu par la synchronisation (Z:EncounterPull).
local function BossSplit(seg, foe, now)
	if not foe or seg.enc or seg.bossId or seg.pvp or bossChecked[foe] or now - seg.start <= 3 then return seg end
	local cid = Z.CreatureId(foe)
	if not (cid and (Z.ENC[cid] or Z.BOSS[cid])) then return seg end
	-- Un nom de boss supposé (cadre de boss, DBM) n'appartient pas au combat de monstres.
	seg.boss, seg.dbm, seg.dbmId, seg.guess = nil, nil, nil, nil
	Z:EndCombat()
	return nil
end

local bossUnits = { "boss1", "boss2", "boss3", "boss4", "target", "focus" }

local function IsBossUnit(unit, always, dungeon)
	if not UnitExists(unit) or not UnitCanAttack("player", unit) then return false end
	if UnitIsDead(unit) then return false end
	if always then return true end
	if not UnitAffectingCombat(unit) then return false end
	local class, level = UnitClassification(unit), UnitLevel(unit)
	if class == "worldboss" or level == -1 then return true end
	-- En donjon, les boss ne sont pas "boss mondiaux" : ce sont des élites
	-- de deux niveaux au-dessus du joueur, contrairement aux monstres ordinaires.
	return dungeon and class == "elite" and level >= (UnitLevel("player") or 80) + 2 or false
end

local function ScanBoss(seg)
	local found
	local inInstance, itype = IsInInstance()
	local dungeon = inInstance and itype == "party"
	for i = 1, #bossUnits do
		if IsBossUnit(bossUnits[i], i <= 4, dungeon) then
			found = bossUnits[i]
			break
		end
	end
	if not found then
		for i = 1, GetNumRaidMembers() do
			local u = RAIDTARGET[i]
			if IsBossUnit(u, false, dungeon) then
				found = u
				break
			end
		end
	end
	if not found and dungeon then
		for i = 1, GetNumPartyMembers() do
			local u = PARTYTARGET[i]
			if IsBossUnit(u, false, true) then
				found = u
				break
			end
		end
	end
	if not found then return end
	Z.SetBoss(seg, UnitName(found))
end

-- Bilan de fiabilité d'un segment : texte et drapeau "sans réserve".
function Z:QualityText(seg)
	local q = seg.q
	local synced = q and q.sync and q.sync > 0
		and (" %s de dégâts et de soins hors de portée de votre journal ont été récupérés auprès du groupe."):format(Z.Num(q.sync)) or ""
	if not q or (q.pet == 0 and q.abs == 0 and q.fix == 0) then
		return "Fiabilité des données : aucune anomalie détectée sur ce segment." .. synced, true
	end
	local parts = {}
	if q.fix > 0 then parts[#parts + 1] = ("%d panne(s) du journal de combat réparée(s), des événements ont pu manquer"):format(q.fix) end
	if q.pet > 0 then parts[#parts + 1] = ("%d coup(s) de familier sans maître identifié, non comptés par votre journal"):format(q.pet) end
	if q.abs > 0 then parts[#parts + 1] = ("%s d'absorption sans bouclier identifié, crédités au joueur protégé lui-même"):format(Z.Num(q.abs)) end
	return "Fiabilité des données : " .. table.concat(parts, " ; ") .. "." .. synced, false
end

-- Écart en direct avec le record personnel sur ce boss (dégâts cumulés).
function Z:GetRecordDelta()
	local seg = Z.current
	if not (seg and seg.boss and playerGUID) then return nil end
	local rec = Z.char.records[seg.boss .. " (" .. (seg.diff or "?") .. ")"]
	if not (rec and rec.tl and rec.dmg) then return nil end
	local me = seg.players[playerGUID]
	local mine = me and me.dmg or 0
	local el = GetTime() - seg.start
	local ghost
	if el >= rec.dur then
		ghost = rec.dmg
	else
		local idx = el / BUCKET
		local i = floor(idx)
		local a = i > 0 and (rec.tl[i] or rec.dmg) or 0
		local b = rec.tl[i + 1] or rec.dmg
		ghost = a + (b - a) * (idx - i)
	end
	return mine - ghost, rec
end

-- Débit sur les dernières secondes (tranche en cours + précédente).
function Z:LiveRate(seg, p, field)
	if not seg.active then return 0 end
	local t = p[field]
	if not t then return 0 end
	local el = GetTime() - seg.start
	local b = floor(el / BUCKET) + 1
	local sum = (t[b] or 0) + (t[b - 1] or 0)
	local span = b > 1 and (el - (b - 2) * BUCKET) or el
	return sum / max(span, 1)
end

-------------------------------------------------------------------------------
-- Enregistrement des données
-------------------------------------------------------------------------------

local function SpellRec(tbl, key, id, name, school, pet)
	local s = tbl[key]
	if not s then
		s = { id = id, n = name or UNKNOWN, sc = school, pet = pet, tot = 0, hit = 0, crit = 0, max = 0, miss = 0 }
		tbl[key] = s
	end
	return s
end

local function AddDone(seg, now, oG, oN, pet, dN, key, id, name, school, amount, crit, friendly, res, blk, abs, glance, ok)
	local p = GetP(seg, oG, oN)
	if not PASSIVE[id] then Active(p, now) end
	if friendly then
		-- Dégâts infligés à un allié (y compris par un debuff porté par le joueur).
		p.ff = p.ff + amount
		local t = p.ffTo
		if not t then
			t = {}
			p.ffTo = t
		end
		t[dN] = (t[dN] or 0) + amount
		local fs = p.ffSpells
		if not fs then
			fs = {}
			p.ffSpells = fs
		end
		local s = SpellRec(fs, key, id, name, school, pet)
		s.tot = s.tot + amount
		s.hit = s.hit + 1
		if crit then s.crit = s.crit + 1 end
		if amount > s.max then s.max = amount end
		if not s.min or amount < s.min then s.min = amount end
		return
	end
	p.dmg = p.dmg + amount
	local s = SpellRec(p.spells, key, id, name, school, pet)
	s.tot = s.tot + amount
	s.hit = s.hit + 1
	if crit then
		s.crit = s.crit + 1
		s.ca = (s.ca or 0) + amount
	end
	if glance then s.gl = (s.gl or 0) + 1 end
	-- Excédent : part du coup fatal qui dépasse la vie restante de la cible.
	if ok and ok > 0 then
		s.ok = (s.ok or 0) + ok
		p.ok = (p.ok or 0) + ok
	end
	if abs and abs > 0 then p.dAbs = (p.dAbs or 0) + abs end
	if amount > s.max then s.max = amount end
	if not s.min or amount < s.min then s.min = amount end
	if res and res > 0 then s.res = (s.res or 0) + res end
	if blk and blk > 0 then s.blk = (s.blk or 0) + blk end
	if abs and abs > 0 then s.abs = (s.abs or 0) + abs end
	p.targets[dN] = (p.targets[dN] or 0) + amount
	seg.enemies[dN] = (seg.enemies[dN] or 0) + amount
	if seg.tl then Timeline(seg, p, "td", now, amount) end
end

local function PlayerClass(guid)
	if not GetPlayerInfoByGUID then return nil end
	local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
	return ok and class or nil
end

-- Classe d'un joueur adverse que le groupe a frappé (pour colorer sa barre).
local function EnemyClass(seg, name, guid)
	local ec = seg.eclass
	if not ec then
		ec = {}
		seg.eclass = ec
	end
	if ec[name] == nil then ec[name] = PlayerClass(guid) or false end
end

-- Ce que chaque ennemi a infligé au groupe (d), soigné (h), et à qui (to).
local function Foe(seg, guid, name, flags)
	local foes = seg.foes
	if not foes then
		foes = {}
		seg.foes = foes
	end
	local f = foes[name]
	if not f then
		f = { d = 0, h = 0 }
		if band(flags, TYPE_PLAYER) ~= 0 then f.class = PlayerClass(guid) end
		foes[name] = f
	end
	return f
end

local function AddFoeDamage(seg, guid, name, flags, victim, amount)
	local f = Foe(seg, guid, name, flags)
	f.d = f.d + amount
	local t = f.to
	if not t then
		t = {}
		f.to = t
	end
	t[victim] = (t[victim] or 0) + amount
end

local function TakenRec(p, id, name)
	local s = p.takenBy[id]
	if not s then
		s = { id = id, n = name or UNKNOWN, tot = 0, hit = 0, crit = 0, max = 0, miss = 0 }
		p.takenBy[id] = s
	end
	return s
end

local function AddTaken(seg, dG, dN, id, name, src, amount, crit, crush, res, blk, abs, hpMax)
	local p = GetP(seg, dG, dN)
	p.taken = p.taken + amount
	if hpMax and hpMax > (p.hpMax or 0) then p.hpMax = hpMax end
	local s = TakenRec(p, id, name)
	s.src = src
	s.tot = s.tot + amount
	s.hit = s.hit + 1
	if crit then
		s.crit = s.crit + 1
		s.ca = (s.ca or 0) + amount
	end
	if crush then s.cr = (s.cr or 0) + 1 end
	if amount > s.max then s.max = amount end
	if not s.min or amount < s.min then s.min = amount end
	if res and res > 0 then
		s.res = (s.res or 0) + res
		p.tRes = (p.tRes or 0) + res
	end
	if blk and blk > 0 then
		s.blk = (s.blk or 0) + blk
		p.tBlk = (p.tBlk or 0) + blk
	end
	if abs and abs > 0 then
		s.abs = (s.abs or 0) + abs
		p.tAbs = (p.tAbs or 0) + abs
	end
end

-- Attaque entièrement évitée ou annulée contre un joueur du groupe.
local function AddAvoid(seg, dG, dN, id, name, src, missType, amount)
	local p = GetP(seg, dG, dN)
	local s = TakenRec(p, id, name)
	s.src = src
	s.miss = s.miss + 1
	local m = s.m
	if not m then
		m = {}
		s.m = m
	end
	m[missType] = (m[missType] or 0) + 1
	if amount and amount > 0 then
		if missType == "ABSORB" then
			s.abs = (s.abs or 0) + amount
			p.tAbs = (p.tAbs or 0) + amount
		elseif missType == "BLOCK" then
			s.blk = (s.blk or 0) + amount
			p.tBlk = (p.tBlk or 0) + amount
		elseif missType == "RESIST" then
			s.res = (s.res or 0) + amount
			p.tRes = (p.tRes or 0) + amount
		end
	end
end

local function AddMiss(seg, oG, oN, pet, key, id, name, school, missType)
	local s = SpellRec(GetP(seg, oG, oN).spells, key, id, name, school, pet)
	s.miss = s.miss + 1
	local m = s.m
	if not m then
		m = {}
		s.m = m
	end
	m[missType] = (m[missType] or 0) + 1
end

local function AddHeal(seg, now, oG, oN, pet, dN, key, id, name, eff, over, crit, isAbsorb, dG)
	local p = GetP(seg, oG, oN)
	if not isAbsorb then Active(p, now) end
	if isAbsorb then
		p.absorb = p.absorb + eff
	else
		p.heal = p.heal + eff
		p.over = p.over + over
	end
	local s = SpellRec(p.heals, key, id, name, nil, pet)
	s.shield = isAbsorb or nil
	s.tot = s.tot + eff
	s.over = (s.over or 0) + over
	s.hit = s.hit + 1
	if crit then
		s.crit = s.crit + 1
		s.ca = (s.ca or 0) + eff
	end
	if eff > s.max then s.max = eff end
	p.healed[dN] = (p.healed[dN] or 0) + eff
	if seg.tl then Timeline(seg, p, "th", now, eff) end
	-- Soins et absorptions reçus par un joueur du groupe.
	local r = dG and eff > 0 and roster[dG]
	if r and r.class then
		local d = GetP(seg, dG, dN)
		d.hin = (d.hin or 0) + eff
		local t = d.healIn
		if not t then
			t = {}
			d.healIn = t
		end
		t[oN] = (t[oN] or 0) + eff
		-- Absorptions reçues par lanceur : la cible les voit toutes, même quand le
		-- lanceur est loin d'elle ; c'est ce qu'elle annonce au groupe (Sync.lua).
		if isAbsorb then
			local a = d.absIn
			if not a then
				a = {}
				d.absIn = a
			end
			a[oN] = (a[oN] or 0) + eff
		end
	end
end

local function ShieldCapacity(def, id, oG, dG, ts, old)
	local ratio = STACKING[id]
	if ratio then
		-- Egide divine et Val'anyr s'empilent : capacité = reste + part du dernier soin.
		local base = (old and not old.gone and old.rem) or 0
		local h = lastHeal[dG] and lastHeal[dG][oG]
		if h and ts - h.t < 0.5 and ts >= h.t then return min(STACK_CAP[id], base + h.a * ratio) end
		return base > 0 and base or nil
	elseif HP_RATIO[id] then
		local r = roster[dG]
		local m = r and r.unit and UnitHealthMax(r.unit)
		return m and m > 0 and m * HP_RATIO[id] or nil
	end
	local l = learned[oG]
	return (l and l[id]) or def.cap
end

local cand = {}

-- Répartit un montant absorbé entre les boucliers de la cible.
-- Le journal 3.3.5 ne dit pas quel bouclier a absorbé ; on reproduit donc la
-- règle du serveur : les boucliers sont consommés dans un ordre fixe, et un
-- bouclier encore présent après le coup a forcément tout encaissé à son tour.
-- Seul un bouclier brisé laisse passer le surplus au suivant.
local function Absorb(ts, now, dG, dN, school, amount)
	local seg = Z.current
	local list = shields[dG]
	school = (school and school > 0) and school or 1
	local n = 0
	if list then
		for i = #list, 1, -1 do
			local s = list[i]
			if (s.gone and ts - s.gone > 0.5) or ts > s.exp then
				tremove(list, i)
			elseif band(school, s.def.mask) == school then
				n = n + 1
				cand[n] = s
			end
		end
	end
	for i = n + 1, #cand do cand[i] = nil end
	if n == 0 then
		if not seg then return end
		local total = Z.char.total
		-- Bouclier inconnu de Zénith (sort propre à un serveur, objet rare) : une
		-- amélioration retirée juste avant un coup absorbé, plusieurs fois de suite,
		-- est reconnue comme un bouclier et créditée à son lanceur.
		local lr = lastRemoved[dG]
		if lr and lr.id and ts >= lr.t and ts - lr.t <= 0.15 then
			local id, name = lr.id, lr.n
			lr.id = nil
			local seen = (autoSeen[id] or 0) + 1
			autoSeen[id] = seen
			if seen >= AUTO_LEARN then
				local oG, oN = Owner(lr.sG, lr.sN or UNKNOWN, lr.sF)
				if oG then
					SHIELDS[id] = SHIELDS[id] or { pri = 20, mask = ALL, dur = 60, auto = true }
					AddHeal(seg, now, oG, oN, nil, dN, id + ABSORB_KEY, id, name, amount, 0, false, true, dG)
					AddHeal(total, now, oG, oN, nil, dN, id + ABSORB_KEY, id, name, amount, 0, false, true, dG)
					return
				end
			end
		end
		Quality(seg).abs = Quality(seg).abs + amount
		-- Sinon l'absorption vient du joueur lui-même : talent passif de tank,
		-- ou effet que le journal ne permet pas d'identifier.
		local r = roster[dG]
		if r and r.class then
			local passive = PASSIVE_ABSORB[r.class]
			-- Défenseur ardent est un talent de protection : on ne le suppose que
			-- pour un paladin qui bloque avec un bouclier, pas pour un vindicte.
			if passive and r.class == "PALADIN" then
				local tp = total.players[dG]
				if not (tp and (tp.tBlk or 0) > 0) then passive = nil end
			end
			local id = passive and passive[school == 1 and 1 or 2] or 0
			local name = SELF_ABSORB
			if id > 0 then
				name = passiveName[id]
				if not name then
					name = GetSpellInfo(id) or SELF_ABSORB
					passiveName[id] = name
				end
			end
			AddHeal(seg, now, dG, dN, nil, dN, id + ABSORB_KEY, id, name, amount, 0, false, true, dG)
			AddHeal(total, now, dG, dN, nil, dN, id + ABSORB_KEY, id, name, amount, 0, false, true, dG)
		end
		return
	end
	for i = 2, n do
		local s = cand[i]
		local j = i - 1
		while j >= 1 and (cand[j].def.pri > s.def.pri or (cand[j].def.pri == s.def.pri and cand[j].t > s.t)) do
			cand[j + 1] = cand[j]
			j = j - 1
		end
		cand[j + 1] = s
	end
	local remaining = amount
	local total = Z.char.total
	for i = 1, n do
		local s = cand[i]
		if s.def.ignore then return end
		local give = remaining
		if i < n and s.gone and s.rem then give = min(remaining, s.rem) end
		if n > 1 then s.solo = false end
		s.used = s.used + give
		if s.rem then
			s.rem = s.rem - give
			if s.rem < 0 then s.rem = 0 end
		end
		remaining = remaining - give
		if give > 0 and seg then
			local key = s.id + ABSORB_KEY
			AddHeal(seg, now, s.src, s.srcName, nil, dN, key, s.id, s.n, give, 0, false, true, dG)
			AddHeal(total, now, s.src, s.srcName, nil, dN, key, s.id, s.n, give, 0, false, true, dG)
		end
		if s.gone then
			-- Bouclier brisé alors qu'il était seul : sa capacité réelle est connue.
			if s.solo and not STACKING[s.id] and s.used > 0 and (not s.def.cap or s.used <= s.def.cap * 2.5) then
				local l = learned[s.src]
				if not l then
					l = {}
					learned[s.src] = l
				end
				-- On garde la plus forte valeur vue : un bouclier entamé hors de portée sous-estime.
				if s.used > (l[s.id] or 0) then l[s.id] = s.used end
			end
			for k = #list, 1, -1 do
				if list[k] == s then
					tremove(list, k)
					break
				end
			end
		end
		if remaining <= 0 then break end
	end
end

-- Un échange entre le groupe et un ennemi ouvre un combat ; un simple tic de DoT
-- sur un joueur, ou un coup venu d'un allié hors du groupe, ne suffit pas.
local function Engages(srcGroup, dstGroup, sF, periodic)
	return (srcGroup and not dstGroup) or (dstGroup and not srcGroup and not periodic and band(sF, HOSTILE_OR_NEUTRAL) ~= 0)
end

-- Combat en cours pour un événement, après un éventuel découpage à l'arrivée d'un boss.
local function CurrentFor(sG, sF, dG, dF, srcGroup, dstGroup, now)
	local seg = Z.current
	if not seg then return nil end
	local foe
	if srcGroup and not dstGroup then
		if band(dF, TYPE_PLAYER) == 0 then foe = dG end
	elseif dstGroup and not srcGroup then
		if band(sF, TYPE_PLAYER) == 0 then foe = sG end
	end
	return BossSplit(seg, foe, now)
end

local function Damage(ts, sG, sN, sF, dG, dN, dF, id, name, school, amount, res, blk, absorbed, crit, glance, crush, periodic, ok)
	-- Sort renvoyé (Renvoi de sort du guerrier...) : le journal montre l'ennemi se
	-- blesser lui-même ; les dégâts reviennent au joueur qui a renvoyé le sort.
	if sG and sG == dG and band(sF, GROUP) == 0 then
		local r = reflects[sG]
		if r and r.id == id and NOW - r.t < 5 then
			sG, sN, sF = r.g, r.n, r.f
		end
	end
	local srcGroup = band(sF, GROUP) ~= 0
	local dstGroup = band(dF, GROUP) ~= 0
	if not srcGroup and not dstGroup then return end
	amount = amount or 0
	id = MERGE[id] or id
	dN = dN or UNKNOWN
	sN = sN or UNKNOWN
	local now = NOW
	local seg = CurrentFor(sG, sF, dG, dF, srcGroup, dstGroup, now)
	if not seg then
		if not Engages(srcGroup, dstGroup, sF, periodic) then return end
		seg = Start(now, sN, name, dN)
	end
	lastEvent = now
	local total = Z.char.total
	if absorbed and absorbed > 0 and dstGroup then Absorb(ts, now, dG, dN, school, absorbed) end

	if dstGroup and not srcGroup and sG then
		-- Ce que l'ennemi (monstre ou joueur adverse) inflige au groupe.
		AddFoeDamage(seg, sG, sN, sF, dN, amount)
		AddFoeDamage(total, sG, sN, sF, dN, amount)
		if band(sF, TYPE_PLAYER) ~= 0 then
			if not seg.pvp and band(sF, HOSTILE) ~= 0 then seg.pvp = "monde" end
		elseif not bossChecked[sG] then
			bossChecked[sG] = true
			CheckBoss(seg, sG, sN)
		end
	elseif srcGroup and not dstGroup and dG then
		if band(dF, TYPE_PLAYER) ~= 0 then
			EnemyClass(seg, dN, dG)
			EnemyClass(total, dN, dG)
			if not seg.pvp and band(dF, HOSTILE) ~= 0 then seg.pvp = "monde" end
		elseif not bossChecked[dG] then
			bossChecked[dG] = true
			CheckBoss(seg, dG, dN)
		end
	end

	if dstGroup and band(dF, TYPE_PLAYER) ~= 0 then
		local hpMax = HpMax(roster[dG], now)
		AddTaken(seg, dG, dN, id, name, sN, amount, crit, crush, res, blk, absorbed, hpMax)
		AddTaken(total, dG, dN, id, name, sN, amount, crit, crush, res, blk, absorbed, hpMax)
		LogPush(dG, now, -amount, name, sN, hpMax)
	end
	if srcGroup then
		local oG, oN, pet = Owner(sG, sN, sF)
		-- Les dégâts qu'un joueur s'inflige à lui-même ne sont ni des dégâts ni des tirs amis.
		if oG and not (dstGroup and (oG == dG or pets[dG] == oG)) then
			if not pet and name then SpecHint(oG, name) end
			local key = pet and (id + PET_KEY) or id
			if periodic then key = -key end
			AddDone(seg, now, oG, oN, pet, dN, key, id, name, school, amount, crit, dstGroup, res, blk, absorbed, glance, ok)
			AddDone(total, now, oG, oN, pet, dN, key, id, name, school, amount, crit, dstGroup, res, blk, absorbed, glance, ok)
		elseif not oG then
			Quality(seg).pet = Quality(seg).pet + 1
		end
	end
end

local function Missed(ts, sG, sN, sF, dG, dN, dF, id, name, school, missType, amount, periodic)
	if not missType then return end
	local srcGroup = band(sF, GROUP) ~= 0
	local dstGroup = band(dF, GROUP) ~= 0
	if not srcGroup and not dstGroup then return end
	dN = dN or UNKNOWN
	sN = sN or UNKNOWN
	-- Une attaque ratée, parée ou absorbée engage le combat comme un coup porté,
	-- et le prolonge : sinon un combat d'esquives semblerait inactif.
	local seg = CurrentFor(sG, sF, dG, dF, srcGroup, dstGroup, NOW)
	if not seg and Engages(srcGroup, dstGroup, sF, periodic) then seg = Start(NOW, sN, name, dN) end
	-- Un coup entièrement absorbé use le bouclier, même hors combat.
	if missType == "ABSORB" and amount and amount > 0 and dstGroup then
		Absorb(ts, NOW, dG, dN, school, amount)
	end
	if not seg then return end
	lastEvent = NOW
	-- Un premier contact raté ou paré avec un boss l'identifie aussi.
	if srcGroup and not dstGroup then
		if dG and band(dF, TYPE_PLAYER) == 0 and not bossChecked[dG] then
			bossChecked[dG] = true
			CheckBoss(seg, dG, dN)
		end
	elseif dstGroup and not srcGroup and sG and band(sF, TYPE_PLAYER) == 0 and not bossChecked[sG] then
		bossChecked[sG] = true
		CheckBoss(seg, sG, sN)
	end
	if missType == "REFLECT" and dstGroup and sG and not srcGroup and band(dF, TYPE_PLAYER) ~= 0 then
		local r = reflects[sG]
		if not r then
			r = {}
			reflects[sG] = r
		end
		r.id, r.g, r.n, r.f, r.t = id, dG, dN, dF, NOW
	end
	id = MERGE[id] or id
	if dstGroup and band(dF, TYPE_PLAYER) ~= 0 then
		AddAvoid(seg, dG, dN, id, name, sN, missType, amount)
		AddAvoid(Z.char.total, dG, dN, id, name, sN, missType, amount)
	end
	if srcGroup and not dstGroup then
		local oG, oN, pet = Owner(sG, sN, sF)
		if oG then
			local key = pet and (id + PET_KEY) or id
			if periodic then key = -key end
			AddMiss(seg, oG, oN, pet, key, id, name, school, missType)
			AddMiss(Z.char.total, oG, oN, pet, key, id, name, school, missType)
		end
	end
end

local function Heal(ts, sG, sN, sF, dG, dN, dF, id, name, amount, over, crit, periodic)
	local oG, oN, pet
	if band(sF, GROUP) ~= 0 then
		oG, oN, pet = Owner(sG, sN or UNKNOWN, sF)
	elseif id == MARK_HEAL and sG and marks[sG] then
		-- Marque de sang : le journal désigne l'ennemi marqué comme soigneur ;
		-- le soin revient au chevalier de la mort qui a posé la marque.
		oG = marks[sG]
		local r = roster[oG]
		oN = r and r.name
	end
	if not oG or not oN then
		-- Soin lancé par un ennemi (utile surtout en JcJ).
		local seg = Z.current
		if seg and sG and sN and band(sF, GROUP) == 0 and band(sF, HOSTILE) ~= 0 then
			local eff = (amount or 0) - (over or 0)
			if eff > 0 then
				local f = Foe(seg, sG, sN, sF)
				f.h = f.h + eff
				f = Foe(Z.char.total, sG, sN, sF)
				f.h = f.h + eff
			end
		end
		return
	end
	if not pet and name then SpecHint(oG, name) end
	amount = amount or 0
	over = over or 0
	if dG then
		-- Mémorisé pour estimer l'Egide divine et Val'anyr qui en découlent.
		local t = lastHeal[dG]
		if not t then
			t = {}
			lastHeal[dG] = t
		end
		local h = t[oG]
		if not h then
			h = {}
			t[oG] = h
		end
		h.t, h.a = ts, amount
	end
	local seg = Z.current
	if not seg then return end
	local eff = amount - over
	if eff < 0 then eff = 0 end
	dN = dN or UNKNOWN
	local now = NOW
	local key = pet and (id + PET_KEY) or id
	if periodic then key = -key end
	AddHeal(seg, now, oG, oN, pet, dN, key, id, name, eff, over, crit, false, dG)
	AddHeal(Z.char.total, now, oG, oN, pet, dN, key, id, name, eff, over, crit, false, dG)
	if eff > 0 and band(dF, GROUP) ~= 0 and band(dF, TYPE_PLAYER) ~= 0 then
		LogPush(dG, now, eff, name, oN)
	end
end

local function Count(sG, sN, sF, field, tblField, what)
	local seg = Z.current
	if not seg or band(sF, GROUP) == 0 then return end
	local oG, oN = Owner(sG, sN or UNKNOWN, sF)
	if not oG then return end
	what = what or UNKNOWN
	for i = 1, 2 do
		local p = GetP(i == 1 and seg or Z.char.total, oG, oN)
		p[field] = (p[field] or 0) + 1
		local t = p[tblField]
		if not t then
			t = {}
			p[tblField] = t
		end
		t[what] = (t[what] or 0) + 1
	end
end

-------------------------------------------------------------------------------
-- Synchronisation de groupe (transport dans Sync.lua)
-------------------------------------------------------------------------------
-- Un joueur voit tous ses propres coups, ceux de ses familiers et ceux qu'il
-- reçoit ; ses coéquipiers peuvent en manquer (portée du journal, panne du
-- journal, familier dont le maître est inconnu). Ce qu'un joueur annonce de
-- lui-même fait donc foi : l'écart avec ce que l'on a vu est ajouté sur une
-- ligne dédiée, jamais retiré. Les durées sont alignées sur le début le plus
-- tôt et la fin la plus tardive vus dans le groupe.

local SYNC_KEY = 3e7
local SYNC_NAME = "Hors de portée (synchronisé)"

local function SyncAdd(seg, p, tp, now, field, tblField, key, timeline, amount, over)
	for i = 1, 2 do
		local q = i == 1 and p or tp
		q[field] = q[field] + amount
		local s = tblField == "takenBy" and TakenRec(q, key, SYNC_NAME) or SpellRec(q[tblField], key, 0, SYNC_NAME)
		s.tot = s.tot + amount
		if over then q.over = q.over + over end
		if tblField == "heals" then s.over = (s.over or 0) + (over or 0) end
		if field == "absorb" then s.shield = true end
	end
	if timeline and seg.tl then
		if seg.active then
			Timeline(seg, p, timeline, now, amount)
		else
			-- Combat terminé : l'écart rejoint la dernière tranche, pour que la
			-- relecture, le graphique et le record retombent sur le bon total.
			local t = p[timeline]
			if not t then
				t = {}
				p[timeline] = t
			end
			local b = max(#t, 1)
			t[b] = (t[b] or 0) + amount
		end
	end
end

local function SyncValues(seg, guid, name, v, now)
	local p = GetP(seg, guid, name)
	local tp = GetP(Z.char.total, guid, name)
	local added = 0
	local d = v.dmg - p.dmg
	if d > 0 then
		SyncAdd(seg, p, tp, now, "dmg", "spells", SYNC_KEY, "td", d)
		added = added + d
	end
	d = v.heal - p.heal
	local o = max(0, v.over - p.over)
	if d > 0 or o > 0 then
		d = max(0, d)
		SyncAdd(seg, p, tp, now, "heal", "heals", SYNC_KEY, "th", d, o)
		added = added + d
	end
	d = v.absorb - p.absorb
	if d > 0 then
		SyncAdd(seg, p, tp, now, "absorb", "heals", SYNC_KEY + 1, "th", d)
		added = added + d
	end
	d = v.taken - p.taken
	if d > 0 then SyncAdd(seg, p, tp, now, "taken", "takenBy", SYNC_KEY, nil, d) end
	d = v.act - p.act
	if d > 0 then
		p.act = v.act
		tp.act = tp.act + d
	end
	-- Boucliers qu'il a reçus : crédités à leurs lanceurs, membres du groupe.
	for caster, amount in pairs(v.absIn) do
		local cg = byName[caster]
		d = amount - (p.absIn and p.absIn[caster] or 0)
		if d > 0 and cg and roster[cg] and roster[cg].unit then
			SyncAdd(seg, GetP(seg, cg, caster), GetP(Z.char.total, cg, caster), now, "absorb", "heals", SYNC_KEY + 1, "th", d)
			for i = 1, 2 do
				local q, c = i == 1 and p or tp, GetP(i == 1 and seg or Z.char.total, cg, caster)
				q.hin = (q.hin or 0) + d
				q.healIn = q.healIn or {}
				q.healIn[caster] = (q.healIn[caster] or 0) + d
				q.absIn = q.absIn or {}
				q.absIn[caster] = (q.absIn[caster] or 0) + d
				c.healed[name] = (c.healed[name] or 0) + d
			end
			added = added + d
		end
	end
	if added > 0 then
		local q = Quality(seg)
		q.sync = (q.sync or 0) + added
	end
	return added > 0
end

local function Overlap(a0, a1, b0, b1)
	return (min(a1, b1) - max(a0, b0)) / max(a1 - a0, b1 - b0, 1)
end

-- Annonce d'un coéquipier : son combat a couru de rs à re (heures locales
-- estimées ; re vaut maintenant tant qu'il est en cours). final : combat terminé.
function Z:SyncReceive(guid, name, final, rs, re, v)
	local now = GetTime()
	local segs = Z.char.segments
	local seg = Z.current
	if seg then
		-- Notre combat précédent (même trop court pour être gardé) s'est terminé
		-- après le début annoncé : le groupe a découpé autrement (pause entre deux
		-- packs), ses chiffres couvrent plusieurs de nos combats et ne peuvent pas
		-- être répartis.
		local ok = seg.t0 - rs <= SYNC_EARLY and not (lastEndAt and lastEndAt <= seg.t0 and lastEndAt > rs + 1)
		if ok and (not final or re > seg.t0) then
			if seg.t0 - rs > SYNC_SLACK then seg.t0 = rs end
			-- Combat déjà fini chez lui : sa fin servira quand le nôtre se terminera.
			if final and re > (seg.syncEnd or 0) then seg.syncEnd = re end
			if SyncValues(seg, guid, name, v, now) then Z:Fire("SYNC", seg) end
			return
		end
		if not final then return end
	end
	-- Combat déjà terminé chez nous : celui qui recouvre le mieux l'annonce.
	for i = 1, min(#segs, 3) do
		local s = segs[i]
		if s ~= Z.current and s.t0 and s.t1 and Overlap(s.t0, s.t1, rs, re) >= 0.5 then
			local older, newer = segs[i + 1], segs[i - 1]
			local o1, n0 = older and older.t1, newer and newer.t0
			-- L'annonce déborde sur un combat voisin : le groupe a découpé autrement,
			-- ses chiffres couvrent plusieurs de nos combats et ne peuvent pas être répartis.
			if (o1 and o1 > rs + SYNC_SLACK) or (n0 and n0 < re - SYNC_SLACK) then return end
			local t0, t1 = s.t0, s.t1
			if t0 - rs > SYNC_SLACK and t0 - rs <= SYNC_EARLY then t0 = rs end
			if re - t1 > SYNC_SLACK and re - t1 <= SYNC_LATE then t1 = re end
			-- Jamais au-delà des combats voisins (sans rogner la plage d'origine).
			if o1 then t0 = max(t0, min(o1, s.t0)) end
			if n0 then t1 = min(t1, max(n0, s.t1)) end
			local dur = max(1, t1 - t0)
			Z.char.total.dur = Z.char.total.dur + (dur - s.dur)
			s.t0, s.t1, s.dur = t0, t1, dur
			SyncValues(s, guid, name, v, now)
			Z:Fire("SYNC", s)
			return
		end
	end
end

-------------------------------------------------------------------------------
-- Répartition des événements (arguments du client 3.3.5 : 8 champs de base)
-------------------------------------------------------------------------------

local H = {}

H.SWING_DAMAGE = function(ts, sG, sN, sF, dG, dN, dF, amount, ok, school, res, blk, absorbed, crit, glance, crush)
	Damage(ts, sG, sN, sF, dG, dN, dF, 6603, MELEE, school or 1, amount, res, blk, absorbed, crit, glance, crush, false, ok)
end
local function SpellDamage(ts, sG, sN, sF, dG, dN, dF, id, name, school, amount, ok, _, res, blk, absorbed, crit, glance, crush)
	Damage(ts, sG, sN, sF, dG, dN, dF, id or 0, name, school, amount, res, blk, absorbed, crit, glance, crush, false, ok)
end
H.SPELL_DAMAGE = SpellDamage
H.RANGE_DAMAGE = SpellDamage
H.DAMAGE_SHIELD = SpellDamage
H.DAMAGE_SPLIT = SpellDamage
H.SPELL_BUILDING_DAMAGE = SpellDamage
H.SPELL_PERIODIC_DAMAGE = function(ts, sG, sN, sF, dG, dN, dF, id, name, school, amount, ok, _, res, blk, absorbed, crit, glance, crush)
	Damage(ts, sG, sN, sF, dG, dN, dF, id or 0, name, school, amount, res, blk, absorbed, crit, glance, crush, true, ok)
end
H.ENVIRONMENTAL_DAMAGE = function(ts, _, _, _, dG, dN, dF, envType, amount, _, school, res, blk, absorbed, crit)
	Damage(ts, nil, ENVIRONMENT, 0, dG, dN, dF, ENV_IDS[envType] or 0, ENV_NAMES[envType] or ENVIRONMENT, school or 1, amount, res, blk, absorbed, crit, nil, nil, false)
end

H.SWING_MISSED = function(ts, sG, sN, sF, dG, dN, dF, missType, amount)
	Missed(ts, sG, sN, sF, dG, dN, dF, 6603, MELEE, 1, missType, amount, false)
end
local function MissedSpell(ts, sG, sN, sF, dG, dN, dF, id, name, school, missType, amount)
	Missed(ts, sG, sN, sF, dG, dN, dF, id or 0, name, school, missType, amount, false)
end
H.SPELL_MISSED = MissedSpell
H.RANGE_MISSED = MissedSpell
H.DAMAGE_SHIELD_MISSED = MissedSpell
H.SPELL_PERIODIC_MISSED = function(ts, sG, sN, sF, dG, dN, dF, id, name, school, missType, amount)
	Missed(ts, sG, sN, sF, dG, dN, dF, id or 0, name, school, missType, amount, true)
end

H.SPELL_HEAL = function(ts, sG, sN, sF, dG, dN, dF, id, name, _, amount, over, _, crit)
	Heal(ts, sG, sN, sF, dG, dN, dF, id or 0, name, amount, over, crit, false)
end
H.SPELL_PERIODIC_HEAL = function(ts, sG, sN, sF, dG, dN, dF, id, name, _, amount, over, _, crit)
	Heal(ts, sG, sN, sF, dG, dN, dF, id or 0, name, amount, over, crit, true)
end

H.SPELL_CAST_SUCCESS = function(_, sG, _, sF, _, _, _, id, name)
	if sG and band(sF, GROUP) ~= 0 and band(sF, TYPE_PLAYER) ~= 0 then
		if id == 63645 or id == 63644 then
			-- Activation de la double spécialisation : les talents sont à relire.
			Z.SpecChanged(sG)
		elseif name then
			SpecHint(sG, name)
		end
	end
end

H.PARTY_KILL = function(_, sG, sN, sF, _, dN, dF)
	Count(sG, sN, sF, "kills", "killsOn", dN)
	if band(dF, TYPE_PLAYER) ~= 0 and band(dF, GROUP) == 0 then Count(sG, sN, sF, "pk", "pkOn", dN) end
end
H.SPELL_RESURRECT = function(_, sG, sN, sF, _, dN)
	Count(sG, sN, sF, "rez", "rezOn", dN)
end

H.SPELL_INTERRUPT = function(_, sG, sN, sF, _, _, _, _, _, _, _, extraName)
	Count(sG, sN, sF, "int", "ints", extraName)
end
local function Dispel(_, sG, sN, sF, _, _, _, _, _, _, _, extraName)
	Count(sG, sN, sF, "disp", "disps", extraName)
end
H.SPELL_DISPEL = Dispel
H.SPELL_STOLEN = Dispel

H.SPELL_SUMMON = function(_, sG, _, sF, dG)
	if band(sF, GROUP) == 0 or not sG or not dG then return end
	if not pets[dG] then petCount = petCount + 1 end
	pets[dG] = sG
end

H.SPELL_CREATE = H.SPELL_SUMMON

local function ShieldApplied(ts, sG, sN, sF, dG, _, dF, id, name)
	if id == MARK_OF_BLOOD then
		if dG and band(sF, GROUP) ~= 0 then marks[dG] = Owner(sG, sN or UNKNOWN, sF) end
		return
	end
	local def = SHIELDS[id]
	if not def or not dG or band(dF, GROUP) == 0 then return end
	local oG, oN
	if def.ignore then
		oG = "boss"
	else
		if band(sF, GROUP) == 0 then return end
		oG, oN = Owner(sG, sN or UNKNOWN, sF)
		if not oG then return end
	end
	local list = shields[dG]
	if not list then
		list = {}
		shields[dG] = list
	end
	local old
	for i = #list, 1, -1 do
		local s = list[i]
		if s.id == id and s.src == oG then
			old = s
			tremove(list, i)
		end
	end
	if #list >= 12 then tremove(list, 1) end
	local e = {
		id = id, n = name, src = oG, srcName = oN, def = def, t = ts, exp = ts + def.dur + 1,
		rem = ShieldCapacity(def, id, oG, dG, ts, old), used = 0, solo = true,
	}
	-- Un bouclier empilable garde sa place dans l'ordre de consommation.
	if old and not old.gone and STACKING[id] then e.t = old.t end
	list[#list + 1] = e
end
H.SPELL_AURA_APPLIED = function(ts, sG, sN, sF, dG, dN, dF, id, name, school, auraType)
	ShieldApplied(ts, sG, sN, sF, dG, dN, dF, id, name)
	if not id then return end
	if sG and band(sF, GROUP) ~= 0 and band(sF, TYPE_PLAYER) ~= 0 then
		if name then SpecHint(sG, name) end
		if TANK_AURAS[id] and sG == dG then SetTanking(sG, true) end
	end
	local seg = Z.current
	if not seg or not trackAuras or not dG or AURA_IGNORE[id] then return end
	if band(dF, GROUP) ~= 0 then
		if band(dF, TYPE_PLAYER) ~= 0 then
			AuraOn(seg, dG, dN, auraType == "DEBUFF" and "debuffs" or "buffs", id, name, NOW)
		end
	elseif auraType == "DEBUFF" and sG and band(sF, GROUP) ~= 0 then
		local oG, oN = Owner(sG, sN or UNKNOWN, sF)
		if oG then AuraOn(seg, oG, oN, "dots", id, name, NOW) end
	end
end
H.SPELL_AURA_REFRESH = ShieldApplied

local function ShieldRemoved(ts, sG, sN, sF, dG, _, dF, id, name, _, auraType)
	if id == MARK_OF_BLOOD then
		if dG then marks[dG] = nil end
		return
	end
	local def = SHIELDS[id]
	if not def then
		-- Mémorisé pour repérer un bouclier inconnu qui vient de se briser.
		if auraType == "BUFF" and id and dG and sG and band(dF, GROUP) ~= 0 and band(sF, GROUP) ~= 0 then
			local lr = lastRemoved[dG]
			if not lr then
				lr = {}
				lastRemoved[dG] = lr
			end
			lr.t, lr.id, lr.n, lr.sG, lr.sN, lr.sF = ts, id, name, sG, sN, sF
		end
		return
	end
	local list = shields[dG]
	if not list then return end
	local oG
	if def.ignore then
		oG = "boss"
	else
		-- Seul un membre du groupe peut avoir posé un bouclier suivi.
		oG = sG and band(sF or 0, GROUP) ~= 0 and Owner(sG, sN or UNKNOWN, sF) or nil
	end
	-- Le retrait est journalisé juste avant le coup qui a brisé le bouclier.
	for i = 1, #list do
		local s = list[i]
		if s.id == id and not s.gone and (not oG or s.src == oG) then
			s.gone = ts
			return
		end
	end
end

H.SPELL_AURA_REMOVED = function(ts, sG, sN, sF, dG, dN, dF, id, name, school, auraType)
	ShieldRemoved(ts, sG, sN, sF, dG, dN, dF, id, name, school, auraType)
	if not id then return end
	if TANK_AURAS[id] and sG and sG == dG then SetTanking(sG, false) end
	local seg = Z.current
	if not seg or not trackAuras or not dG then return end
	if band(dF, GROUP) ~= 0 then
		if band(dF, TYPE_PLAYER) ~= 0 then
			AuraOff(seg, dG, auraType == "DEBUFF" and "debuffs" or "buffs", id, NOW)
		end
	elseif auraType == "DEBUFF" and sG and band(sF, GROUP) ~= 0 then
		local oG = Owner(sG, sN or UNKNOWN, sF)
		if oG then AuraOff(seg, oG, "dots", id, NOW) end
	end
end

-- Boss vaincu, vu dans le journal : le groupe est prévenu (coéquipier trop loin).
local function Killed(seg)
	if not seg.kill then Z:Fire("ENCOUNTER_RESULT", "kill", false) end
	seg.kill = true
	seg.killAt = NOW
end

H.UNIT_DIED = function(_, _, _, _, dG, dN, dF)
	local seg = Z.current
	if not seg then return end
	if seg.boss and dN == seg.boss then Killed(seg) end
	if band(dF, GROUP) == 0 then
		local cid = Z.CreatureId(dG)
		if cid and seg.enc then
			-- Rencontre à plusieurs créatures : une seule mort suffit, ou toutes.
			local e = Z.ENCS[seg.enc]
			if e.kill and e.kill[cid] then
				local d = seg.encDead
				if not d then
					d = { n = 0 }
					seg.encDead = d
				end
				if not d[cid] then
					d[cid] = true
					d.n = d.n + 1
				end
				if d.n >= e.need then Killed(seg) end
			end
		elseif cid and seg.bossId == cid then
			Killed(seg)
		end
	end
	if dN and band(dF, GROUP) == 0 then
		-- Sert à savoir, après coup, si le boss probable d'une instance inconnue est mort.
		local d = seg.dead
		if not d then
			d = {}
			seg.dead = d
		end
		d[dN] = NOW
	end
	if band(dF, GROUP) == 0 or band(dF, TYPE_PLAYER) == 0 then return end
	local r = roster[dG]
	if r and r.unit and UnitIsFeignDeath(r.unit) then return end
	local now = GetTime()
	-- Esprit de rédemption : le prêtre "meurt" deux fois en quinze secondes.
	if r and r.class == "PRIEST" then
		if deathAt[dG] and now >= deathAt[dG] and now - deathAt[dG] < 16 then return end
		deathAt[dG] = now
	end
	local total = Z.char.total
	GetP(seg, dG, dN).deaths = GetP(seg, dG, dN).deaths + 1
	GetP(total, dG, dN).deaths = GetP(total, dG, dN).deaths + 1
	local death = {
		guid = dG, name = dN, class = r and r.class,
		t = now - seg.start, log = LogSnapshot(dG, now, seg.start),
	}
	tinsert(seg.deaths, death)
	Z:Fire("DEATH", seg, death)
end
H.UNIT_DESTROYED = function(_, _, _, _, dG)
	if dG and pets[dG] then
		pets[dG] = nil
		petCount = petCount - 1
	end
end

function Z.CLEU(ts, etype, sG, sN, sF, dG, dN, dF, ...)
	local h = H[etype]
	NOW = GetTime()
	lastCLEU = NOW
	if not h then return end
	sF, dF = sF or 0, dF or 0
	-- Événement mal formé (certains serveurs en émettent) : sans identifiant,
	-- une unité ne peut pas être suivie comme membre du groupe.
	if not sG then sF = sF - band(sF, GROUP) end
	if not dG then dF = dF - band(dF, GROUP) end
	ts = ts or 0
	lastTs = ts
	h(ts, sG, sN, sF, dG, dN, dF, ...)
end

-------------------------------------------------------------------------------
-- Initialisation, surveillance, réinitialisation en instance
-------------------------------------------------------------------------------

local function FixLog(now, force)
	if not Z.db.fixLog or now - lastFix < 3 then return end
	lastFix = now
	CombatLogClearEntries()
	if not force and Z.current then
		Z.logFixes = Z.logFixes + 1
		Quality(Z.current).fix = Quality(Z.current).fix + 1
	end
end

local function Tick()
	local now = GetTime()
	-- Bogue connu de la 3.3.5 : le journal de combat cesse d'émettre des
	-- événements. Un sort lancé sans aucun événement reçu trahit la panne.
	if castAt and now - castAt > 1 then
		if lastCLEU < castAt - 0.5 then FixLog(now) end
		castAt = nil
	end
	local seg = Z.current
	if seg then
		-- Pas de boss en champ de bataille ni en arène.
		if not seg.boss and seg.pvp ~= "pvp" and seg.pvp ~= "arena" then ScanBoss(seg) end
		local idle = now - lastEvent
		-- Garde-fou : un membre du raid resté en combat ailleurs ne prolonge pas le segment.
		if (idle > 2.5 and not GroupInCombat()) or (idle > 20 and not UnitAffectingCombat("player")) then
			Z:EndCombat()
		end
	end
end

StaticPopupDialogs["ZENITH_RESET"] = {
	text = "Zénith : nouvelle instance détectée.\nRéinitialiser les données de combat ?",
	button1 = "Oui",
	button2 = "Non",
	OnAccept = function() Z:ResetData() end,
	timeout = 30,
	whileDead = 1,
	hideOnEscape = 1,
}

local function CheckInstance()
	local inInstance, itype = IsInInstance()
	if not inInstance or (itype ~= "party" and itype ~= "raid") then return end
	local name = GetInstanceInfo()
	if not name or name == Z.char.lastInstance then return end
	Z.char.lastInstance = name
	if #Z.char.segments == 0 then return end
	local mode = Z.db.resetInstance
	if mode == "toujours" then
		Z:ResetData()
		Z:Print("nouvelle instance : données réinitialisées.")
	elseif mode == "demander" then
		StaticPopup_Show("ZENITH_RESET")
	end
end

function Z:InitCombat()
	playerGUID, playerName = UnitGUID("player"), UnitName("player")
	Z.playerGUID = playerGUID
	local spell = GetSpellInfo(6603)
	if spell then MELEE = spell end

	Z.RAID_ROSTER_UPDATE = Z.UpdateRoster
	Z.PARTY_MEMBERS_CHANGED = Z.UpdateRoster
	Z.UNIT_PET = Z.UpdateRoster
	Z.UNIT_ENTERED_VEHICLE = Z.UpdateRoster
	Z.UNIT_EXITED_VEHICLE = Z.UpdateRoster
	function Z:UNIT_SPELLCAST_SUCCEEDED(unit)
		if unit == "player" then castAt = GetTime() end
	end
	function Z:PLAYER_ENTERING_WORLD()
		Z:UpdateRoster()
		wipe(shields)
		wipe(marks)
		FixLog(GetTime(), true)
		Z:After(3, CheckInstance)
	end
	function Z:ZONE_CHANGED_NEW_AREA()
		FixLog(GetTime(), true)
	end
	for _, e in ipairs({
		"COMBAT_LOG_EVENT_UNFILTERED", "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "UNIT_PET",
		"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UNIT_SPELLCAST_SUCCEEDED",
		"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	}) do
		Z:RegisterEvent(e)
	end
	Z:UpdateRoster()
	Z:Every(1, Tick)
	trackAuras = Z.db.trackAuras
	Z:On("SETTINGS", function() trackAuras = Z.db.trackAuras end)

	-- Liste de boss d'un autre addon, si elle est déjà chargée : elle complète la liste intégrée.
	local LS = rawget(_G, "LibStub")
	if type(LS) == "table" and LS.GetLibrary then
		local ok, lib = pcall(LS.GetLibrary, LS, "LibBossIDs-1.0", true)
		if ok and type(lib) == "table" and type(lib.BossIDs) == "table" then
			for id in pairs(lib.BossIDs) do
				if type(id) == "number" then Z.BOSS[id] = true end
			end
		end
	end

	-- DBM, s'il est installé, complète Zénith : nom de la rencontre, victoire, échec.
	-- Il ne décide jamais du découpage des combats (voir BossSplit) : un joueur
	-- avec DBM et un joueur sans DBM découpent exactement de la même façon.
	local dbm = rawget(_G, "DBM")
	if type(dbm) == "table" and type(dbm.RegisterCallback) == "function" then
		local function Name(mod)
			if type(mod) ~= "table" then return nil end
			local id = mod.creatureId
			if type(id) ~= "number" then id = mod.combatInfo and mod.combatInfo.mob end
			if type(id) ~= "number" then id = nil end
			local name = mod.combatInfo and mod.combatInfo.name
			if not name and mod.localization and mod.localization.general then name = mod.localization.general.name end
			return Z.EncounterName(id, type(name) == "string" and name or nil), id
		end
		pcall(dbm.RegisterCallback, dbm, "pull", function(_, mod)
			local name, id = Name(mod)
			Z:EncounterPull(name, id, true)
		end)
		pcall(dbm.RegisterCallback, dbm, "kill", function()
			if Z:EncounterResult("kill", true) then Z:Fire("ENCOUNTER_RESULT", "kill", true) end
		end)
		pcall(dbm.RegisterCallback, dbm, "wipe", function()
			if Z:EncounterResult("wipe", true) then Z:Fire("ENCOUNTER_RESULT", "wipe", true) end
		end)
		Z.hasDBM = true
	end
end

-- Nom d'une rencontre : celui de Zénith, sinon le nom du boss tel que le client
-- l'affiche, sinon le nom fourni (par DBM, éventuellement en anglais).
function Z.EncounterName(id, fallback)
	local idx = id and Z.ENC[id]
	if idx then return Z.ENCS[idx].name end
	if id and cidName[id] then return cidName[id] end
	return fallback
end

-- Engagement d'une rencontre annoncé par DBM (dbm vrai) ou par un coéquipier
-- dont le journal a vu le boss (dbm faux). DBM ne fait que nommer le combat ;
-- l'annonce d'un coéquipier découpe comme BossSplit l'aurait fait si ce coup
-- avait été à portée. Renvoie vrai si l'annonce était nouvelle.
function Z:EncounterPull(name, id, dbm)
	if not name then return end
	local now = GetTime()
	-- Plusieurs coéquipiers annoncent le même engagement, déjà vu ou non dans notre
	-- journal : seule la première annonce compte. DBM, qui ne découpe pas, n'entre
	-- pas dans ce décompte.
	if not dbm then
		if now - lastPull < 5 and now >= lastPull then return end
		lastPull = now
	end
	local seg = Z.current
	if seg and not dbm and not seg.pvp and not (seg.enc or seg.bossId) and now - seg.start > 3 then
		seg.boss, seg.dbm, seg.dbmId, seg.guess = nil, nil, nil, nil
		Z:EndCombat()
		seg = nil
	end
	if seg and not seg.pvp then
		Z.SetBoss(seg, name, dbm)
		if dbm then
			seg.dbmId = id
		elseif id and not (seg.enc or seg.bossId) then
			if Z.ENC[id] then seg.enc = Z.ENC[id] else seg.bossId = id end
		end
	elseif not seg then
		pendingBoss = { name = name, t = now, id = id, dbm = dbm }
	end
	return true
end

-- Issue d'une rencontre ("kill" ou "wipe"). dbm vrai : annoncée par DBM, qui fait
-- autorité ; dbm faux : mort du boss vue dans le journal d'un coéquipier.
function Z:EncounterResult(result, dbm)
	local seg = Z.current
	if not (seg and seg.boss) then return end
	if not dbm then
		if result ~= "kill" or seg.kill then return end
		seg.kill, seg.killAt = true, GetTime()
		return true
	end
	if seg.dbmResult == result then return end
	if result == "kill" then
		seg.kill, seg.killAt, seg.dbmResult = true, GetTime(), "kill"
	elseif result == "wipe" then
		seg.dbmResult = "wipe"
	else
		return
	end
	return true
end
