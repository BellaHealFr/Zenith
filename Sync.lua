-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Zénith » réservé) : voir LICENSE et NOTICE.md.

-- Zénith - Synchronisation de groupe (client 3.3.5)
-- Chaque joueur annonce à son groupe ce qu'il a lui-même fait : son client voit
-- tous ses coups, ceux de ses familiers et ceux qu'il reçoit, quelle que soit la
-- distance. Les autres complètent ce que leur journal a manqué (Combat.lua).
--
-- Message : version;type;début;fin;dégâts;soins;excès;absorptions;subis;activité;boucliers
--   type      : L (combat en cours, toutes les 2 s si quelque chose a changé) ou F (terminé)
--   début, fin: secondes écoulées depuis le début et la fin du combat de l'émetteur
--   boucliers : absorptions reçues, par lanceur ("Nom:montant,Nom:montant"), les plus
--               fortes d'abord tant que le message tient dans la limite du jeu
-- Rencontres de boss, pour un coéquipier trop loin pour avoir vu ces événements :
--   version;P;identifiant de créature;nom   (premier coup échangé avec le boss)
--   version;R;kill|wipe;d|j                  (issue : d annoncée par DBM, j vue dans le journal)

local ADDON, ns = ...
local Z = ns.Z

local PREFIX = "ZNTH"
local VERSION = "1"
local INTERVAL = 2
local LIMIT = 250 -- octets autorisés pour préfixe + message (254 dans le client)

local GetTime, tonumber, pairs, sort = GetTime, tonumber, pairs, table.sort
local strsplit, wipe = strsplit, wipe

local lastBody, lastSeg
local v = { absIn = {} }
local shieldBuf = {}

local function ByAmount(a, b) return a.v > b.v end

local function Channel()
	local _, itype = IsInInstance()
	if itype == "pvp" then return "BATTLEGROUND" end
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
end

-- Absorptions reçues, les plus fortes d'abord, dans la place restante.
local function Shields(p, room)
	local a = p.absIn
	if not a then return "" end
	local n = 0
	for name, amount in pairs(a) do
		if amount >= 1 then
			n = n + 1
			local e = shieldBuf[n]
			if not e then
				e = {}
				shieldBuf[n] = e
			end
			e.k, e.v = name, amount
		end
	end
	for i = n + 1, #shieldBuf do shieldBuf[i] = nil end
	sort(shieldBuf, ByAmount)
	local out = ""
	for i = 1, n do
		local part = ("%s%s:%.0f"):format(out == "" and "" or ",", shieldBuf[i].k, shieldBuf[i].v)
		if #out + #part > room then break end
		out = out .. part
	end
	return out
end

local function Send(kind, seg, ago0, ago1)
	if not Z.db.sync then return end
	local ch = Channel()
	local p = ch and Z.playerGUID and seg.players[Z.playerGUID]
	if not p then return end
	local body = ("%.0f;%.0f;%.0f;%.0f;%.0f;%.1f"):format(p.dmg, p.heal, p.over, p.absorb, p.taken, p.act)
	local head = ("%s;%s;%.1f;%.1f;"):format(VERSION, kind, ago0, ago1)
	body = body .. ";" .. Shields(p, LIMIT - #PREFIX - #head - #body - 1)
	if kind == "L" then
		if body == lastBody and seg == lastSeg then return end
		lastBody, lastSeg = body, seg
	end
	SendAddonMessage(PREFIX, head .. body, ch)
end

-- Membre actuel du groupe qui porte ce nom (sans le royaume éventuel).
local function Guid(name)
	local guid = Z.rosterByName[name]
	local r = guid and Z.roster[guid]
	return r and r.unit and guid or nil
end

local function Announce(text)
	if not Z.db.sync then return end
	local ch = Channel()
	if ch then SendAddonMessage(PREFIX, VERSION .. ";" .. text, ch) end
end

local function Receive(msg, sender)
	local ver, kind, a, b, dmg, heal, over, absorb, taken, act, shields = strsplit(";", msg)
	if ver ~= VERSION then return end
	local name = sender:match("^[^%-]+") or sender
	if name == UnitName("player") then return end
	local guid = Guid(name)
	if not guid then return end
	if kind == "P" then
		local id = tonumber(a)
		if id == 0 then id = nil end
		Z:EncounterPull(Z.EncounterName(id, b ~= "" and b or nil), id, false)
		return
	elseif kind == "R" then
		Z:EncounterResult(a, b == "d")
		return
	elseif kind ~= "L" and kind ~= "F" then
		return
	end
	a, b = tonumber(a), tonumber(b)
	v.dmg, v.heal, v.over = tonumber(dmg), tonumber(heal), tonumber(over)
	v.absorb, v.taken, v.act = tonumber(absorb), tonumber(taken), tonumber(act)
	if not (a and b and v.dmg and v.heal and v.over and v.absorb and v.taken and v.act) then return end
	if b < 0 or a < b or a > 3600 then return end
	wipe(v.absIn)
	if shields then
		for caster, amount in shields:gmatch("([^:,]+):(%d+)") do v.absIn[caster] = tonumber(amount) end
	end
	local now = GetTime()
	Z:SyncReceive(guid, name, kind == "F", now - a, now - b, v)
end

function Z:InitSync()
	function Z:CHAT_MSG_ADDON(prefix, msg, _, sender)
		if prefix ~= PREFIX or not Z.db.sync or not msg or not sender then return end
		Receive(msg, sender)
	end
	Z:RegisterEvent("CHAT_MSG_ADDON")
	Z:Every(INTERVAL, function()
		local seg = Z.current
		if seg and seg.t0 then Send("L", seg, GetTime() - seg.t0, 0) end
	end)
	Z:On("COMBAT_END", function(seg)
		if seg.t0 and seg.t1 then
			local now = GetTime()
			Send("F", seg, now - seg.t0, now - seg.t1)
		end
		lastBody, lastSeg = nil, nil
	end)
	-- Seul ce que l'on a vu soi-même est relayé, jamais ce que l'on a reçu.
	Z:On("PULL", function(name, id)
		Announce(("P;%.0f;%s"):format(id or 0, ((name or ""):gsub(";", ","))))
	end)
	Z:On("ENCOUNTER_RESULT", function(result, dbm) Announce("R;" .. result .. ";" .. (dbm and "d" or "j")) end)
end
