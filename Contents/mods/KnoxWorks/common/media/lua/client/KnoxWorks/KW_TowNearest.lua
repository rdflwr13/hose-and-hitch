require "Vehicles/ISVehicleTrailerUtils"

-- The game's own hitching (trailers and cars on a tow rope) picks the first
-- vehicle it comes across in the squares around, not the one standing at the
-- hitch. With two vehicles within reach it can hitch the wrong one. Here it
-- picks the vehicle whose tow point is nearest to the hitch, with the same
-- rules of the game for what may be hitched.
local original = ISVehicleTrailerUtils.getTowableVehicleNear

local function dist2(a, b)
    local dx, dy = a:x() - b:x(), a:y() - b:y()
    return dx * dx + dy * dy
end

function ISVehicleTrailerUtils.getTowableVehicleNear(square, ignoreVehicle, attachmentA, attachmentB)
    if not square or not ignoreVehicle then return original(square, ignoreVehicle, attachmentA, attachmentB) end
    local hitch = ignoreVehicle:getTowingWorldPos(attachmentA, Vector3f.new())
    if not hitch then return original(square, ignoreVehicle, attachmentA, attachmentB) end
    local best, bestD = nil, nil
    local cell = getCell()
    for y = square:getY() - 6, square:getY() + 6 do
        for x = square:getX() - 6, square:getX() + 6 do
            local sq = cell:getGridSquare(x, y, square:getZ())
            if sq then
                local moving = sq:getMovingObjects()
                for i = 0, moving:size() - 1 do
                    local obj = moving:get(i)
                    if instanceof(obj, "BaseVehicle") and obj ~= ignoreVehicle
                        and ignoreVehicle:canAttachTrailer(obj, attachmentA, attachmentB) then
                        local p = obj:getTowedByWorldPos(attachmentB, Vector3f.new())
                        local d = p and dist2(hitch, p) or math.huge
                        if not bestD or d < bestD then best, bestD = obj, d end
                    end
                end
            end
        end
    end
    return best
end
