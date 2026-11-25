require "TimedActions/ISBaseTimedAction"
require "KnoxWorks/KW_Chain"

-- Hitching or unhitching the drawbar by hand, the way the game hitches a
-- trailer: the character faces the hitch, plays the game's trailer animation
-- and sound, and the hitch is made when the action ends.
KWDrawbarAction = ISBaseTimedAction:derive("KWDrawbarAction")

local C = KnoxWorks.Chain

local function hitchPos(self)
    return C.rearHitch(self.parent)
end

function KWDrawbarAction:isValid()
    if self.connect then
        return C.candidateFor(self.parent) == self.child
    end
    return C.isChained(self.child)
end

function KWDrawbarAction:waitToStart()
    local p = hitchPos(self)
    if p then self.character:faceLocationF(p:x(), p:y()) end
    return self.character:shouldBeTurning()
end

function KWDrawbarAction:update()
    local p = hitchPos(self)
    if p then self.character:faceLocationF(p:x(), p:y()) end
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end

function KWDrawbarAction:start()
    self:setActionAnim("VehicleTrailer")
    self.sound = self.character:getEmitter():playSound(self.connect and "VehicleTowAttach" or "VehicleTowDetach")
end

function KWDrawbarAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function KWDrawbarAction:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function KWDrawbarAction:perform()
    self:stopSound()
    if self.connect then
        sendClientCommand(self.character, "KnoxWorks", "chain", { parent = self.parent:getId(), child = self.child:getId() })
    else
        sendClientCommand(self.character, "KnoxWorks", "unchain", { child = self.child:getId() })
    end
    ISBaseTimedAction.perform(self)
end

-- connect: true to hitch the child behind the parent, false to unhitch it
function KWDrawbarAction:new(character, parent, child, connect)
    local o = ISBaseTimedAction.new(self, character)
    o.parent = parent
    o.child = child
    o.connect = connect
    o.maxTime = character:isTimedActionInstant() and 1 or 100
    return o
end
