require "Moveables/ISMoveableSpriteProps"

-- Barrels can stand on crates, tables and orange barrels.
-- Placement goes through the game's own moveable placement: the same cursor,
-- the same height limit as things on a table. The barrel stays the same kind
-- of object as a barrel on the floor (thumpable, a valid plumbing source);
-- only its height changes. The game keeps that height in the world, so
-- removing the mod leaves the barrels standing where they are.

KnoxWorks = KnoxWorks or {}
KnoxWorks.Place = KnoxWorks.Place or {}
local P = KnoxWorks.Place

P.NAMES = {
    ["Barrel"] = true,
    ["Metal Drum"] = true,
    ["Rain Collector Barrel"] = true,
}
P.MAX_HEIGHT = 64   -- same limit the game uses for things on a table

function P.isBarrelProps(props)
    if not props then return false end
    if props:has("IsWaterCollector") then return true end
    return props:has("CustomName") and P.NAMES[props:get("CustomName")] == true
end

-- A barrel already standing on a table or crate on this square.
function P.raisedBarrelOn(square)
    if not square then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local spr = obj:getSprite()
        if spr and obj:getRenderYOffset() > 0 and P.isBarrelProps(spr:getProperties()) then
            return obj
        end
    end
    return nil
end

-- The square has a free table surface a barrel can go on.
local function hasSurface(props, square)
    return square and square:has("IsTable") and not square:has("IsTableTop")
        and props:getTotalTableHeight(square) > 0
end

local originalNew = ISMoveableSpriteProps.new
function ISMoveableSpriteProps.new(_sprite)
    local s = originalNew(_sprite)
    if s and s.isMoveable and s.type == "Object" and P.isBarrelProps(s.spriteProps) then
        s.kwBarrel = true
    end
    return s
end

local originalCanPlace = ISMoveableSpriteProps.canPlaceMoveableInternal
function ISMoveableSpriteProps:canPlaceMoveableInternal(_character, _square, _item, _forceTypeObject)
    -- a barrel onto a table, crate or orange barrel
    if self.kwBarrel and hasSurface(self, _square) then
        if _square:isVehicleIntersecting() or not _square:getFloor() then return false end
        if self:isSquareAtTopOfStairs(_square) or P.raisedBarrelOn(_square) then return false end
        local height = self:getTotalTableHeight(_square)
        self.yOffsetCursor = height
        return height <= P.MAX_HEIGHT
    end

    local canPlace = originalCanPlace(self, _character, _square, _item, _forceTypeObject)
    -- nothing else goes onto a square where a barrel stands raised
    if canPlace and (self.type == "Object" or _forceTypeObject) and P.raisedBarrelOn(_square) then
        return false
    end
    return canPlace
end

-- The game raises an object to the table height only for stackable tables.
-- For the length of one placement the barrel is treated that way, so the
-- game builds the usual barrel object and lifts it before sending it to clients.
local originalPlace = ISMoveableSpriteProps.placeMoveableInternal
function ISMoveableSpriteProps:placeMoveableInternal(_character, _square, _item, _spriteName)
    if not (self.kwBarrel and hasSurface(self, _square)) then
        return originalPlace(self, _character, _square, _item, _spriteName)
    end
    local wasStackable, wasTable = self.isStackable, self.isTable
    self.isStackable, self.isTable = true, true
    local ok, result = pcall(originalPlace, self, _character, _square, _item, _spriteName)
    self.isStackable, self.isTable = wasStackable, wasTable
    if not ok then error(result) end
    return result
end

-- Nor can it be scrapped from under the barrel.
local originalCanScrap = ISMoveableSpriteProps.canScrapObjectInternal
function ISMoveableSpriteProps:canScrapObjectInternal(_result, _object)
    local canScrap = originalCanScrap(self, _result, _object)
    if canScrap and _object and self.isTable then
        local barrel = P.raisedBarrelOn(_object:getSquare())
        if barrel and barrel ~= _object then
            return false
        end
    end
    return canScrap
end

-- The table or crate under a raised barrel stays put until the barrel is taken off.
local originalCanPickUp = ISMoveableSpriteProps.canPickUpMoveableInternal
function ISMoveableSpriteProps:canPickUpMoveableInternal(_character, _square, _object, _isMulti)
    local canPickUp = originalCanPickUp(self, _character, _square, _object, _isMulti)
    if canPickUp and self.isTable then
        local barrel = P.raisedBarrelOn(_square)
        if barrel and barrel ~= _object then
            return false
        end
    end
    return canPickUp
end
