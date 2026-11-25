-- Fuel barrel linked to a generator: shared helpers.
-- A link lives in the generator's modData (barrel coordinates) and in the
-- global modData registry, so the server can top up loaded generators.
-- Removing the mod leaves only unused modData keys behind.

require "KnoxWorks/KW_BarrelPlace"
require "KnoxWorks/KW_BarrelFluid"

KnoxWorks = KnoxWorks or {}
KnoxWorks.Fuel = KnoxWorks.Fuel or {}
local F = KnoxWorks.Fuel

F.RADIUS = 2            -- barrel must stand this close to the generator, same floor
F.MIN_CAPACITY = 50     -- litres; smaller containers are cans, not barrels
F.MODKEY = "KnoxWorksBarrel"
F.REGISTRY = "KnoxWorksGenerators"
F.HOSE = "Base.RubberHose"
F.BARRELKEY = "KnoxWorksFuelFor"     -- on the barrel: it feeds a generator
F.WATERKEY = "KnoxWorksSupply"       -- on the barrel: it feeds a house (KW_Water)

function F.key(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

-- A world object that can hold fuel: a barrel or another big tank.
-- Sinks, toilets and bathtubs are plumbing fixtures, not tanks.
function F.isBarrel(obj)
    if not obj or instanceof(obj, "IsoGenerator") or instanceof(obj, "IsoWorldInventoryObject") then
        return false
    end
    local fc = obj:getFluidContainer()
    if not fc or fc:getCapacity() < F.MIN_CAPACITY then return false end
    local spr = obj:getSprite()
    local props = spr and spr:getProperties()
    if not props then return false end
    if KnoxWorks.Place.isBarrelProps(props) then return true end
    -- A bathtub spans two tiles and only one carries the waterPiped flag,
    -- so the fixture tile set is checked by name as well.
    local name = spr:getName()
    if name and string.sub(name, 1, 9) == "fixtures_" then return false end
    return not props:has(IsoFlagType.waterPiped) and not props:has(IsoFlagType.water)
end

-- Empty, or holding nothing but petrol.
function F.isPetrolBarrel(obj)
    if not F.isBarrel(obj) then return false end
    local fc = obj:getFluidContainer()
    return fc:isEmpty() or fc:isPureFluid(Fluid.Petrol)
end

-- An open barrel catches rain; rain in a fuel barrel spoils the fuel.
function F.catchesRain(obj)
    local fc = obj and obj:getFluidContainer()
    return fc ~= nil and fc:getRainCatcher() > 0
end

-- Petrol with water or anything else mixed in.
function F.isSpoiled(obj)
    if not F.isBarrel(obj) then return false end
    local fc = obj:getFluidContainer()
    return not fc:isEmpty() and fc:contains(Fluid.Petrol) and not fc:isPureFluid(Fluid.Petrol)
end

function F.petrolIn(obj)
    if not F.isBarrel(obj) then return 0 end
    local fc = obj:getFluidContainer()
    if fc:isEmpty() or not fc:isPureFluid(Fluid.Petrol) then return 0 end
    return fc:getAmount()
end

function F.barrelOnSquare(sq)
    if not sq then return nil end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if F.isPetrolBarrel(obj) then return obj end
    end
    return nil
end

-- Fuel flows by gravity: the barrel must stand higher than the generator,
-- either on a table, crate or other surface, or on the floor above.
function F.isAbove(barrel, generator)
    local bsq, gsq = barrel:getSquare(), generator:getSquare()
    if not bsq or not gsq then return false end
    if bsq:getZ() > gsq:getZ() then return true end
    return bsq:getZ() == gsq:getZ() and barrel:getRenderYOffset() > 0
end

-- Petrol barrels near a generator, this floor and the floor above.
-- Barrels standing higher come first, then the nearest.
function F.barrelsNear(generator)
    local sq = generator:getSquare()
    local found = {}
    if not sq then return found end
    local cell = getCell()
    for dz = 0, 1 do
        for dx = -F.RADIUS, F.RADIUS do
            for dy = -F.RADIUS, F.RADIUS do
                local b = F.barrelOnSquare(cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ() + dz))
                if b and b:getModData()[F.WATERKEY] ~= true then
                    local above = F.isAbove(b, generator)
                    table.insert(found, { obj = b, rank = (above and 0 or 100) + math.abs(dx) + math.abs(dy) })
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.rank < b.rank end)
    local out = {}
    for _, f in ipairs(found) do table.insert(out, f.obj) end
    return out
end

function F.linkOf(generator)
    return generator:getModData()[F.MODKEY]
end

-- The barrel on the linked spot, whatever is in it now.
function F.linkedBarrel(generator)
    local link = F.linkOf(generator)
    if not link then return nil end
    local sq = getCell():getGridSquare(link.x, link.y, link.z)
    if not sq then return nil end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if F.isBarrel(obj) then return obj end
    end
    return nil
end

function F.generatorOnSquare(sq)
    if not sq then return nil end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoGenerator") then return obj end
    end
    return nil
end

-- Generators within reach of a barrel: its floor and the floor below.
function F.generatorNear(barrel)
    local sq = barrel:getSquare()
    if not sq then return nil end
    local cell = getCell()
    local best, bestDist = nil, 999
    for dz = 0, -1, -1 do
        for dx = -F.RADIUS, F.RADIUS do
            for dy = -F.RADIUS, F.RADIUS do
                local g = F.generatorOnSquare(cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ() + dz))
                local d = math.abs(dx) + math.abs(dy) - dz * 10
                if g and d < bestDist then best, bestDist = g, d end
            end
        end
    end
    return best
end

-- The barrel feeds a generator right now: a generator in reach is linked to it.
-- Checked on the spot, not from a flag: a flag can outlive the generator.
function F.feedsGenerator(barrel)
    local sq = barrel and barrel:getSquare()
    if not sq then return false end
    local cell = getCell()
    for dz = 0, -1, -1 do
        for dx = -F.RADIUS, F.RADIUS do
            for dy = -F.RADIUS, F.RADIUS do
                local g = F.generatorOnSquare(cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ() + dz))
                if g and F.linkedBarrel(g) == barrel then return true end
            end
        end
    end
    return false
end

function F.registry()
    local reg = ModData.getOrCreate(F.REGISTRY)
    reg.list = reg.list or {}
    return reg
end

-- Server side: move petrol from the linked barrel into the generator.
-- On its own fuel only runs down from a barrel standing higher; by hand
-- (manual = true) it is poured from a barrel standing anywhere.
-- Returns the litres moved.
function F.topUp(generator, manual)
    local barrel = F.linkedBarrel(generator)
    if not barrel or (not manual and not F.isAbove(barrel, generator)) then return 0 end
    local need = generator:getMaxFuel() - generator:getFuel()
    if need < 0.1 then return 0 end
    local take = math.min(need, F.petrolIn(barrel))
    if take < 0.01 then return 0 end
    local used = barrel:useFluid(take)
    if used and used > 0 then
        generator:setFuel(generator:getFuel() + used)
        generator:sync()
        return used
    end
    return 0
end
