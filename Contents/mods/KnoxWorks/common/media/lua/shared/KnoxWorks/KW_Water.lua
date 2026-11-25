require "KnoxWorks/KW_Fuel"

-- Roof barrels feed the house water supply.
-- Every original tap in a house (sink, bath, shower, toilet) keeps a small
-- reserve of water in its pipes; the game uses it after the water is shut
-- off. Barrels connected to the house refill those reserves for every tap
-- lower than the barrels. No barrels, no rain: the taps run dry.
-- A connection is a flag in the barrel's modData plus an entry in the global
-- registry. Removing the mod leaves taps as in the vanilla game.

KnoxWorks = KnoxWorks or {}
KnoxWorks.Water = KnoxWorks.Water or {}
local W = KnoxWorks.Water
local F = KnoxWorks.Fuel

W.MODKEY = "KnoxWorksSupply"
W.REGISTRY = "KnoxWorksWater"
W.DEFAULT_RESERVE = 20   -- litres, what a vanilla sink holds in its pipes
W.INFINITE = 9999        -- tiles with this much water are endless sources (wells)

-- Water a barrel can give: anything but fuel.
function W.waterIn(barrel)
    if not F.isBarrel(barrel) then return 0 end
    local fc = barrel:getFluidContainer()
    if fc:isEmpty() or fc:contains(Fluid.Petrol) then return 0 end
    return fc:getAmount()
end

function W.canConnect(barrel)
    if not F.isBarrel(barrel) then return false end
    if F.feedsGenerator(barrel) then return false end
    local fc = barrel:getFluidContainer()
    return fc:isEmpty() or not fc:contains(Fluid.Petrol)
end

function W.isConnected(barrel)
    return barrel:getModData()[W.MODKEY] == true
end

-- The house a barrel stands on or in: its own square, the roof it sits on,
-- or the floors straight below it.
function W.buildingOf(barrel)
    local sq = barrel:getSquare()
    if not sq then return nil end
    local b = sq:getBuilding() or sq:getRoofHideBuilding()
    if b then return b end
    local cell = getCell()
    for z = sq:getZ() - 1, 0, -1 do
        local below = cell:getGridSquare(sq:getX(), sq:getY(), z)
        b = below and (below:getBuilding() or below:getRoofHideBuilding())
        if b then return b end
    end
    return nil
end

function W.buildingKey(building)
    local def = building and building:getDef()
    return def and def:getIDString() or nil
end

-- An original tap of the house that the game feeds from its pipe reserve.
function W.isHouseTap(obj)
    if instanceof(obj, "IsoWorldInventoryObject") then return false end
    local spr = obj:getSprite()
    local props = spr and spr:getProperties()
    if not props or not props:has(IsoFlagType.waterPiped) then return false end
    if obj:getModData().canBeWaterPiped == true then return false end   -- moved by a player
    if obj:getUsesExternalWaterSource() then return false end          -- plumbed the vanilla way
    local sq = obj:getSquare()
    if not sq or sq:isNoWater() then return false end
    local tileAmount = props:has("waterAmount") and tonumber(props:get("waterAmount")) or nil
    return not (tileAmount and tileAmount >= W.INFINITE)
end

function W.reserveOf(obj)
    local md = obj:getModData()
    local props = obj:getSprite():getProperties()
    local tileAmount = props:has("waterAmount") and tonumber(props:get("waterAmount")) or nil
    local max = tonumber(md.waterMaxAmount) or tileAmount or W.DEFAULT_RESERVE
    local cur = tonumber(md.waterAmount) or tileAmount or 0
    return cur, max
end

-- Taps of a building, each once, with their floor.
function W.housetaps(building)
    local taps = {}
    local def = building:getDef()
    if not def then return taps end
    local seen = {}
    local cell = getCell()
    local rooms = def:getRooms()
    for r = 0, rooms:size() - 1 do
        local room = rooms:get(r)
        local z = room:getZ()
        for x = room:getX(), room:getX2() - 1 do       -- x2 and y2 lie just past the room
            for y = room:getY(), room:getY2() - 1 do
                local key = x .. "," .. y .. "," .. z
                if not seen[key] then
                    seen[key] = true
                    local sq = cell:getGridSquare(x, y, z)
                    if sq and sq:getBuilding() == building then
                        local objects = sq:getObjects()
                        for i = 0, objects:size() - 1 do
                            local obj = objects:get(i)
                            if W.isHouseTap(obj) then
                                table.insert(taps, obj)
                            end
                        end
                    end
                end
            end
        end
    end
    return taps
end

function W.registry()
    local reg = ModData.getOrCreate(W.REGISTRY)
    reg.list = reg.list or {}
    return reg
end

-- Server side: refill the taps of one house from its barrels.
-- Water runs down only: a barrel feeds taps on lower floors.
function W.supply(building, barrels)
    local taps = W.housetaps(building)
    for _, tap in ipairs(taps) do
        local cur, max = W.reserveOf(tap)
        local need = max - cur
        if need >= 0.5 then
            local tz = tap:getSquare():getZ()
            local got = 0
            for _, barrel in ipairs(barrels) do
                if need - got < 0.01 then break end
                if barrel:getSquare():getZ() > tz then
                    local take = math.min(need - got, W.waterIn(barrel))
                    if take > 0.01 then
                        local used = barrel:useFluid(take)
                        if used and used > 0 then got = got + used end
                    end
                end
            end
            if got > 0 then
                tap:getModData().waterAmount = cur + got
                tap:transmitModData()
            end
        end
    end
end
