require "TimedActions/ISBaseTimedAction"
require "KnoxWorks/KW_Fuel"

-- Disconnect the fuel barrel from a generator and take the hose back.
KWUnlinkBarrelAction = ISBaseTimedAction:derive("KWUnlinkBarrelAction")

function KWUnlinkBarrelAction:isValid()
    return self.generator:getObjectIndex() ~= -1
        and KnoxWorks.Fuel.linkOf(self.generator) ~= nil
end

function KWUnlinkBarrelAction:waitToStart()
    self.character:faceThisObject(self.generator)
    return self.character:shouldBeTurning()
end

function KWUnlinkBarrelAction:update()
    self.character:faceThisObject(self.generator)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function KWUnlinkBarrelAction:start()
    self:setActionAnim("Loot")
end

function KWUnlinkBarrelAction:perform()
    ISBaseTimedAction.perform(self)
end

function KWUnlinkBarrelAction:complete()
    local F = KnoxWorks.Fuel
    local gsq = self.generator:getSquare()
    local barrel = F.linkedBarrel(self.generator)
    if barrel then
        barrel:getModData()[F.BARRELKEY] = nil
        barrel:transmitModData()
    end

    self.generator:getModData()[F.MODKEY] = nil
    self.generator:transmitModData()
    if gsq then
        F.registry().list[F.key(gsq:getX(), gsq:getY(), gsq:getZ())] = nil
    end

    local inv = self.character:getInventory()
    local hose = inv:AddItem(F.HOSE)
    if hose then sendAddItemToContainer(inv, hose) end
    return true
end

function KWUnlinkBarrelAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 80
end

function KWUnlinkBarrelAction:new(character, generator)
    local o = ISBaseTimedAction.new(self, character)
    o.generator = generator
    o.maxTime = o:getDuration()
    return o
end
