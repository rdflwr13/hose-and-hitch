require "KnoxWorks/KW_BarrelPlace"

-- A barrel holds liquid. In the vanilla game most barrels are only furniture:
-- only rain collector barrels have a tank. Every other barrel gets an empty
-- 400 L tank the moment its square loads or it is put down, on the server and
-- on every client alike. The tank is the game's own fluid container, saved
-- with the world by the game itself; removing the mod keeps what is in it.

KnoxWorks = KnoxWorks or {}
KnoxWorks.BarrelFluid = KnoxWorks.BarrelFluid or {}
local B = KnoxWorks.BarrelFluid
local P = KnoxWorks.Place

B.CAPACITY = 400   -- litres, same as the game's metal rain collector barrel

-- Barrels whose tile has no tank of its own.
function B.needsTank(props)
    return props ~= nil and P.isBarrelProps(props) and not props:has("IsWaterCollector")
end

function B.ensureTank(entity)
    if not entity or entity:getFluidContainer() then return false end
    local tank = ComponentType.FluidContainer:CreateComponent()
    tank:setCapacity(B.CAPACITY)
    GameEntityFactory.AddComponent(entity, true, tank)
    return true
end

local function onSquareLoad(sq)
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local spr = obj:getSprite()
        if spr and B.needsTank(spr:getProperties()) then B.ensureTank(obj) end
    end
end
Events.LoadGridsquare.Add(onSquareLoad)

-- Marks of this mod on a barrel: it feeds a house or a generator.
B.LINK_KEYS = { "KnoxWorksSupply", "KnoxWorksFuelFor" }

-- A barrel that was picked up and is put down again starts unconnected.
-- The game carries the object's modData through the item (for thumpables
-- inside a "modData" table), so the marks are taken off the item first.
function B.forgetLinks(item)
    if not item or not item:hasModData() then return end
    local md = item:getModData()
    for _, key in ipairs(B.LINK_KEYS) do
        md[key] = nil
        if type(md.modData) == "table" then md.modData[key] = nil end
    end
end

-- A barrel put down from the inventory: the tank goes with the item, so the
-- game hands it to the new object and sends it to everyone with it.
local originalPlace = ISMoveableSpriteProps.placeMoveableInternal
function ISMoveableSpriteProps:placeMoveableInternal(_character, _square, _item, _spriteName)
    if self.kwBarrel and _item then
        B.forgetLinks(_item)
        if B.needsTank(self.spriteProps) then B.ensureTank(_item) end
    end
    return originalPlace(self, _character, _square, _item, _spriteName)
end
