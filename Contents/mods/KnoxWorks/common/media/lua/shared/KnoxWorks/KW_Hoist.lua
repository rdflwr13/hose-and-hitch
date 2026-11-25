require "KnoxWorks/KW_Water"

-- Barrels go up onto a house roof on a rope from the ground, the way it is
-- done in real life: there is no way onto most roofs in the game.
-- A barrel hoisted this way is connected to the house water supply at once.

KnoxWorks = KnoxWorks or {}
KnoxWorks.Hoist = KnoxWorks.Hoist or {}
local H = KnoxWorks.Hoist
local W = KnoxWorks.Water
local F = KnoxWorks.Fuel
local P = KnoxWorks.Place

H.ROPES = { "Base.Rope", "Base.SheetRope" }
H.REACH = 2   -- how far along the roof the player can reach with a rope

function H.rope(character)
    local inv = character:getInventory()
    for _, t in ipairs(H.ROPES) do
        local r = inv:getFirstTypeRecurse(t)
        if r then return r end
    end
    return nil
end

-- Fuel stays on the ground: only a barrel with water, or an empty one, goes up.
function H.itemHasFuel(item)
    local fc = item:getFluidContainer()
    return fc ~= nil and not fc:isEmpty() and fc:contains(Fluid.Petrol)
end

-- A barrel in the inventory, as an item.
function H.isBarrelItem(item)
    if not instanceof(item, "Moveable") then return false end
    local ws = item:getWorldSprite()
    local spr = ws and getSprite(ws)
    return spr ~= nil and P.isBarrelProps(spr:getProperties())
end

function H.barrelItem(playerObj)
    local items = playerObj:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if H.isBarrelItem(item) then return item end
    end
    return nil
end

H.WALL_REACH = 2   -- a rope is thrown up from a couple of steps away

-- A house near a player standing outside, no further than two squares from
-- its wall. Returns the nearest house square and its building.
function H.houseNextTo(playerObj)
    if playerObj:getVehicle() then return nil end
    local sq = playerObj:getCurrentSquare()
    if not sq or sq:getBuilding() then return nil end
    local cell = getCell()
    local best, bestDist = nil, 999
    for dx = -H.WALL_REACH, H.WALL_REACH do
        for dy = -H.WALL_REACH, H.WALL_REACH do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local d = math.max(math.abs(dx), math.abs(dy))
            if s and s:getBuilding() and d < bestDist then best, bestDist = s, d end
        end
    end
    if best then return best, best:getBuilding() end
    return nil
end

-- A barrel standing on the ground right next to the player.
function H.groundBarrelNear(playerObj, obj)
    if not obj or not H.isMovableBarrel(obj) then return false end
    local psq, bsq = playerObj:getCurrentSquare(), obj:getSquare()
    if not psq or not bsq or bsq:getZ() ~= psq:getZ() then return false end
    return math.abs(bsq:getX() - psq:getX()) <= 1 and math.abs(bsq:getY() - psq:getY()) <= 1
end

-- Up on the roof the lid comes off: the barrel catches rain from then on.
H.ROOF_RAIN = 0.25   -- same rain share as the game's own rain collector barrel
function H.openToRain(barrel)
    local fc = barrel and barrel:getFluidContainer()
    if fc and fc:getRainCatcher() <= 0 then fc:setRainCatcher(H.ROOF_RAIN) end
end

function H.objectHasFuel(obj)
    local fc = obj and obj:getFluidContainer()
    return fc ~= nil and not fc:isEmpty() and fc:contains(Fluid.Petrol)
end

-- The level of the roof: one above the highest room of the house.
function H.roofZ(building)
    local rooms = building:getDef():getRooms()
    local top = 0
    for r = 0, rooms:size() - 1 do
        top = math.max(top, rooms:get(r):getZ())
    end
    return top + 1
end

local function barrelOn(sq)
    if not sq then return nil end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if F.isBarrel(obj) then return obj end
    end
    return nil
end

-- Roof spots above the house next to the player, nearest first.
local function roofSpots(houseSq, building)
    local z = H.roofZ(building)
    local cell = getCell()
    local spots = {}
    for dx = -H.REACH, H.REACH do
        for dy = -H.REACH, H.REACH do
            local x, y = houseSq:getX() + dx, houseSq:getY() + dy
            local ground = cell:getGridSquare(x, y, houseSq:getZ())
            if ground and ground:getBuilding() == building then
                table.insert(spots, { x = x, y = y, z = z, d = math.abs(dx) + math.abs(dy) })
            end
        end
    end
    table.sort(spots, function(a, b) return a.d < b.d end)
    return spots
end

-- A free roof spot to put a barrel on.
function H.freeSpot(houseSq, building)
    local cell = getCell()
    for _, s in ipairs(roofSpots(houseSq, building)) do
        if not barrelOn(cell:getGridSquare(s.x, s.y, s.z)) then return s end
    end
    return nil
end

-- A barrel that can be carried: a fixed roof tank of the map is not one.
function H.isMovableBarrel(obj)
    local spr = obj and obj:getSprite()
    local props = spr and spr:getProperties()
    return props ~= nil and props:has("IsMoveAble") and P.isBarrelProps(props)
end

-- The nearest barrel on the roof within reach that can be lowered.
function H.barrelWithinReach(houseSq, building)
    local cell = getCell()
    for _, s in ipairs(roofSpots(houseSq, building)) do
        local b = barrelOn(cell:getGridSquare(s.x, s.y, s.z))
        if b and H.isMovableBarrel(b) then return b end
    end
    return nil
end

-- All barrels connected to the water supply of a house, on the roof and on
-- every floor, and the water in them.
function H.roofSummary(building)
    local roof = H.roofZ(building)
    local cell = getCell()
    local rooms = building:getDef():getRooms()
    local houseKey = W.buildingKey(building)
    local seen, count, water = {}, 0, 0
    for r = 0, rooms:size() - 1 do
        local room = rooms:get(r)
        for x = room:getX(), room:getX2() - 1 do       -- x2 and y2 lie just past the room
            for y = room:getY(), room:getY2() - 1 do
                for z = 1, roof do
                    local key = x .. "," .. y .. "," .. z
                    if not seen[key] then
                        seen[key] = true
                        local b = barrelOn(cell:getGridSquare(x, y, z))
                        if b and W.isConnected(b) and W.buildingKey(W.buildingOf(b)) == houseKey then
                            count = count + 1
                            water = water + W.waterIn(b)
                        end
                    end
                end
            end
        end
    end
    return count, water
end
