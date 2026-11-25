require "TimedActions/ISBaseTimedAction"
require "KnoxWorks/KW_Fuel"

-- Pour petrol by hand from the linked barrel into a switched-off generator.
-- Used when the barrel stands on the ground: then fuel does not run on its own.
KWPourFromBarrelAction = ISBaseTimedAction:derive("KWPourFromBarrelAction")

local function amountToMove(generator)
    local F = KnoxWorks.Fuel
    local barrel = F.linkedBarrel(generator)
    if not barrel then return 0 end
    return math.min(generator:getMaxFuel() - generator:getFuel(), F.petrolIn(barrel))
end

function KWPourFromBarrelAction:isValid()
    return self.generator:getObjectIndex() ~= -1
        and not self.generator:isActivated()
        and amountToMove(self.generator) > 0.01
end

function KWPourFromBarrelAction:waitToStart()
    self.character:faceThisObject(self.generator)
    return self.character:shouldBeTurning()
end

function KWPourFromBarrelAction:update()
    self.character:faceThisObject(self.generator)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function KWPourFromBarrelAction:start()
    self:setActionAnim("Loot")
    self.sound = self.character:playSound("GeneratorAddFuel")
end

function KWPourFromBarrelAction:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function KWPourFromBarrelAction:perform()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.perform(self)
end

function KWPourFromBarrelAction:complete()
    KnoxWorks.Fuel.topUp(self.generator, true)
    return true
end

-- as long as pouring the same amount from a gas can
function KWPourFromBarrelAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 70 + amountToMove(self.generator) * 50
end

function KWPourFromBarrelAction:new(character, generator)
    local o = ISBaseTimedAction.new(self, character)
    o.generator = generator
    o.maxTime = o:getDuration()
    return o
end
