require "TimedActions/ISBaseTimedAction"
require "KnoxWorks/KW_Water"

-- Connect a barrel to the house water supply, or disconnect it.
-- Needs a pipe wrench in hand, like vanilla plumbing. Nothing is used up.
KWWaterLinkAction = ISBaseTimedAction:derive("KWWaterLinkAction")

function KWWaterLinkAction:isValid()
    if self.barrel:getObjectIndex() == -1 then return false end
    if not self.character:isEquipped(self.wrench) then return false end
    local W = KnoxWorks.Water
    if self.connect then
        return not W.isConnected(self.barrel) and W.canConnect(self.barrel)
    end
    return W.isConnected(self.barrel)
end

function KWWaterLinkAction:waitToStart()
    self.character:faceThisObject(self.barrel)
    return self.character:shouldBeTurning()
end

function KWWaterLinkAction:update()
    self.character:faceThisObject(self.barrel)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function KWWaterLinkAction:start()
    self.sound = self.character:playSound("RepairWithWrench")
end

function KWWaterLinkAction:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function KWWaterLinkAction:perform()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.perform(self)
end

function KWWaterLinkAction:complete()
    local W = KnoxWorks.Water
    local sq = self.barrel:getSquare()
    if not sq then return false end
    local key = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
    if self.connect then
        self.barrel:getModData()[W.MODKEY] = true
        W.registry().list[key] = true
    else
        self.barrel:getModData()[W.MODKEY] = nil
        W.registry().list[key] = nil
    end
    self.barrel:transmitModData()
    return true
end

function KWWaterLinkAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return self.connect and 100 or 60
end

-- connect: 1 to connect, 0 to disconnect. Online the server builds the
-- action again from its fields, so it gets true or false here.
function KWWaterLinkAction:new(character, barrel, wrench, connect)
    local o = ISBaseTimedAction.new(self, character)
    o.barrel = barrel
    o.wrench = wrench
    o.connect = connect == 1 or connect == true
    o.maxTime = o:getDuration()
    return o
end
