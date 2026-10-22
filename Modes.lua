-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Modes d'affichage, infobulles et analyse automatique.

local ADDON, ns = ...
local Z = ns.Z

local pairs, max, floor, sort = pairs, math.max, math.floor, table.sort
local Num, Pct, Time, Comma = Z.Num, Z.Pct, Z.Time, Z.Comma

Z.modes = {}
Z.modeByKey = {}

local function PerSecTime(p, dur)
	if Z.db.activeTime then return max(p.act or 0, 1) end
	return dur
end

-- "1,25 M (8,3 k, 23,4 %)" selon les options d'affichage.
local function Rich(total, per, pct)
	local db = Z.db
	local extra
	if per and db.showPerSec then extra = Num(per) end
	if pct and db.showPercent then extra = (extra and (extra .. ", ") or "") .. Pct(pct) end
	if extra then return Num(total) .. " (" .. extra .. ")" end
	return Num(total)
end

local function HealValue(p)
	return p.heal + p.absorb
end

local AVOID = { DODGE = true, PARRY = true, MISS = true }
local tank = {}

-- Bilan défensif d'un joueur : brut, atténué, évitement.
-- Renvoie une table réutilisée (à lire immédiatement).
function Z:TankStats(p)
	local abs, blk, res = p.tAbs or 0, p.tBlk or 0, p.tRes or 0
	local hits, avoided, others = 0, 0, 0
	local dodge, parry, miss = 0, 0, 0
	for _, s in pairs(p.takenBy) do
		hits = hits + (s.hit or 0)
		if s.m then
			for kind, n in pairs(s.m) do
				if AVOID[kind] then avoided = avoided + n else others = others + n end
				if kind == "DODGE" then dodge = dodge + n elseif kind == "PARRY" then parry = parry + n elseif kind == "MISS" then miss = miss + n end
			end
		end
	end
	local attacks = hits + avoided + others
	tank.abs, tank.blk, tank.res = abs, blk, res
	tank.mit = abs + blk + res
	tank.raw = p.taken + tank.mit
	tank.mitPct = tank.raw > 0 and tank.mit / tank.raw * 100 or 0
	tank.attacks, tank.avoided = attacks, avoided
	tank.dodge, tank.parry, tank.miss = dodge, parry, miss
	tank.avoidPct = attacks > 0 and avoided / attacks * 100 or 0
	return tank
end

local function TankTip(p, tip)
	local t = Z:TankStats(p)
	tip:AddLine("Bilan défensif", Z.db.accent[1], Z.db.accent[2], Z.db.accent[3])
	tip:AddDoubleLine("Dégâts bruts (avant atténuation)", Num(t.raw), 0.8, 0.8, 0.8, 1, 1, 1)
	tip:AddDoubleLine("Atténués", Num(t.mit) .. " (" .. Pct(t.mitPct) .. ")", 0.8, 0.8, 0.8, 1, 1, 1)
	tip:AddDoubleLine("  absorbés / bloqués / résistés", Num(t.abs) .. " / " .. Num(t.blk) .. " / " .. Num(t.res), 0.6, 0.6, 0.6, 1, 1, 1)
	tip:AddDoubleLine("Évitement (esquive, parade, raté)", ("%d sur %d (%s)"):format(t.avoided, t.attacks, Pct(t.avoidPct)), 0.8, 0.8, 0.8, 1, 1, 1)
	if p.hpMax and p.hpMax > 0 then
		tip:AddDoubleLine("Points de vie maximum", Num(p.hpMax), 0.8, 0.8, 0.8, 1, 1, 1)
	end
end

local function NotShield(rec) return not rec.shield end
local function IsShield(rec) return rec.shield end

local function AddMode(m)
	Z.modes[#Z.modes + 1] = m
	Z.modeByKey[m.key] = m
end

AddMode({
	key = "damage", name = "Dégâts infligés", group = "Dégâts", tab = "degats", tl = "td",
	value = function(p) return p.dmg end,
	text = function(v, p, dur, sum) return Rich(v, v / PerSecTime(p, dur), sum > 0 and v / sum * 100) end,
	spells = "spells", targets = "targets",
})
AddMode({
	key = "dps", name = "DPS", group = "Dégâts", tab = "degats", tl = "td",
	value = function(p, dur) return p.dmg / PerSecTime(p, dur) end,
	text = function(v, p) return Num(v) .. " (" .. Num(p.dmg) .. ")" end,
	spells = "spells", targets = "targets",
})
AddMode({
	key = "live", name = "DPS en direct", group = "Dégâts", tab = "degats", live = true,
	value = function(p, _, seg) return Z:LiveRate(seg, p, "td") end,
	text = function(v) return Num(v) end,
	spells = "spells", targets = "targets",
})
AddMode({
	key = "enemies", name = "Dégâts par ennemi", group = "Dégâts", enemies = true, color = { 0.85, 0.28, 0.25 },
	text = function(v, _, dur, sum) return Rich(v, nil, sum > 0 and v / sum * 100) end,
})
AddMode({
	key = "ff", name = "Dégâts infligés aux alliés", group = "Dégâts", tab = "allies",
	value = function(p) return p.ff end,
	text = function(v, _, _, sum) return Rich(v, nil, sum > 0 and v / sum * 100) end,
	spells = "ffSpells", targets = "ffTo", spellTitle = "Sorts et debuffs responsables", targetTitle = "Alliés touchés",
})
AddMode({
	key = "taken", name = "Dégâts subis (total)", group = "Tank et survie", tab = "subis",
	value = function(p) return p.taken end,
	text = function(v, _, dur, sum) return Rich(v, v / dur, sum > 0 and v / sum * 100) end,
	spells = "takenBy", spellTitle = "Sorts subis", extraTip = TankTip,
})
AddMode({
	-- Pondération par les points de vie maximum : un tank à 50 000 PV et un mage
	-- à 20 000 PV deviennent comparables ("combien de barres de vie perdues").
	key = "takenw", name = "Dégâts subis pondérés (PV max)", group = "Tank et survie", tab = "subis",
	value = function(p) return p.hpMax and p.hpMax > 0 and p.taken / p.hpMax or 0 end,
	text = function(v, p) return Comma(("%.1f"):format(v)) .. " x PV max (" .. Num(p.taken) .. ")" end,
	spells = "takenBy", spellTitle = "Sorts subis", extraTip = TankTip,
})
AddMode({
	key = "mitig", name = "Défense du tank (bloqué, absorbé, résisté)", group = "Tank et survie", tab = "subis",
	value = function(p) return (p.tAbs or 0) + (p.tBlk or 0) + (p.tRes or 0) end,
	text = function(v, p) return Num(v) .. " (" .. Pct(v / (v + p.taken) * 100) .. " du brut)" end,
	extraTip = TankTip,
})
AddMode({
	key = "avoid", name = "Évitement (esquive, parade, raté)", group = "Tank et survie", tab = "subis",
	value = function(p)
		local t = Z:TankStats(p)
		return t.attacks >= 5 and t.avoidPct or 0
	end,
	text = function(v, p)
		local t = Z:TankStats(p)
		return Pct(v) .. (" (%d sur %d)"):format(t.avoided, t.attacks)
	end,
	fixedMax = 100, extraTip = TankTip,
})
AddMode({
	-- Vue du raid entier : quels sorts ennemis ont fait le plus mal, et à qui.
	key = "takenspell", name = "Dégâts subis par sort (raid)", group = "Tank et survie", color = { 0.86, 0.32, 0.28 },
	collect = function(seg, out) return Z.CollectTakenSpells(seg, out) end,
	text = function(v, _, dur, sum) return Rich(v, v / dur, sum > 0 and v / sum * 100) end,
})
AddMode({
	key = "deaths", name = "Morts", group = "Tank et survie", tab = "morts",
	value = function(p) return p.deaths end,
	text = function(v) return ("%d"):format(v) end,
})
AddMode({
	key = "foedmg", name = "Dégâts infligés par les ennemis", group = "Ennemis et JcJ", color = { 0.85, 0.28, 0.25 },
	collect = function(seg, out) return Z.CollectFoes(seg, out, "d") end,
	text = function(v, _, dur, sum) return Rich(v, v / dur, sum > 0 and v / sum * 100) end,
})
AddMode({
	key = "foeheal", name = "Soins des ennemis", group = "Ennemis et JcJ", color = { 0.30, 0.75, 0.45 },
	collect = function(seg, out) return Z.CollectFoes(seg, out, "h") end,
	text = function(v, _, dur, sum) return Rich(v, v / dur, sum > 0 and v / sum * 100) end,
})
AddMode({
	key = "pk", name = "Joueurs adverses vaincus", group = "Ennemis et JcJ",
	value = function(p) return p.pk or 0 end,
	text = function(v) return ("%d"):format(v) end,
	counts = "pkOn",
})
AddMode({
	key = "heal", name = "Soins et absorptions", group = "Soins", tab = "soins", tl = "th",
	value = HealValue,
	text = function(v, p, dur, sum) return Rich(v, v / PerSecTime(p, dur), sum > 0 and v / sum * 100) end,
	spells = "heals", targets = "healed",
})
AddMode({
	key = "healonly", name = "Soins (hors absorptions)", group = "Soins", tab = "soins",
	value = function(p) return p.heal end,
	text = function(v, p, dur, sum) return Rich(v, v / PerSecTime(p, dur), sum > 0 and v / sum * 100) end,
	spells = "heals", filter = NotShield,
})
AddMode({
	key = "absorb", name = "Absorptions seules", group = "Soins", tab = "soins",
	value = function(p) return p.absorb end,
	text = function(v, _, dur, sum) return Rich(v, v / dur, sum > 0 and v / sum * 100) end,
	spells = "heals", filter = IsShield,
})
AddMode({
	key = "over", name = "Excès de soins (sursoins)", group = "Soins", tab = "soins",
	value = function(p) return p.over end,
	text = function(v, p)
		local all = p.heal + p.over
		return Num(v) .. " (" .. Pct(all > 0 and v / all * 100 or 0) .. " des soins lancés)"
	end,
	spells = "heals", filter = NotShield, spellValue = "over",
})
AddMode({
	key = "hps", name = "SPS (soins par seconde)", group = "Soins", tab = "soins", tl = "th",
	value = function(p, dur) return HealValue(p) / PerSecTime(p, dur) end,
	text = function(v, p) return Num(v) .. " (" .. Num(HealValue(p)) .. ")" end,
	spells = "heals", targets = "healed",
})
AddMode({
	key = "healin", name = "Soins reçus", group = "Soins",
	value = function(p) return p.hin or 0 end,
	text = function(v, _, dur, sum) return Rich(v, v / dur, sum > 0 and v / sum * 100) end,
	targets = "healIn", targetTitle = "Soigné ou protégé par",
})
AddMode({
	key = "kills", name = "Coups fatals", group = "Utilitaire",
	value = function(p) return p.kills or 0 end,
	text = function(v) return ("%d"):format(v) end,
	counts = "killsOn",
})
AddMode({
	key = "rez", name = "Résurrections", group = "Utilitaire",
	value = function(p) return p.rez or 0 end,
	text = function(v) return ("%d"):format(v) end,
	counts = "rezOn",
})
AddMode({
	key = "int", name = "Interruptions", group = "Utilitaire",
	value = function(p) return p.int end,
	text = function(v) return ("%d"):format(v) end,
	counts = "ints",
})
AddMode({
	key = "disp", name = "Dissipations", group = "Utilitaire",
	value = function(p) return p.disp end,
	text = function(v) return ("%d"):format(v) end,
	counts = "disps",
})
AddMode({
	key = "activity", name = "Temps d'activité", group = "Utilitaire",
	value = function(p, dur)
		local v = (p.act or 0) / dur * 100
		return v > 100 and 100 or v
	end,
	text = function(v, p, dur) return Pct(v) .. " (" .. Time(p.act > dur and dur or p.act) .. ")" end,
	fixedMax = 100,
})
AddMode({
	key = "threat", name = "Menace (cible actuelle)", group = "Utilitaire", threat = true,
	text = function(v, row) return Num(v) .. " (" .. ("%d %%"):format(row.pct or 0) .. ")" end,
})

-- Explication de chaque mode en langage simple, et niveau de confiance.
-- { description, exact, essentiel } ; exact = false signale une part d'estimation.
local EXACT = "Chiffre exact : lu tel quel dans le journal de combat du jeu."
local INFO = {
	damage = { "Les dégâts que chaque joueur a infligés aux ennemis. Plus la barre est longue, plus le joueur a fait de dégâts.", true, true },
	dps = { "DPS = dégâts par seconde. C'est la vitesse à laquelle un joueur fait des dégâts : pratique pour comparer des combats de durées différentes.", true, true },
	live = { "Le DPS des toutes dernières secondes. Il monte et descend en direct pendant le combat.", true },
	enemies = { "Les dégâts reçus par chaque ennemi. Permet de voir sur quelle cible le groupe a tapé.", true },
	ff = { "Les dégâts qu'un joueur a infligés à ses propres alliés, souvent à cause d'un effet néfaste qu'il portait sans s'écarter du groupe. Plus c'est bas, mieux c'est.", true, true },
	taken = { "Les dégâts encaissés par chaque joueur. Normal pour un tank ; pour les autres, c'est souvent le signe qu'on est resté dans une zone dangereuse.", true, true },
	takenw = { "Les dégâts subis divisés par les points de vie maximum : « combien de barres de vie ce joueur a perdues ». Permet de comparer un tank et un mage.", true },
	mitig = { "Ce que le tank a évité de subir : dégâts bloqués au bouclier, absorbés par un bouclier magique ou résistés. Un guerrier ou un paladin bloque surtout ; un chevalier de la mort ou un druide absorbe. La réduction due à l'armure n'apparaît pas : le jeu ne la communique pas.", true, true },
	foedmg = { "Les dégâts que chaque ennemi (monstre ou joueur adverse) a infligés à votre groupe. Montre qui vous a fait le plus mal.", true },
	foeheal = { "Les soins lancés par vos ennemis. En JcJ, repère le soigneur adverse à neutraliser.", true },
	pk = { "Les joueurs adverses à qui chacun a porté le coup de grâce.", true },
	avoid = { "La part des attaques ennemies complètement évitées (esquive, parade, raté). Surtout utile pour les tanks.", true },
	takenspell = { "Quels sorts ennemis ont fait le plus mal au groupe entier. Idéal pour comprendre un échec sur un boss.", true },
	deaths = { "Le nombre de morts de chaque joueur. Cliquez sur une barre pour voir ce qui l'a tué.", true, true },
	heal = { "Les points de vie réellement rendus, plus les dégâts évités grâce aux boucliers. C'est le classement de base des soigneurs.",
		false, true, "Soins exacts. La part des boucliers est une estimation : le jeu 3.3.5 n'indique pas quel bouclier a absorbé un coup." },
	healonly = { "Uniquement les points de vie réellement rendus, sans les boucliers et sans l'excès.", true },
	absorb = { "Les dégâts évités grâce aux boucliers (Mot de pouvoir : Bouclier, Egide divine, Bouclier saint...) et aux effets propres aux tanks (Stoïcisme, Défenseur ardent, Volonté de la nécropole, Défense sauvage...).",
		false, false, "Estimation fiable : le jeu 3.3.5 n'indique pas quel bouclier a absorbé un coup, Zénith applique l'ordre de consommation du serveur." },
	over = { "Les soins lancés sur une cible déjà en pleine santé : ils n'ont servi à rien. Un peu d'excès est normal.", true },
	hps = { "SPS = soins par seconde (boucliers compris).", false, false, "Soins exacts, part des boucliers estimée." },
	healin = { "Les soins et protections que chaque joueur a reçus, et de qui.", false, false, "Soins exacts, part des boucliers estimée." },
	kills = { "Qui a porté le coup de grâce aux ennemis.", true },
	rez = { "Qui a ressuscité un allié pendant le combat.", true },
	int = { "Les sorts ennemis interrompus par chaque joueur. Interrompre un sort dangereux aide tout le groupe.", true, true },
	disp = { "Les effets magiques retirés par chaque joueur (maléfices sur les alliés, protections sur les ennemis).", true },
	activity = { "Le temps que chaque joueur a passé à agir pendant le combat. Rester inactif fait perdre des dégâts ou des soins.",
		false, false, "Estimation : un joueur est considéré actif tant qu'il agit au moins toutes les 3,5 secondes." },
	threat = { "La menace de chaque joueur sur votre cible. Si vous dépassez le tank, l'ennemi vous attaque.", true },
}
for key, info in pairs(INFO) do
	local m = Z.modeByKey[key]
	if m then m.desc, m.exact, m.basic, m.note = info[1], info[2], info[3], info[4] or EXACT end
end

-------------------------------------------------------------------------------
-- Collecte des lignes
-------------------------------------------------------------------------------

local function ThreatUnit(out, n, unit)
	if not UnitExists(unit) then return n end
	local _, _, scaled, _, value = UnitDetailedThreatSituation(unit, "target")
	if value and value > 0 then
		n = n + 1
		local row = out[n]
		local _, class = UnitClass(unit)
		row.id, row.name, row.class, row.value, row.p, row.pct, row.spell = UnitGUID(unit), UnitName(unit), class, value / 100, row, scaled, nil
	end
	return n
end

-- Les lignes sont créées à la demande et réutilisées d'un rafraîchissement à l'autre.
local ROWS_MT = { __index = function(t, k)
	local r = {}
	rawset(t, k, r)
	return r
end }

local function Trim(out, n)
	for i = #out, n + 1, -1 do rawset(out, i, nil) end
end

local aggV, aggN = {}, {}

-- Dégâts subis par l'ensemble du groupe, regroupés par sort ennemi.
function Z.CollectTakenSpells(seg, out)
	wipe(aggV)
	for _, p in pairs(seg.players) do
		for id, s in pairs(p.takenBy) do
			if s.tot > 0 then
				aggV[id] = (aggV[id] or 0) + s.tot
				aggN[id] = s.n
			end
		end
	end
	local n, sum = 0, 0
	for id, v in pairs(aggV) do
		n = n + 1
		local row = out[n]
		row.id, row.name, row.class, row.value, row.p, row.pct, row.spell = "s" .. id, aggN[id], nil, v, nil, nil, id
		sum = sum + v
	end
	return n, sum
end

-- Statistiques par ennemi : field = "d" (dégâts infligés au groupe) ou "h" (soins).
function Z.CollectFoes(seg, out, field)
	local n, sum = 0, 0
	if seg.foes then
		for name, f in pairs(seg.foes) do
			local v = f[field] or 0
			if v > 0 then
				n = n + 1
				local row = out[n]
				row.id, row.name, row.class, row.value, row.p, row.pct, row.spell = name, name, f.class or nil, v, nil, nil, nil
				row.foe = f
				sum = sum + v
			end
		end
	end
	return n, sum
end

local function CollectInto(mode, seg, out)
	local n, sum = 0, 0
	if mode.threat then
		if UnitExists("target") and UnitCanAttack("player", "target") then
			n = ThreatUnit(out, n, "player")
			local raid = GetNumRaidMembers()
			if raid > 0 then
				for i = 1, raid do
					local u = Z.RAID[i]
					if not UnitIsUnit(u, "player") then n = ThreatUnit(out, n, u) end
				end
			else
				for i = 1, GetNumPartyMembers() do n = ThreatUnit(out, n, Z.PARTY[i]) end
			end
		end
		for i = 1, n do sum = sum + out[i].value end
		return n, sum
	end
	if not seg then return 0, 0 end
	if mode.collect then return mode.collect(seg, out) end
	if mode.enemies then
		for name, v in pairs(seg.enemies) do
			if v > 0 then
				n = n + 1
				local row = out[n]
				row.id, row.name, row.class, row.value, row.p, row.pct, row.spell = name, name, (seg.eclass and seg.eclass[name]) or nil, v, nil, nil, nil
				sum = sum + v
			end
		end
		return n, sum
	end
	local dur = Z:SegDuration(seg)
	local value = mode.value
	for guid, p in pairs(seg.players) do
		local v = value(p, dur, seg)
		if v and v > 0 then
			n = n + 1
			local row = out[n]
			row.id, row.name, row.class, row.value, row.p, row.pct, row.spell = guid, p.name, p.class, v, p, nil, nil
			sum = sum + v
		end
	end
	return n, sum
end

-- Remplit `out` et renvoie le nombre de lignes et la somme des valeurs.
function Z:Collect(mode, seg, out)
	if not getmetatable(out) then setmetatable(out, ROWS_MT) end
	local n, sum = CollectInto(mode, seg, out)
	Trim(out, n)
	return n, sum
end

-- Classement à l'instant T d'un combat enregistré (relecture).
function Z:CollectReplay(seg, field, T, out)
	local n, sum = 0, 0
	if not getmetatable(out) then setmetatable(out, ROWS_MT) end
	local full = floor(T / Z.BUCKET)
	local frac = T / Z.BUCKET - full
	for guid, p in pairs(seg.players) do
		local t = p[field]
		if t then
			local v = 0
			for i = 1, full do v = v + (t[i] or 0) end
			v = v + (t[full + 1] or 0) * frac
			if v > 0 then
				n = n + 1
				local row = out[n]
				row.id, row.name, row.class, row.value, row.p, row.pct, row.spell = guid, p.name, p.class, v, p, nil, nil
				sum = sum + v
			end
		end
	end
	Trim(out, n)
	return n, sum
end

-------------------------------------------------------------------------------
-- Outils de présentation
-------------------------------------------------------------------------------

function Z.SpellLabel(rec, key)
	local name = rec.n or "Inconnu"
	if rec.pet then name = rec.pet .. " : " .. name end
	if rec.shield then
		name = name .. " (absorption)"
	elseif type(key) == "number" and key < 0 then
		name = name .. " (périodique)"
	end
	return name
end

function Z.SpellIcon(rec)
	local icon
	if rec.id and rec.id >= 1 then
		local _, _, tex = GetSpellInfo(rec.id)
		icon = tex
	end
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local topBuf = {}
local function ByValue(a, b) return a.v > b.v end

-- Trie une table { clé = nombre | { tot = nombre } } ; renvoie une liste réutilisée.
function Z.Top(tbl, filter, field)
	local n = 0
	if tbl then
		for k, v in pairs(tbl) do
			local val = v
			if type(v) == "table" then val = v[field or "tot"] end
			if type(val) == "number" and val > 0 and (not filter or filter(v)) then
				n = n + 1
				local e = topBuf[n]
				if not e then
					e = {}
					topBuf[n] = e
				end
				e.k, e.v, e.rec = k, val, type(v) == "table" and v or nil
			end
		end
	end
	for i = n + 1, #topBuf do topBuf[i] = nil end
	sort(topBuf, ByValue)
	return topBuf, n
end

function Z:RowTooltip(mode, seg, row, tip)
	local r, g, b = Z.ClassColor(row.class)
	tip:AddLine(row.name, r, g, b)
	if row.class and row.p then
		local _, sname, _, role = Z:SpecInfo(row.id, row.class, row.p)
		if sname then tip:AddLine(sname .. (role and (" - " .. Z.RoleName(role)) or ""), 0.7, 0.74, 0.8) end
	end
	local ar, ag, ab = Z.db.accent[1], Z.db.accent[2], Z.db.accent[3]
	if mode.enemies then
		tip:AddLine("Dégâts infligés par", ar, ag, ab)
		local list = {}
		for _, p in pairs(seg.players) do
			local v = p.targets[row.name]
			if v and v > 0 then list[#list + 1] = { p = p, v = v } end
		end
		sort(list, ByValue)
		for i = 1, math.min(#list, 8) do
			local cr, cg, cb = Z.ClassColor(list[i].p.class)
			tip:AddDoubleLine(list[i].p.name, Num(list[i].v) .. " (" .. Pct(list[i].v / row.value * 100) .. ")", cr, cg, cb, 1, 1, 1)
		end
		return
	end
	if mode.key == "foedmg" or mode.key == "foeheal" then
		local f = seg.foes and seg.foes[row.name]
		if f then
			tip:AddDoubleLine("Dégâts infligés au groupe", Num(f.d), 0.8, 0.8, 0.8, 1, 1, 1)
			if f.h > 0 then tip:AddDoubleLine("Soins lancés", Num(f.h), 0.8, 0.8, 0.8, 1, 1, 1) end
			local list, n = Z.Top(f.to)
			if n > 0 then
				tip:AddLine("Ses victimes", ar, ag, ab)
				for i = 1, math.min(n, 8) do
					tip:AddDoubleLine(list[i].k, Num(list[i].v) .. " (" .. Pct(list[i].v / f.d * 100) .. ")", 1, 1, 1, 1, 1, 1)
				end
			end
		end
		return
	end
	if row.spell then
		tip:AddLine("Joueurs touchés", ar, ag, ab)
		local list = {}
		for _, pl in pairs(seg.players) do
			local rec = pl.takenBy[row.spell]
			if rec and rec.tot > 0 then list[#list + 1] = { p = pl, v = rec.tot, n = rec.hit } end
		end
		sort(list, ByValue)
		for i = 1, math.min(#list, 10) do
			local cr, cg, cb = Z.ClassColor(list[i].p.class)
			tip:AddDoubleLine(list[i].p.name, ("%s (%d coups)"):format(Num(list[i].v), list[i].n), cr, cg, cb, 1, 1, 1)
		end
		return
	end
	local p = row.p
	if not p or mode.threat then return end
	if mode.extraTip then mode.extraTip(p, tip) end
	if mode.spells and p[mode.spells] then
		local list, n = Z.Top(p[mode.spells], mode.filter, mode.spellValue)
		if n > 0 then
			tip:AddLine(mode.spellTitle or "Sorts principaux", ar, ag, ab)
			local sum = 0
			for i = 1, n do sum = sum + list[i].v end
			for i = 1, math.min(n, 5) do
				tip:AddDoubleLine(Z.SpellLabel(list[i].rec, list[i].k), Num(list[i].v) .. " (" .. Pct(list[i].v / sum * 100) .. ")", 1, 1, 1, 1, 1, 1)
			end
		end
	end
	if mode.targets and p[mode.targets] then
		local list, n = Z.Top(p[mode.targets])
		if n > 0 then
			tip:AddLine(mode.targetTitle or "Cibles principales", ar, ag, ab)
			for i = 1, math.min(n, 4) do
				tip:AddDoubleLine(list[i].k, Num(list[i].v), 1, 1, 1, 1, 1, 1)
			end
		end
	end
	if mode.counts and p[mode.counts] then
		local list, n = Z.Top(p[mode.counts])
		for i = 1, math.min(n, 6) do
			tip:AddDoubleLine(list[i].k, ("%d"):format(list[i].v), 1, 1, 1, 1, 1, 1)
		end
	end
	if mode.key == "activity" then
		tip:AddLine("Temps passé à agir pendant le combat.", 0.7, 0.7, 0.7)
	end
	tip:AddLine("Clic : détails du joueur", 0.5, 0.5, 0.5)
end

-------------------------------------------------------------------------------
-- Analyse automatique d'un joueur sur un combat
-------------------------------------------------------------------------------

local function Ordinal(n)
	return n == 1 and "1er" or (n .. "e")
end

-- Renvoie une liste de { texte, ton } ; ton = "bon", "mauvais" ou nil.
function Z:Insights(seg, guid)
	local out = {}
	local p = seg.players[guid]
	if not p then return out end
	local dur = Z:SegDuration(seg)
	local function add(text, tone) out[#out + 1] = { text, tone } end

	local healer = (p.heal + p.absorb) > p.dmg
	local field = healer and "soins" or "dégâts"
	local mine = healer and (p.heal + p.absorb) or p.dmg
	local rank, count, sum = 1, 0, 0
	for _, o in pairs(seg.players) do
		local v = healer and (o.heal + o.absorb) or o.dmg
		if v > 0 then
			count = count + 1
			sum = sum + v
			if v > mine then rank = rank + 1 end
		end
	end
	if mine > 0 and count > 0 then
		add(("Classement : %s sur %d aux %s, soit %s du total du groupe."):format(
			Ordinal(rank), count, field, Pct(mine / sum * 100)), rank == 1 and "bon" or nil)
		if count > 1 then
			local avg = sum / count
			local diff = (mine - avg) / avg * 100
			add(("%s : %s, soit %s %s de la moyenne du groupe."):format(
				healer and "SPS" or "DPS", Num(mine / dur), Pct(math.abs(diff)), diff >= 0 and "au-dessus" or "en dessous"),
				diff >= 0 and "bon" or "mauvais")
		else
			add(("%s : %s sur %s de combat."):format(healer and "SPS" or "DPS", Num(mine / dur), Time(dur)))
		end
	end

	if seg ~= Z.char.total then
		local text, clean = Z:QualityText(seg)
		if not clean then add(text, "mauvais") end
	end

	local act = (p.act or 0) / dur * 100
	if act > 100 then act = 100 end
	if act >= 85 then
		add(("Temps d'activité : %s du combat. Excellent rythme."):format(Pct(act)), "bon")
	elseif act >= 65 then
		add(("Temps d'activité : %s du combat."):format(Pct(act)))
	else
		add(("Temps d'activité : %s seulement. Chaque seconde d'inaction est une perte sèche."):format(Pct(act)), "mauvais")
	end

	local list, n = Z.Top(healer and p.heals or p.spells)
	if n > 0 then
		local top = list[1]
		local total = 0
		for i = 1, n do total = total + list[i].v end
		local rec = top.rec
		add(("Sort principal : %s (%s du total, %s de critiques)."):format(
			Z.SpellLabel(rec, top.k), Pct(top.v / total * 100), Pct(rec.hit > 0 and rec.crit / rec.hit * 100 or 0)))
		local hits, miss = 0, 0
		for i = 1, n do
			hits = hits + list[i].rec.hit
			miss = miss + (list[i].rec.miss or 0)
		end
		if not healer and miss > 0 and hits + miss >= 20 and miss / (hits + miss) > 0.06 then
			add(("Attaques ratées, esquivées ou parées : %s. Vérifiez vos scores de toucher et d'expertise."):format(
				Pct(miss / (hits + miss) * 100)), "mauvais")
		end
	end

	if not healer and p.dmg > 0 then
		local ok, abs = p.ok or 0, p.dAbs or 0
		if ok > 0 then
			add(("Dégâts utiles : %s. L'excédent sur les coups fatals (%s, soit %s) dépasse la vie restante des cibles."):format(
				Num(p.dmg - ok), Num(ok), Pct(ok / p.dmg * 100)))
		end
		if abs > 0 then
			add(("Dégâts absorbés par les boucliers ennemis : %s, non comptés dans le total."):format(Num(abs)))
		end
	end

	if p.dots and seg ~= Z.char.total then
		local best, bestUp = nil, 0
		for _, a in pairs(p.dots) do
			local up = Z.AuraUp(seg, a)
			if up > bestUp then best, bestUp = a, up end
		end
		if best then
			local pct = bestUp / dur * 100
			add(("Affaiblissement le mieux maintenu : %s, actif %s du combat."):format(best.n, Pct(pct > 100 and 100 or pct)))
		end
	end

	local t = healer and p.th or p.td
	if t and #t > 1 then
		local best, at = 0, 1
		for i = 1, #t do
			if (t[i] or 0) > best then best, at = t[i], i end
		end
		add(("Meilleure séquence : %s %s vers %s."):format(Num(best / Z.BUCKET), healer and "SPS" or "DPS", Time((at - 1) * Z.BUCKET)))
	end

	if healer and (p.heal + p.over) > 0 then
		local over = p.over / (p.heal + p.over) * 100
		add(("Sursoins : %s des soins lancés."):format(Pct(over)), over > 45 and "mauvais" or nil)
		if p.absorb > 0 then add(("Absorptions : %s de dégâts évités."):format(Num(p.absorb)), "bon") end
	end

	if p.taken > 0 then
		local tl, tn = Z.Top(p.takenBy)
		if tn > 0 then
			add(("Dégâts subis : %s, principalement %s (%s)."):format(Num(p.taken), tl[1].rec.n, Pct(tl[1].v / p.taken * 100)))
		end
	end
	if p.taken > 0 then
		local t = Z:TankStats(p)
		if t.mit > 0 or t.avoided > 0 then
			add(("Défense : %s atténués sur %s bruts (%s), %s des attaques évitées."):format(
				Num(t.mit), Num(t.raw), Pct(t.mitPct), Pct(t.avoidPct)))
		end
		if p.hpMax and p.hpMax > 0 then
			add(("Dégâts subis pondérés : %s fois les points de vie maximum."):format(Comma(("%.1f"):format(p.taken / p.hpMax))))
		end
	end
	if p.ff > 0 then
		local fl, fn = Z.Top(p.ffSpells)
		add(("Dégâts infligés aux alliés : %s%s."):format(Num(p.ff),
			fn > 0 and (", surtout par " .. Z.SpellLabel(fl[1].rec, fl[1].k)) or ""), "mauvais")
	end
	if p.int > 0 then add(("Interruptions réussies : %d."):format(p.int), "bon") end
	if p.disp > 0 then add(("Dissipations : %d."):format(p.disp), "bon") end

	for _, d in ipairs(seg.deaths) do
		if d.guid == guid then
			local last
			for i = #d.log, 1, -1 do
				if d.log[i].a < 0 then
					last = d.log[i]
					break
				end
			end
			if last then
				add(("Mort à %s : coup fatal %s (%s) pour %s."):format(Time(d.t), last.s or "?", last.f or "?", Num(-last.a)), "mauvais")
			else
				add(("Mort à %s."):format(Time(d.t)), "mauvais")
			end
		end
	end
	if p.deaths == 0 and seg ~= Z.char.total and not seg.active then add("Aucune mort sur ce combat.", "bon") end
	if seg.record and guid == Z.playerGUID then add("Nouveau record personnel sur ce boss !", "bon") end
	if seg ~= Z.char.total then
		local text, clean = Z:QualityText(seg)
		if clean then add(text, "bon") end
	end

	return out
end
