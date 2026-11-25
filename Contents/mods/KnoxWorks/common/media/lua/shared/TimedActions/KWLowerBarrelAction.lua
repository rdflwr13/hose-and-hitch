require "TimedActions/ISBaseTimedAction"
require "KnoxWorks/KW_Hoist"

-- Lower a barrel from the roof on a rope. The water in it is poured out
-- first: a full barrel is far too heavy to lower. The barrel comes back to
-- the inventory through the game's own furniture pick-up.
KWLowerBarrelAction = ISBaseTimedAction:derive("KWLowerBarrelAction")

function KWLowerBarrelAction:isValid()
    return self.barrel:getObjectIndex() ~= -1 and KnoxWorks.Hoist.isMovableBarrel(self.barrel)
        and KnoxWorks.Hoist.rope(self.character) ~= nil
end

function KWLowerBarrelAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function KWLowerBarrelAction:start()
    self:setActionAnim("Loot")
end

function KWLowerBarrelAction:stop()
    ISBaseTimedAction.stop(self)
end

function KWLowerBarrelAction:perform()
    ISBaseTimedAction.perform(self)
end

function KWLowerBarrelAction:complete()
    local W = KnoxWorks.Water
    local sq = self.barrel:getSquare()
    if not sq then return false end
    W.registry().list[sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()] = nil
    self.barrel:getModData()[W.MODKEY] = nil
    local fc = self.barrel:getFluidContainer()
    if fc and not fc:isEmpty() then fc:Empty() end
    local props = ISMoveableSpriteProps.fromObject(self.barrel)
    props:pickUpMoveable(self.character, sq, true, true)
    return true
end

function KWLowerBarrelAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 250
end

function KWLowerBarrelAction:new(character, barrel)
    local o = ISBaseTimedAction.new(self, character)
    o.barrel = barrel
    o.maxTime = o:getDuration()
    return o
end
