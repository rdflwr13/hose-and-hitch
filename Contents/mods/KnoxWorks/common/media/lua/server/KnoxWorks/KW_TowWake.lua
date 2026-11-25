require "KnoxWorks/KW_Chain"

-- When the game unhitches a trailer it only drops the hitch and does not
-- wake the physics. A trailer that has gone to sleep (a vehicle with nobody
-- in it sleeps after a second at rest) then stays as it hung on the hitch,
-- nose up. Here the vehicles right at the unhitched one are woken for the
-- game's own three seconds, so the trailer settles the way it should.
-- Runs where the game unhitches: on the server, or in singleplayer.
local C = KnoxWorks.Chain

C.WAKE_REACH = 4   -- only the vehicles right at the unhitched hitch

local function wakeAround(vehicle)
    if not vehicle then return end
    vehicle:setPhysicsActive(true)
    for _, v in ipairs(C.vehiclesNear(vehicle)) do
        local dx, dy = v:getX() - vehicle:getX(), v:getY() - vehicle:getY()
        if v:getDriver() == nil and dx * dx + dy * dy <= C.WAKE_REACH * C.WAKE_REACH then
            v:setPhysicsActive(true)
        end
    end
end
KnoxWorks.wakeAround = wakeAround

local function onClientCommand(module, command, player, args)
    if module ~= "vehicle" then return end
    if command ~= "detachTrailer" and command ~= "detachTrailerSpontaneous" then return end
    if not args or not args.vehicle then return end
    local vehicle = getVehicleById(args.vehicle)
    -- test build: the singleplayer bridge records what the unhitch found
    if KnoxWorks.Dev and vehicle then
        KnoxWorks.Dev.log("unhitch " .. vehicle:getScriptName() .. " active=" .. tostring(vehicle:isPhysicsActive()))
    end
    wakeAround(vehicle)
end
Events.OnClientCommand.Add(onClientCommand)
