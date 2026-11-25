require "TimedActions/ISBaseTimedAction"
require "KnoxWorks/KW_Hoist"

-- Hoist a barrel from the inventory onto the roof on a rope and connect it
-- to the house water supply. The barrel is put down by the game's own
-- furniture placement, so it is the same barrel object as one placed by hand.
KWHoistBarrelAction = ISBaseTimedAction:derive("KWHoistBarrelAction")

local function hasTools(character)
    local inv = character:getInventory()
    return KnoxWorks.Hoist.rope(character) ~= nil
        and (inv:getFirstTypeRecurse("Base.PipeWrench") ~= nil or inv:getFirstTagRecurse(ItemTag.PIPE_WRENCH) ~= nil)
end

function KWHoistBarrelAction:isValid()
    local H = KnoxWorks.Hoist
    if not hasTools(self.character) then return false end
    if self.ground then
        return self.ground:getObjectIndex() ~= -1 and not H.objectHasFuel(self.ground)
            and not KnoxWorks.Fuel.feedsGenerator(self.ground)
    end
    return self.character:getInventory():contains(self.item) and not H.itemHasFuel(self.item)
end

function KWHoistBarrelAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function KWHoistBarrelAction:start()
    self:setActionAnim("Loot")
end

function KWHoistBarrelAction:stop()
    ISBaseTimedAction.stop(self)
end

function KWHoistBarrelAction:perform()
    ISBaseTimedAction.perform(self)
end

function KWHoistBarrelAction:complete()
    local W = KnoxWorks.Water
    local F = KnoxWorks.Fuel
    local sq = getCell():getOrCreateGridSquare(self.x, self.y, self.z)
    if not sq then return false end
    local existing = sq:getObjects()
    for i = 0, existing:size() - 1 do
        if F.isBarrel(existing:get(i)) then return false end   -- someone was quicker
    end
    local inv = self.character:getInventory()
    local item = self.item
    if self.ground then
        -- straight from the ground: the game's own pick-up first, without a
        -- break roll; the barrel comes into the inventory as a new item
        local before = {}
        local items = inv:getItems()
        for i = 0, items:size() - 1 do before[items:get(i)] = true end
        local fromProps = ISMoveableSpriteProps.fromObject(self.ground)
        fromProps:pickUpMoveable(self.character, self.ground:getSquare(), true, true)
        item = nil
        items = inv:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if not before[it] and KnoxWorks.Hoist.isBarrelItem(it) then item = it break end
        end
    end
    if not item then return false end
    -- this very barrel goes up, not another one of the same kind
    local spriteName = item:getWorldSprite()
    local props = ISMoveableSpriteProps.new(getSprite(spriteName))
    props:placeMoveableInternal(self.character, sq, item, props.spriteName or spriteName)
    inv:Remove(item)
    sendRemoveItemFromContainer(inv, item)

    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if F.isBarrel(obj) and not W.isConnected(obj) and W.canConnect(obj) then
            obj:getModData()[W.MODKEY] = true
            obj:transmitModData()
            KnoxWorks.Hoist.openToRain(obj)
            W.registry().list[self.x .. "," .. self.y .. "," .. self.z] = true
            break
        end
    end
    return true
end

function KWHoistBarrelAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 300
end

-- item: a barrel in the inventory, or nil; ground: a barrel on the ground, or nil
function KWHoistBarrelAction:new(character, item, x, y, z, ground)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.ground = ground
    o.x, o.y, o.z = x, y, z
    o.maxTime = o:getDuration()
    return o
end
