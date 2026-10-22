-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Panneau de détails d'un joueur : fiche complète de chaque sort
-- (dégâts, soins, dégâts subis, dégâts aux alliés), cibles, graphique,
-- journal des morts et analyse automatique.

local ADDON, ns = ...
local Z = ns.Z
local UI = Z.UI

local floor, max, min, pairs = math.floor, math.max, math.min, pairs
local Num, Pct, Time = Z.Num, Z.Pct, Z.Time
local sort = table.sort

local W, H = 660, 480
local TOP = 74 -- début de la zone de contenu
local CW, CH = W - 24, H - TOP - 30

local TABS = {
	{ key = "degats", name = "Dégâts" },
	{ key = "soins", name = "Soins" },
	{ key = "subis", name = "Dégâts subis" },
	{ key = "allies", name = "Sur alliés" },
	{ key = "auras", name = "Auras" },
	{ key = "graphique", name = "Graphique" },
	{ key = "morts", name = "Morts" },
	{ key = "analyse", name = "Analyse" },
}

local SCHOOL_COLORS = {
	[1] = { 0.82, 0.72, 0.52 }, [2] = { 1.00, 0.90, 0.50 }, [4] = { 1.00, 0.47, 0.22 }, [8] = { 0.42, 0.90, 0.42 },
	[16] = { 0.45, 0.76, 1.00 }, [32] = { 0.62, 0.47, 0.92 }, [64] = { 0.92, 0.52, 0.92 },
}

local D

local function Copy(list, n, out)
	for i = 1, n do
		local e = out[i]
		if not e then
			e = {}
			out[i] = e
		end
		e.k, e.v, e.rec = list[i].k, list[i].v, list[i].rec
	end
	for i = n + 1, #out do out[i] = nil end
	return out
end

local MISS_NAMES = {
	MISS = "Raté", DODGE = "Esquivé", PARRY = "Paré", BLOCK = "Bloqué", RESIST = "Résisté", ABSORB = "Absorbé",
	IMMUNE = "Insensible", DEFLECT = "Dévié", EVADE = "Évité", REFLECT = "Renvoyé",
}
local MAX_LINES = 15
local SPELL_TABS = { degats = true, soins = true, subis = true, allies = true }

-------------------------------------------------------------------------------
-- Vues
-------------------------------------------------------------------------------

local spellRows, targetRows, buf = {}, {}, {}
local lines, missBuf = {}, {}

local function ByCount(a, b) return a.n > b.n end

-- Fiche complète d'un sort : remplit `lines` avec des paires { libellé, valeur }.
local function SpellLines(rec, tab, share)
	local n = 0
	local function add(label, value)
		if n >= MAX_LINES then return end
		n = n + 1
		local l = lines[n]
		if not l then
			l = {}
			lines[n] = l
		end
		l[1], l[2] = label, value
	end
	local hits = rec.hit or 0
	local miss = rec.miss or 0
	add("Total", Num(rec.tot) .. " (" .. Pct(share) .. ")")
	add(tab == "soins" and "Soins et ticks" or (tab == "subis" and "Coups reçus" or "Coups portés"), ("%d"):format(hits))
	if hits > 0 then
		add("Moyenne par coup", Num(rec.tot / hits))
		local crits = rec.crit or 0
		if rec.ca and crits > 0 and hits > crits then
			add("Moyenne normale / critique", Num((rec.tot - rec.ca) / (hits - crits)) .. " / " .. Num(rec.ca / crits))
		end
		if rec.min then add("Minimum / maximum", Num(rec.min) .. " / " .. Num(rec.max or 0)) end
		add("Critiques", ("%d (%s)"):format(rec.crit or 0, Pct((rec.crit or 0) / hits * 100)))
		if rec.gl then add("Éraflures", ("%d (%s)"):format(rec.gl, Pct(rec.gl / hits * 100))) end
		if rec.cr then add("Coups écrasants", ("%d (%s)"):format(rec.cr, Pct(rec.cr / hits * 100))) end
	end
	if tab == "soins" then
		if rec.shield then
			add("Nature", "Absorption (bouclier)")
		else
			local over = rec.over or 0
			add("Excès de soins", Num(over) .. " (" .. Pct(rec.tot + over > 0 and over / (rec.tot + over) * 100 or 0) .. ")")
			add("Soins lancés (brut)", Num(rec.tot + over))
		end
	else
		if miss > 0 then
			add(tab == "subis" and "Attaques évitées ou annulées" or "Attaques sans effet",
				("%d (%s)"):format(miss, Pct(miss / (hits + miss) * 100)))
			local k = 0
			if rec.m then
				for kind, count in pairs(rec.m) do
					k = k + 1
					local e = missBuf[k]
					if not e then
						e = {}
						missBuf[k] = e
					end
					e.kind, e.n = kind, count
				end
			end
			for i = k + 1, #missBuf do missBuf[i] = nil end
			sort(missBuf, ByCount)
			for i = 1, k do add("   " .. (MISS_NAMES[missBuf[i].kind] or missBuf[i].kind), ("%d"):format(missBuf[i].n)) end
		end
		if rec.ok and rec.ok > 0 then add("Excédent sur coup fatal", Num(rec.ok) .. " (" .. Pct(rec.ok / rec.tot * 100) .. ")") end
		if rec.abs and rec.abs > 0 then add("Montant absorbé", Num(rec.abs)) end
		if rec.blk and rec.blk > 0 then add("Montant bloqué", Num(rec.blk)) end
		if rec.res and rec.res > 0 then add("Montant résisté", Num(rec.res)) end
		if tab == "subis" and rec.src then add("Dernière source", rec.src) end
	end
	return n
end

local function ShowLines(n)
	local box = D.detail
	for i = 1, MAX_LINES do
		local l = box.rows[i]
		if i <= n then
			UI.SetFont(l.label, 11)
			UI.SetFont(l.value, 11)
			l.label:SetText(lines[i][1])
			l.value:SetText(lines[i][2])
			l.label:Show()
			l.value:Show()
		else
			l.label:Hide()
			l.value:Hide()
		end
	end
end

local function Summary(seg, p, tab)
	local dur = Z:SegDuration(seg)
	if tab == "degats" then
		local hits, crit, miss = 0, 0, 0
		for _, s in pairs(p.spells) do
			hits, crit, miss = hits + s.hit, crit + s.crit, miss + (s.miss or 0)
		end
		return ("Total : %s   -   DPS : %s   -   Critiques : %s   -   Sans effet : %s"):format(
			Num(p.dmg), Num(p.dmg / dur), Pct(hits > 0 and crit / hits * 100 or 0), Pct(hits + miss > 0 and miss / (hits + miss) * 100 or 0))
	elseif tab == "soins" then
		local cast = p.heal + p.over
		return ("Soins : %s   -   Absorptions : %s   -   Ensemble : %s   -   Excès : %s (%s)"):format(
			Num(p.heal), Num(p.absorb), Num(p.heal + p.absorb), Num(p.over), Pct(cast > 0 and p.over / cast * 100 or 0))
	elseif tab == "subis" then
		local t = Z:TankStats(p)
		local w = p.hpMax and p.hpMax > 0 and ("   -   Pondéré : " .. Z.Comma(("%.1f"):format(p.taken / p.hpMax)) .. " x PV max") or ""
		return ("Subis : %s   -   Brut : %s   -   Atténué : %s (%s)   -   Évitement : %s%s"):format(
			Num(p.taken), Num(t.raw), Num(t.mit), Pct(t.mitPct), Pct(t.avoidPct), w)
	end
	return ("Dégâts infligés aux alliés : %s (les dégâts sur soi-même ne sont pas comptés)"):format(Num(p.ff))
end

local function FillSpells(seg, p, tab)
	local tbl = (tab == "degats" and p.spells) or (tab == "soins" and p.heals) or (tab == "subis" and p.takenBy) or p.ffSpells
	local list, n = Z.Top(tbl)
	Copy(list, n, buf)
	local sum = 0
	for i = 1, n do sum = sum + buf[i].v end
	local top = n > 0 and buf[1].v or 1
	local selected
	for i = 1, n do
		if buf[i].k == D.selKey then selected = i end
	end
	if not selected and n > 0 then
		selected = 1
		D.selKey = buf[1].k
	end
	local ar, ag, ab = UI.Accent()
	for i = 1, n do
		local e = buf[i]
		local d = spellRows[i]
		if not d then
			d = {}
			spellRows[i] = d
		end
		d.rec, d.key = e.rec, e.k
		d.label = Z.SpellLabel(e.rec, e.k)
		if i == selected then d.label = Z.Hex(ar, ag, ab) .. d.label .. "|r" end
		d.text = Num(e.v) .. " (" .. Pct(e.v / sum * 100) .. ")"
		d.frac = e.v / top
		d.icon, d.coords = Z.SpellIcon(e.rec), nil
		local c
		if tab == "soins" then
			c = e.rec.shield and { 0.92, 0.85, 0.42 } or { 0.30, 0.85, 0.52 }
		elseif tab == "subis" or tab == "allies" then
			c = { 0.86, 0.32, 0.28 }
		else
			c = SCHOOL_COLORS[e.rec.sc or 1] or { 0.75, 0.6, 0.85 }
		end
		d.r, d.g, d.b = c[1], c[2], c[3]
	end
	D.spells:SetData(spellRows, n)
	local heads = { degats = "Sorts", soins = "Sorts de soin et boucliers", subis = "Sorts subis", allies = "Sorts et debuffs responsables" }
	D.spellHead:SetText(heads[tab] .. (n > 0 and ("  (" .. n .. ")  -  cliquez pour le détail") or ""))
	D.summary:SetText(Summary(seg, p, tab))
	if selected then
		D.detailHead:SetText(Z.SpellLabel(buf[selected].rec, buf[selected].k))
		ShowLines(SpellLines(buf[selected].rec, tab, buf[selected].v / sum * 100))
	else
		D.detailHead:SetText("Détail du sort")
		ShowLines(0)
	end

	-- Colonne de droite : cibles, joueurs soignés, sources ou alliés touchés
	local tt
	if tab == "degats" then
		tt = p.targets
		D.targetHead:SetText("Cibles")
	elseif tab == "soins" then
		tt = p.healed
		D.targetHead:SetText("Joueurs soignés ou protégés")
	elseif tab == "allies" then
		tt = p.ffTo
		D.targetHead:SetText("Alliés touchés")
	else
		tt = {}
		for _, s in pairs(p.takenBy) do
			if s.src and s.tot > 0 then tt[s.src] = (tt[s.src] or 0) + s.tot end
		end
		D.targetHead:SetText("Sources")
	end
	list, n = Z.Top(tt)
	Copy(list, n, buf)
	sum = 0
	for i = 1, n do sum = sum + buf[i].v end
	top = n > 0 and buf[1].v or 1
	for i = 1, n do
		local e = buf[i]
		local d = targetRows[i]
		if not d then
			d = {}
			targetRows[i] = d
		end
		d.label = e.k
		d.text = Num(e.v) .. " (" .. Pct(e.v / sum * 100) .. ")"
		d.frac = e.v / top
		d.r, d.g, d.b = 0.42, 0.50, 0.62
	end
	D.targets:SetData(targetRows, n)
end

local auraLeft, auraRight = {}, {}
local function ByUptime(a, b) return a.sortv > b.sortv end

local function AuraRows(seg, tbl, out, n, dur, prefix, r, g, b)
	if tbl then
		for id, a in pairs(tbl) do
			local up = Z.AuraUp(seg, a)
			if up > 0 then
				n = n + 1
				local d = out[n]
				if not d then
					d = {}
					out[n] = d
				end
				local pct = up / dur * 100
				if pct > 100 then pct = 100 end
				d.sortv = pct
				d.label = (prefix or "") .. (a.n or "?")
				d.text = Pct(pct) .. "  (" .. a.c .. " fois)"
				d.frac = pct / 100
				d.r, d.g, d.b = r, g, b
				d.icon, d.coords = nil, nil
				if type(id) == "number" and id >= 1 then
					local _, _, tex = GetSpellInfo(id)
					d.icon = tex
				end
			end
		end
	end
	return n
end

-- Temps d'effet des améliorations et des affaiblissements, en part de la durée du combat.
local function FillAuras(seg, p)
	local dur = Z:SegDuration(seg)
	local n = AuraRows(seg, p.buffs, auraLeft, 0, dur, nil, 0.30, 0.62, 0.86)
	for i = #auraLeft, n + 1, -1 do auraLeft[i] = nil end
	sort(auraLeft, ByUptime)
	D.spells:SetData(auraLeft, n)
	local m = AuraRows(seg, p.dots, auraRight, 0, dur, nil, 0.92, 0.60, 0.25)
	local posed = m
	m = AuraRows(seg, p.debuffs, auraRight, m, dur, "Subi : ", 0.80, 0.30, 0.30)
	for i = #auraRight, m + 1, -1 do auraRight[i] = nil end
	sort(auraRight, ByUptime)
	D.auraList:SetData(auraRight, m)
	D.spellHead:SetText("Améliorations portées" .. (n > 0 and ("  (" .. n .. ")") or ""))
	D.detailHead:SetText(("Affaiblissements : %d posés, %d subis"):format(posed, m - posed))
	D.summary:SetText("Temps d'effet en part de la durée du combat ; entre parenthèses, le nombre d'applications.")
	if n == 0 and m == 0 then
		D.msg:SetText((seg == Z.char.total and "Les améliorations et affaiblissements sont suivis par combat : choisissez un combat précis.")
			or (not Z.db.trackAuras and "Le suivi des améliorations est désactivé (Options > Combat).")
			or "Aucune amélioration ni aucun affaiblissement enregistré pour ce joueur.")
		D.msg:Show()
	end
end

local graphVals = {}

local function FillGraph(seg, p)
	local g = D.graph
	local healer = (p.heal + p.absorb) > p.dmg
	local t = healer and p.th or p.td
	for i = 1, #g.cols do g.cols[i]:Hide() end
	for i = 1, #g.marks do g.marks[i]:Hide() end
	g.avg:Hide()
	if not t or #t == 0 then
		g.info:SetText(seg == Z.char.total and "Le graphique est disponible pour un combat précis, pas pour le total."
			or "Aucune donnée chronologique pour ce joueur.")
		g.axisL:SetText("")
		g.axisR:SetText("")
		return
	end
	local unit = healer and "SPS" or "DPS"
	local dur = Z:SegDuration(seg)
	local nb = max(#t, math.ceil(dur / Z.BUCKET))
	local group = 1
	while nb / group > 160 do group = group + 1 end
	local cols = math.ceil(nb / group)
	local gw, gh = CW, CH - 44
	local cw = gw / cols
	local peak, total = 0, 0
	local vals = graphVals
	for c = 1, cols do
		local v = 0
		for i = (c - 1) * group + 1, min(nb, c * group) do v = v + (t[i] or 0) end
		v = v / (group * Z.BUCKET)
		vals[c] = v
		if v > peak then peak = v end
		total = total + v
	end
	if peak <= 0 then peak = 1 end
	local r, gg, b = Z.ClassColor(p.class)
	for c = 1, cols do
		local tex = g.cols[c]
		if not tex then
			tex = g:CreateTexture(nil, "ARTWORK")
			tex:SetTexture("Interface\\Buttons\\WHITE8X8")
			g.cols[c] = tex
		end
		local h = max(1, vals[c] / peak * gh)
		tex:ClearAllPoints()
		tex:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", (c - 1) * cw, 18)
		tex:SetWidth(max(1, cw - (cw > 3 and 1 or 0)))
		tex:SetHeight(h)
		tex:SetGradientAlpha("VERTICAL", r * 0.35, gg * 0.35, b * 0.35, 0.9, r, gg, b, 1)
		tex:Show()
	end
	local avg = total / cols
	g.avg:ClearAllPoints()
	g.avg:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 18 + avg / peak * gh)
	g.avg:SetWidth(gw)
	g.avg:SetVertexColor(UI.Accent())
	g.avg:Show()
	g.shown = cols
	local m = 0
	for _, d in ipairs(seg.deaths) do
		if d.guid == D.guid then
			m = m + 1
			local mark = g.marks[m]
			if not mark then
				mark = UI.Solid(g, "OVERLAY", 1, 0.25, 0.2, 0.9)
				mark:SetWidth(2)
				g.marks[m] = mark
			end
			mark:ClearAllPoints()
			mark:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", min(gw - 2, d.t / (nb * Z.BUCKET) * gw), 18)
			mark:SetHeight(gh)
			mark:Show()
		end
	end
	g.info:SetText(("%s par tranche de %d s  -  Pic : %s  -  Moyenne : %s%s"):format(
		unit, group * Z.BUCKET, Num(peak), Num(avg), m > 0 and "  -  trait rouge : mort" or ""))
	g.axisL:SetText("0:00")
	g.axisR:SetText(Time(dur))
end

local deathRows, logRows = {}, {}

local function FillLog(death)
	local n = 0
	if death then
		for i = #death.log, 1, -1 do
			local e = death.log[i]
			n = n + 1
			local d = logRows[n]
			if not d then
				d = {}
				logRows[n] = d
			end
			local dmg = e.a < 0
			d.label = ("%s s   %s (%s)"):format((("%.1f"):format(e.t)):gsub("%.", ","), e.s or "?", e.f or "?")
			d.text = (dmg and "|cffff6b5e-" or "|cff55e07a+") .. Num(math.abs(e.a)) .. "|r   PV " .. (e.hp or 0) .. " %"
			d.frac = (e.hp or 0) / 100
			if dmg then d.r, d.g, d.b = 0.75, 0.25, 0.22 else d.r, d.g, d.b = 0.22, 0.65, 0.38 end
		end
	end
	D.log:SetData(logRows, n)
	D.logHead:SetText(death and ("Derniers événements avant la mort à " .. Time(death.t)) or "Derniers événements")
end

local function FillDeaths(seg)
	local n = 0
	for _, death in ipairs(seg.deaths) do
		if death.guid == D.guid then
			n = n + 1
			local d = deathRows[n]
			if not d then
				d = {}
				deathRows[n] = d
			end
			d.death = death
			d.label = ("Mort n° %d"):format(n)
			d.text = Time(death.t)
			d.frac = 1
			if D.death == death then d.r, d.g, d.b = UI.Accent() else d.r, d.g, d.b = 0.35, 0.2, 0.2 end
		end
	end
	if n > 0 and not D.death then
		D.death = deathRows[1].death
		deathRows[1].r, deathRows[1].g, deathRows[1].b = UI.Accent()
	end
	D.deaths:SetData(deathRows, n)
	FillLog(D.death)
	if n == 0 then
		D.msg:SetText(seg == Z.char.total and "Le journal des morts est conservé par combat : choisissez un combat précis."
			or "Ce joueur n'est pas mort pendant ce combat.")
		D.msg:Show()
	end
end

local TONES = { bon = { 0.33, 0.88, 0.48 }, mauvais = { 1.00, 0.42, 0.37 } }

local function FillInsights(seg)
	local list = Z:Insights(seg, D.guid)
	local a = D.analyse
	local y = 0
	for i = 1, max(#list, #a.lines) do
		local line = a.lines[i]
		local item = list[i]
		if item and y + UI.TextHeight(item[1], CW - 20, 12) > CH then item = nil end
		if item then
			if not line then
				line = { dot = UI.Solid(a, "ARTWORK", 1, 1, 1, 1), text = UI.Text(a, 12) }
				line.dot:SetWidth(4)
				line.dot:SetHeight(12)
				line.text:SetJustifyH("LEFT")
				line.text:SetWidth(CW - 20)
				a.lines[i] = line
			end
			UI.SetFont(line.text, 12)
			local h = UI.SetBlock(line.text, item[1], CW - 20, 12)
			local c = TONES[item[2]]
			if c then
				line.dot:SetVertexColor(c[1], c[2], c[3])
			else
				line.dot:SetVertexColor(UI.Accent())
			end
			line.dot:ClearAllPoints()
			line.dot:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -y - 1)
			line.text:ClearAllPoints()
			line.text:SetPoint("TOPLEFT", a, "TOPLEFT", 14, -y)
			line.dot:Show()
			line.text:Show()
			y = y + h + 7
		elseif line then
			line.dot:Hide()
			line.text:Hide()
		end
	end
end

-------------------------------------------------------------------------------
-- Construction et mise à jour
-------------------------------------------------------------------------------

local function Build()
	D = UI.Panel("ZenithDetail", W, H, "")
	D.tabs = {}
	local tw = floor((W - 24 - (#TABS - 1) * 4) / #TABS)
	for i, t in ipairs(TABS) do
		local b = UI.Button(D, t.name, tw, 22, function()
			D.tab, D.selKey = t.key, nil
			D:Update()
		end)
		b:SetPoint("TOPLEFT", D, "TOPLEFT", 12 + (i - 1) * (tw + 4), -40)
		D.tabs[t.key] = b
	end

	local function Head(x, dy)
		local fs = UI.Text(D, 11)
		fs:SetPoint("TOPLEFT", D, "TOPLEFT", x, -TOP - (dy or 0))
		fs:SetTextColor(0.6, 0.65, 0.72)
		return fs
	end
	local lw = 350
	local rw = CW - lw - 10
	local LH = H - TOP - 36 - 14 -- hauteur des listes de sorts
	local BOX = MAX_LINES * 13 + 6
	local opt = { rowHeight = 18, spacing = 1, fontSize = 11, icons = true }
	local optPlain = { rowHeight = 18, spacing = 1, fontSize = 11, icons = false }

	D.summary = UI.Text(D, 11)
	D.summary:SetPoint("TOPLEFT", D, "TOPLEFT", 12, -TOP)
	D.summary:SetTextColor(0.86, 0.89, 0.93)
	D.summary:SetWidth(CW)
	D.summary:SetHeight(13)
	D.summary:SetJustifyH("LEFT")
	D.spellHead = Head(12, 20)
	D.spellHead:SetWidth(lw)
	D.spellHead:SetHeight(13)
	D.spellHead:SetJustifyH("LEFT")
	D.detailHead = Head(12 + lw + 10, 20)
	D.detailHead:SetWidth(rw)
	D.detailHead:SetHeight(13)
	D.detailHead:SetJustifyH("LEFT")
	D.spells = UI.BarList(D, opt)
	D.spells.f:SetPoint("TOPLEFT", D, "TOPLEFT", 12, -TOP - 36)
	D.spells:SetSize(lw, LH)
	D.spells.onClick = function(d)
		D.selKey = d.key
		D:Update()
	end

	-- Fiche du sort sélectionné
	local box = CreateFrame("Frame", nil, D)
	D.detail = box
	box:SetPoint("TOPLEFT", D, "TOPLEFT", 12 + lw + 10, -TOP - 36)
	box:SetWidth(rw)
	box:SetHeight(BOX)
	box.bg = UI.Solid(box, "BACKGROUND", 1, 1, 1, 0.04)
	box.bg:SetAllPoints(box)
	box.rows = {}
	for i = 1, MAX_LINES do
		local label = UI.Text(box, 11)
		label:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -3 - (i - 1) * 13)
		label:SetTextColor(0.66, 0.70, 0.77)
		local value = UI.Text(box, 11)
		value:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -3 - (i - 1) * 13)
		box.rows[i] = { label = label, value = value }
	end

	D.auraList = UI.BarList(D, opt)
	D.auraList.f:SetPoint("TOPLEFT", D, "TOPLEFT", 12 + lw + 10, -TOP - 36)
	D.auraList:SetSize(rw, LH)

	D.targetHead = Head(12 + lw + 10, 36 + BOX + 6)
	D.targets = UI.BarList(D, optPlain)
	D.targets.f:SetPoint("TOPLEFT", D, "TOPLEFT", 12 + lw + 10, -TOP - 36 - BOX - 22)
	D.targets:SetSize(rw, LH - BOX - 22)

	D.deathHead = Head(12)
	D.deathHead:SetText("Morts")
	D.logHead = Head(12 + 150 + 10)
	D.deaths = UI.BarList(D, optPlain)
	D.deaths.f:SetPoint("TOPLEFT", D, "TOPLEFT", 12, -TOP - 16)
	D.deaths:SetSize(150, CH)
	D.deaths.onClick = function(d)
		D.death = d.death
		D:Update()
	end
	D.log = UI.BarList(D, { rowHeight = 16, spacing = 1, fontSize = 10, icons = false, static = true })
	D.log.f:SetPoint("TOPLEFT", D, "TOPLEFT", 12 + 150 + 10, -TOP - 16)
	D.log:SetSize(CW - 160, CH)

	local g = CreateFrame("Frame", nil, D)
	D.graph = g
	g:SetPoint("TOPLEFT", D, "TOPLEFT", 12, -TOP)
	g:SetWidth(CW)
	g:SetHeight(CH + 16)
	g.cols, g.marks = {}, {}
	g.base = UI.Solid(g, "BORDER", 1, 1, 1, 0.15)
	g.base:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 17)
	g.base:SetWidth(CW)
	g.base:SetHeight(1)
	g.avg = UI.Solid(g, "OVERLAY", 1, 1, 1, 0.7)
	g.avg:SetHeight(1)
	g.info = UI.Text(g, 11)
	g.info:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
	g.info:SetTextColor(0.75, 0.79, 0.85)
	g.axisL = UI.Text(g, 10)
	g.axisL:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 2)
	g.axisL:SetTextColor(0.55, 0.6, 0.68)
	g.axisR = UI.Text(g, 10)
	g.axisR:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 2)
	g.axisR:SetTextColor(0.55, 0.6, 0.68)

	local a = CreateFrame("Frame", nil, D)
	D.analyse = a
	a:SetPoint("TOPLEFT", D, "TOPLEFT", 16, -TOP - 6)
	a:SetWidth(CW - 8)
	a:SetHeight(CH)
	a.lines = {}

	D.msg = UI.Text(D, 12)
	D.msg:SetPoint("CENTER", D, "CENTER", 0, -30)
	D.msg:SetWidth(CW - 80)
	D.msg:SetTextColor(0.55, 0.6, 0.68)

	function D:Update()
		local seg, guid = self.seg, self.guid
		local p = seg and seg.players[guid]
		self:Paint()
		for key, b in pairs(self.tabs) do
			b.active = key == self.tab
			b:Paint(false)
		end
		local tab = self.tab
		local spellTab = SPELL_TABS[tab] or false
		local function Vis(frame, on)
			if on then frame:Show() else frame:Hide() end
		end
		local auraTab = tab == "auras"
		Vis(self.spells.f, spellTab or auraTab)
		Vis(self.targets.f, spellTab)
		Vis(self.spellHead, spellTab or auraTab)
		Vis(self.targetHead, spellTab)
		Vis(self.summary, spellTab or auraTab)
		Vis(self.detailHead, spellTab or auraTab)
		Vis(self.detail, spellTab)
		Vis(self.auraList.f, auraTab)
		Vis(self.deaths.f, tab == "morts")
		Vis(self.log.f, tab == "morts")
		Vis(self.deathHead, tab == "morts")
		Vis(self.logHead, tab == "morts")
		Vis(self.graph, tab == "graphique")
		Vis(self.analyse, tab == "analyse")
		self.msg:Hide()
		if not p then
			self.title:SetText("Joueur introuvable")
			self.sub:SetText("")
			return
		end
		local r, g2, b2 = Z.ClassColor(p.class)
		local _, sname, _, role = Z:SpecInfo(guid, p.class, p)
		self.title:SetText(Z.Hex(r, g2, b2) .. p.name .. "|r"
			.. (sname and ("  |cff8d97a6" .. sname .. (role and (" - " .. Z.RoleName(role)) or "") .. "|r") or ""))
		self.sub:SetText(Z:SegName(seg) .. "  -  " .. Time(Z:SegDuration(seg)))
		-- Les lignes ne sont remises en forme qu'après un changement de réglage.
		if self.restyle then
			self.restyle = nil
			self.spells.styled = self.spells.styled + 1
			self.targets.styled = self.targets.styled + 1
			self.deaths.styled = self.deaths.styled + 1
			self.log.styled = self.log.styled + 1
			self.auraList.styled = self.auraList.styled + 1
		end
		if spellTab then
			FillSpells(seg, p, tab)
			if self.spells.n == 0 then
				self.msg:SetText(tab == "allies" and "Ce joueur n'a infligé aucun dégât à ses alliés."
					or "Aucune donnée dans cette catégorie pour ce joueur.")
				self.msg:Show()
			end
		elseif auraTab then
			FillAuras(seg, p)
		elseif tab == "graphique" then
			FillGraph(seg, p)
		elseif tab == "morts" then
			FillDeaths(seg)
		else
			FillInsights(seg)
		end
	end

	-- Mise à jour en direct tant que le combat affiché est en cours.
	local acc = 0
	D:SetScript("OnUpdate", function(self, elapsed)
		acc = acc + elapsed
		if acc >= 1 then
			acc = 0
			if self.seg and (self.seg.active or self.seg == Z.char.total and Z.current) then self:Update() end
		end
	end)
	Z:On("SETTINGS", function()
		D.restyle = true
		if D:IsShown() then D:Update() end
	end)
	Z:On("SYNC", function(seg)
		if D:IsShown() and D.seg == seg and not seg.active then D:Update() end
	end)
	D.restyle = true
end

function Z:ShowDetail(seg, guid, tab)
	if not seg or not seg.players[guid] then return end
	if not D then Build() end
	if D:IsShown() and D.seg == seg and D.guid == guid and (not tab or tab == D.tab) then
		D:Hide()
		return
	end
	D.seg, D.guid, D.death, D.selKey = seg, guid, nil, nil
	D.tab = tab or D.tab or "degats"
	D:Update()
	D:Show()
end
