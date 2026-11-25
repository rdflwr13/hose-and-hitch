-- Bigger trunks. A trailer or a car body in the game holds far less than
-- it would carry in life (a small trailer holds 100, a real one of that size
-- carries 500-750 kg). Here every trunk holds more:
--   trunks and beds of cars and trucks, trailer beds: twice as much;
--   roof racks, rear racks and bike bags of the tuning mod: a quarter more
--   (a car roof carries little in life, 75-100 kg).
--
-- The game works a trunk's size out itself, from the trunk part and its
-- condition, and again whenever these change (a trailer's bed, for one, is
-- set back to at most 100 on every change of condition). So the size is not
-- written once: whatever the game or another mod has set, this file makes it
-- bigger, and notes in the part what it found and what it set. A size it set
-- itself is left alone, so nothing grows twice, after a reload either.
-- Runs on the server, on every player's game and in singleplayer, so all of
-- them agree on how much fits.

KnoxWorks = KnoxWorks or {}
KnoxWorks.Cargo = KnoxWorks.Cargo or {}
local G = KnoxWorks.Cargo

G.KEY = "KnoxWorksCargo"

-- part id -> how much bigger
G.EXACT = { TruckBed = 2.0, TruckBedOpen = 2.0, TrailerTrunk = 2.0 }
-- part ids starting with these (the tuning mod adds them with a suffix)
G.PREFIX = {
    { "ATA2InteractiveTrunk", 1.25 }, { "ATAInteractiveTrunk", 1.25 },
    { "ATA2RoofRackToolbox", 1.25 }, { "ATARoofRackToolbox", 1.25 },
    { "ATA2Bag", 1.25 }, { "ATABag", 1.25 },
}

function G.factorFor(id)
    if not id then return nil end
    local f = G.EXACT[id]
    if f then return f end
    for _, rule in ipairs(G.PREFIX) do
        if string.sub(id, 1, #rule[1]) == rule[1] then return rule[2] end
    end
    return nil
end

-- One trunk: bigger, once per size the game set. Returns the size it has now.
function G.applyPart(part)
    if not part:getItemContainer() then return nil end
    local f = G.factorFor(part:getId())
    if not f then return nil end
    local now = part:getContainerCapacity()
    local md = part:getModData()
    local note = md[G.KEY]
    if note and note.set == now then return now end
    local want = math.floor(now * f + 0.5)
    md[G.KEY] = { base = now, set = want }
    if want ~= now then part:setContainerCapacity(want) end
    return want
end

function G.applyVehicle(vehicle)
    for i = 0, vehicle:getPartCount() - 1 do
        G.applyPart(vehicle:getPartByIndex(i))
    end
end

-- The players whose trunks are looked after here: every player online on
-- the server, the players at this screen in a player's game.
local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        if list then
            for i = 0, list:size() - 1 do table.insert(out, list:get(i)) end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then table.insert(out, p) end
        end
    end
    return out
end

-- Vehicles within G.REACH squares of a player, each once. The game's own list
-- of a cell's vehicles is a set that Lua cannot walk by number, so the
-- squares around the player are looked through instead.
G.REACH = 20
local function vehiclesAround(player, seen, out)
    local cell = getCell()
    if not cell then return end
    local cx, cy, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for x = cx - G.REACH, cx + G.REACH do
        for y = cy - G.REACH, cy + G.REACH do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local moving = sq:getMovingObjects()
                for i = 0, moving:size() - 1 do
                    local o = moving:get(i)
                    if instanceof(o, "BaseVehicle") and not seen[o] then
                        seen[o] = true
                        table.insert(out, o)
                    end
                end
            end
        end
    end
end

-- The vehicles near the players, once a second by the clock: a server runs
-- far fewer frames a second than a player's game, and by frames it would
-- look only every six seconds.
G.EVERY = 1000   -- ms
local lastLook = 0
local function onTick()
    local now = getTimestampMs()
    if now - lastLook < G.EVERY then return end
    lastLook = now
    local seen, found = {}, {}
    for _, p in ipairs(players()) do vehiclesAround(p, seen, found) end
    for _, v in ipairs(found) do G.applyVehicle(v) end
end
Events.OnTick.Add(onTick)
