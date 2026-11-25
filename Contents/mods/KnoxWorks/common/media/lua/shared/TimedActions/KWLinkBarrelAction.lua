require "TimedActions/ISBaseTimedAction"
require "KnoxWorks/KW_Fuel"

-- Connect a fuel barrel to a generator with a rubber hose.
-- The hose stays in the connection and comes back on disconnect.
KWLinkBarrelAction = ISBaseTimedAction:derive("KWLinkBarrelAction")

function KWLinkBarrelAction:isValid()
    return self.generator:getObjectIndex() ~= -1
        and self.barrel:getObjectIndex() ~= -1
        and self.character:getInventory():contains(self.hose)
        and not KnoxWorks.Fuel.linkOf(self.generator)
end

function KWLinkBarrelAction:waitToStart()
    self.character:faceThisObject(self.generator)
    return self.character:shouldBeTurning()
end

function KWLinkBarrelAction:update()
    self.character:faceThisObject(self.generator)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function KWLinkBarrelAction:start()
    self:setActionAnim("Loot")
    self.sound = self.character:playSound("RepairWithWrench")
end

function KWLinkBarrelAction:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function KWLinkBarrelAction:perform()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.perform(self)
end

function KWLinkBarrelAction:complete()
    local F = KnoxWorks.Fuel
    local bsq = self.barrel:getSquare()
    local gsq = self.generator:getSquare()
    if not bsq or not gsq then return false end

    local inv = self.character:getInventory()
    inv:Remove(self.hose)
    sendRemoveItemFromContainer(inv, self.hose)

    self.generator:getModData()[F.MODKEY] = { x = bsq:getX(), y = bsq:getY(), z = bsq:getZ() }
    self.generator:transmitModData()
    self.barrel:getModData()[F.BARRELKEY] = true
    self.barrel:transmitModData()

    local reg = F.registry()
    reg.list[F.key(gsq:getX(), gsq:getY(), gsq:getZ())] = true

    F.topUp(self.generator)
    return true
end

function KWLinkBarrelAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 150
end

function KWLinkBarrelAction:new(character, generator, barrel, hose)
    local o = ISBaseTimedAction.new(self, character)
    o.generator = generator
    o.barrel = barrel
    o.hose = hose
    o.maxTime = o:getDuration()
    return o
end
