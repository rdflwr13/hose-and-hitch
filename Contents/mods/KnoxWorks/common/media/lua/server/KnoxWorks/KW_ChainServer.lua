require "KnoxWorks/KW_Log"
require "KnoxWorks/KW_Chain"

-- Server side of the second trailer: connect and disconnect on request, keep
-- the session id of the first trailer up to date for players, and hand the
-- second trailer's physics to the truck's driver (checked once a second), so
-- the drawbar pulls it on the driver's machine without network delay.
local C = KnoxWorks.Chain

-- parent nil: disconnect
local function setLink(child, parent)
    local part = C.linkPart(child)
    if not part then return false end
    local md = part:getModData()
    md[C.KEY] = parent and parent:getSqlId() or nil
    md[C.KEY_NOW] = parent and parent:getId() or nil
    if isServer() then child:transmitPartModData(part) end
    -- off the drawbar: the game works its brakes out again from the brake parts
    if not parent then child:updatePartStats() end
    return true
end
C.setLink = setLink

local function vehicleById(id)
    if not id then return nil end
    return getVehicleById(id)
end

local function onClientCommand(module, command, player, args)
    if module ~= "KnoxWorks" then return end
    if command == "chain" then
        local parent, child = vehicleById(args.parent), vehicleById(args.child)
        if not parent or not child or parent:getSqlId() < 0 then return end
        if C.candidateFor(parent) ~= child then
            if KnoxWorks.Log.on then print("KnoxWorks: chain refused, " .. tostring(child:getScriptName()) .. " is not at the hitch") end
            return
        end   -- checked again here, not trusted from the client
        -- A free car at the head of a pair the game already tows: the game's
        -- hitch is stiff and exact, the drawbar only pulls with impulses, so
        -- the head takes the game's hitch itself and the drawbar goes to the
        -- tail, to the light one. Otherwise the order of hitching decides who
        -- is dragged by the drawbar (2026-11-24: a pickup that towed a cart
        -- was hitched to another pickup; the middle one, 1295 kg, hung 1.4 m
        -- behind on the drawbar and the tow drove badly).
        local tail = child:getVehicleTowing()
        if tail and parent:getVehicleTowedBy() == nil and parent:getVehicleTowing() == nil then
            child:breakConstraint(player, true, false)
            parent:addPointConstraint(player, child, C.ATTACH, C.isCar(child) and C.FRONT or C.ATTACH)
            setLink(tail, child)
            if KnoxWorks.Log.on then print("KnoxWorks: swapped, " .. tostring(parent:getScriptName()) .. " tows " .. tostring(child:getScriptName()) .. " the game's way, " .. tostring(tail:getScriptName()) .. " on the drawbar") end
            return
        end
        setLink(child, parent)
        if KnoxWorks.Log.on then print("KnoxWorks: chained " .. tostring(child:getScriptName()) .. " #" .. tostring(child:getId()) .. " behind " .. tostring(parent:getScriptName()) .. " #" .. tostring(parent:getId())) end
    elseif command == "unchain" then
        local child = vehicleById(args.child)
        if child and C.isChained(child) then setLink(child, nil) end
    end
end
Events.OnClientCommand.Add(onClientCommand)

-- The session id changes when the server restarts: write the current one,
-- or none while the first trailer is not around.
local function refresh(child)
    local part = C.linkPart(child)
    if not part then return end
    local md = part:getModData()
    if md[C.KEY] == nil then return end
    local parent = C.findParent(child)
    local now = parent and parent:getId() or nil
    if md[C.KEY_NOW] ~= now then
        md[C.KEY_NOW] = now
        child:transmitPartModData(part)
    end
end

-- Second trailers whose physics this server handed to a driver: trailer -> player.
-- The game's own call for that (authorizationChanged) takes the player
-- object; the one taking a player number wants a Java short, which Lua
-- cannot pass. Handed over the same way the game does it for a driver,
-- so it stays with that player until given back here.
local handed = {}

-- Looked at once a second by the clock, not by counting frames: a server runs
-- far fewer frames a second than a player's game (10 against 60), and by
-- frames a trailer waited six seconds to be handed over.
C.HAND_EVERY = 1000   -- ms
-- How many looks in a row a trailer may go unseen behind a driver who is
-- still driving before it is taken back. One missed look (the two vehicles
-- seen apart for a moment) would otherwise take it from him for a second,
-- and with nobody pulling it the trailer stops dead and tears off.
C.HAND_GRACE = 3
C.KEEP_DIST = 30   -- squares: a player this close to a pair he holds keeps it
local lastLook = 0
local unseen = {}
local function onTick()
    if not isServer() then return end
    local now = getTimestampMs()
    if now - lastLook < C.HAND_EVERY then return end
    lastLook = now
    local players = getOnlinePlayers()
    if not players then return end
    local done, wanted, online = {}, {}, {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        online[p] = true
        local car = p:getVehicle()
        if car and car:getDriver() == p then
            -- the truck tows trailer one; is anything chained behind it?
            local first = car:getVehicleTowing() or car
            local child = C.childOf(first)
            if child then
                done[child] = true
                refresh(child)
                wanted[child] = p
            end
        end
    end
    for i = 0, players:size() - 1 do
        -- chained trailers around every player; a dead link nobody pulls
        -- (the two stand apart) is taken off; a live one standing still goes
        -- to the player next to it, whose game then holds its nose up
        local p = players:get(i)
        for _, v in ipairs(C.vehiclesNear(p)) do
            if not done[v] and C.isChained(v) then
                done[v] = true
                if C.liveParentOf(v) then
                    refresh(v)
                    if not wanted[v] and (not p:getVehicle() or p:getVehicle():getDriver() ~= p) then wanted[v] = p end
                else
                    setLink(v, nil)
                end
            end
        end
    end
    -- give the trailer to its driver, and back to the server once nobody pulls it;
    -- what it tows the game's way goes along with it
    local function give(child, p)
        if KnoxWorks.Log.on then
            print("KnoxWorks: hand " .. tostring(child:getScriptName()) .. " #" .. tostring(child:getId()) .. " to "
                .. (p and ("player " .. tostring(p:getOnlineID()) .. (p:getVehicle() and " in a vehicle" or " on foot")) or "the server"))
        end
        child:authorizationChanged(p)
        local tail = child:getVehicleTowing()
        if tail then tail:authorizationChanged(p) end
    end
    for child, p in pairs(wanted) do
        if handed[child] ~= p then give(child, p) end
        unseen[child] = nil
    end
    local back, kept = {}, {}
    for child, p in pairs(handed) do
        if not wanted[child] then
            local car = p:getVehicle()
            local drives = car ~= nil and car:getDriver() == p
            local n = (unseen[child] or 0) + 1
            -- out of the truck but still around a live pair: it stays his, so his
            -- game goes on holding the nose up. A long tow puts the second
            -- trailer further from the driver's door than players are looked
            -- around, and given back to the server its nose dropped.
            local dx, dy = p:getX() - child:getX(), p:getY() - child:getY()
            local around = online[p] and dx * dx + dy * dy <= C.KEEP_DIST * C.KEEP_DIST and C.liveParentOf(child) ~= nil
            if around then
                unseen[child] = nil
                table.insert(kept, child)
            elseif drives and n < C.HAND_GRACE and C.isChained(child) then
                unseen[child] = n
                table.insert(kept, child)
            else
                unseen[child] = nil
                table.insert(back, child)
            end
        end
    end
    for _, child in ipairs(back) do give(child, nil) end
    for _, child in ipairs(kept) do wanted[child] = handed[child] end
    handed = wanted
end
Events.OnTick.Add(onTick)
