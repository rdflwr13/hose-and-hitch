require "KnoxWorks/KW_Log"
require "KnoxWorks/KW_Chain"
require "Vehicles/ISUI/ISVehicleMenu"

-- Client side of the second trailer: the vehicle radial menu entries, and
-- the drawbar itself, run by the driver of the truck (or in singleplayer).
local C = KnoxWorks.Chain

local function displayName(vehicle)
    return ISVehicleMenu.getVehicleDisplayName(vehicle)
end

require "KnoxWorks/KWDrawbarAction"

-- from the menu: by hand, with the game's trailer animation and sound
local function onChain(playerObj, parent, child)
    ISTimedActionQueue.add(KWDrawbarAction:new(playerObj, parent, child, true))
end

local function onUnchainByHand(playerObj, child)
    ISTimedActionQueue.add(KWDrawbarAction:new(playerObj, C.findParent(child) or child, child, false))
end

-- torn off while driving: at once
local function onUnchain(playerObj, child)
    sendClientCommand(playerObj, "KnoxWorks", "unchain", { child = child:getId() })
end

-- The player stands at the drawbar: where the second vehicle hitches to the
-- rear of the first. Only there the menu offers to hitch or unhitch it.
C.MENU_REACH = 2.0
function C.atDrawbar(playerObj, parent)
    local rear = parent and C.rearHitch(parent)
    if not rear or not playerObj then return false end
    local dx, dy = playerObj:getX() - rear:x(), playerObj:getY() - rear:y()
    return dx * dx + dy * dy <= C.MENU_REACH * C.MENU_REACH
end

-- What the menu of this vehicle offers: the same entry whichever of the
-- three the player opened it at (the truck, trailer one or trailer two),
-- and only to a player standing at the drawbar.
-- Returns "unchain", child  or  "chain", parent, child  or nil.
function C.menuEntry(vehicle, playerObj)
    local entry
    local parent = C.liveParentOf(vehicle)
    if parent then
        entry = { "unchain", vehicle, nil, parent }
    else
        -- the truck stands for the trailer it tows; a free car stands for itself
        local first = vehicle
        if vehicle:getVehicleTowedBy() == nil and vehicle:getVehicleTowing() then first = vehicle:getVehicleTowing() end
        local child = C.liveChildOf(first)
        if child then
            entry = { "unchain", child, nil, first }
        else
            local candidate = C.candidateFor(first)
            if candidate then
                entry = { "chain", first, candidate, first }
            elseif vehicle:getVehicleTowedBy() == nil then
                -- this one stands behind another that can take it on the drawbar
                for _, v in ipairs(C.vehiclesNear(vehicle)) do
                    if C.candidateFor(v) == vehicle then entry = { "chain", v, vehicle, v } break end
                end
            end
        end
    end
    if not entry or not C.atDrawbar(playerObj, entry[4]) then return nil end
    return entry[1], entry[2], entry[3]
end

-- The game's own towing slice of the vehicle radial menu, plus ours.
local originalTowingMenu = ISVehicleMenu.doTowingMenu
function ISVehicleMenu.doTowingMenu(playerObj, vehicle, menu)
    originalTowingMenu(playerObj, vehicle, menu)
    local kind, a, b = C.menuEntry(vehicle, playerObj)
    if kind == "unchain" then
        menu:addSlice(getText("ContextMenu_KW_Unchain", displayName(a)), getTexture("media/ui/ZoomOut.png"), onUnchainByHand, playerObj, a)
    elseif kind == "chain" then
        menu:addSlice(getText("ContextMenu_KW_Chain", displayName(b), displayName(a)), getTexture("media/ui/ZoomIn.png"), onChain, playerObj, a, b)
    end
end

-- The drawbar: every frame, for the trailer chained behind the truck this
-- player is driving, or the chained pair standing next to the player.
local broken = {}
-- seen within reach since it was chained: only such a trailer can tear off
-- (right after a server restart the link may still point at nothing near)
local held = {}
local cache = { first = nil, child = nil, ticks = 0 }
-- finding the chained trailer means looking around many squares: do it twice
-- a second and trust the remembered one in between, if it is still chained
local function chainedBehind(first)
    cache.ticks = cache.ticks + 1
    local stale = cache.first ~= first or cache.ticks >= 30
        or (cache.child and not C.isParentOf(cache.child, first))
    if stale then
        cache.first, cache.child, cache.ticks = first, C.childOf(first), 0
    end
    return cache.child
end

-- Every chained pair standing near the player, so the drawbar holds each
-- nose up from the moment it is hitched, and none is left loose with its
-- brakes off while the player is out of the truck or a passenger. Looked up
-- once a second, and at once when the player stops driving.
local near = { list = {}, ticks = 30, driving = false }
-- pairs held a moment ago: second vehicle -> first
local kept = {}
local function chainedNearby(playerObj, driving)
    near.ticks = near.ticks + 1
    if driving ~= near.driving then near.driving, near.ticks = driving, 30 end
    if near.ticks >= 30 then
        near.ticks, near.list = 0, {}
        for _, v in ipairs(C.vehiclesNear(playerObj)) do
            local parent = C.liveParentOf(v)
            if parent then table.insert(near.list, { child = v, parent = parent }) end
        end
    end
    return near.list
end

-- With the journal on (KW_Log): what the drawbar does, written to the game's
-- console (console.txt) when it changes and every two seconds while it holds.
local said = setmetatable({}, { __mode = "k" })
local sayTicks = 0
local function say(child, state, detail)
    if not KnoxWorks.Log.on then return end
    local key = state
    if said[child] ~= key or detail then
        said[child] = key
        print("KnoxWorks: " .. tostring(child:getScriptName()) .. " #" .. tostring(child:getId()) .. " " .. state
            .. (detail and (" " .. detail) or "")
            .. (isClient() and (" | " .. tostring(child:getAuthorizationDescription())) or ""))
    end
end

local function hold(playerObj, child, first, dt)
    -- online, push only once the server has handed this trailer to us
    if isClient() and not child:isLocalPhysicSim() then say(child, "not ours") return nil end
    if not C.isParentOf(child, first) then return nil end
    local result = C.step(child, first, dt)
    local info = C.info[child]
    if KnoxWorks.Log.on then
        say(child, tostring(result), sayTicks == 0 and string.format("gap=%.2f lift=%s force=%s",
            C.gap(child, first) or -1, tostring(C.lastLift), tostring(info and info.force)) or nil)
    end
    if result == "break" then
        if held[child] and not broken[child] then
            broken[child] = true
            held[child] = nil
            onUnchain(playerObj, child)
            HaloTextHelper.addBadText(playerObj, getText("IGUI_KW_ChainBroke"))
        end
    elseif result == "pulled" or result == "idle" or result == "asleep" then
        broken[child] = nil
        held[child] = true
    end
    return result
end

local function onTick()
    local playerObj = getPlayer()
    if not playerObj then return end
    sayTicks = sayTicks + 1
    if sayTicks >= 120 then sayTicks = 0 end
    local dt = getGameTime():getRealworldSecondsSinceLastUpdate()
    dt = math.max(0.005, math.min(0.05, dt))
    local car = playerObj:getVehicle()
    local driving = car ~= nil and car:getDriver() == playerObj
    local mine = nil
    if driving then
        -- behind what the truck tows, or on the drawbar right behind the truck
        local first = car:getVehicleTowing() or car
        mine = chainedBehind(first)
        if mine then C.lastResult = hold(playerObj, mine, first, dt) end
    end
    local nearNow = {}
    for _, pair in ipairs(chainedNearby(playerObj, driving)) do
        nearNow[pair.child] = true
        if pair.child ~= mine then
            local result = hold(playerObj, pair.child, pair.parent, dt)
            if not mine then C.lastResult = result end
            if result == "pulled" or result == "idle" then kept[pair.child] = pair.parent end
        end
    end
    if mine then kept[mine] = car:getVehicleTowing() or car end
    -- A pair this player held a moment ago and is no longer next to: a long
    -- tow (a motorhome and a livestock trailer) puts the second trailer
    -- further from the driver's door than the player is looked around, and
    -- with nobody holding it the nose dropped until he walked back. It is
    -- held on until it has gone to sleep (asleep it keeps its pose by itself).
    local drop = {}
    for child, parent in pairs(kept) do
        if child ~= mine and not nearNow[child] then
            local result = nil
            if not child:isRemovedFromWorld() and not parent:isRemovedFromWorld() then
                result = hold(playerObj, child, parent, dt)
            end
            if result ~= "pulled" and result ~= "idle" then table.insert(drop, child) end
        end
    end
    for _, child in ipairs(drop) do kept[child] = nil end
end
Events.OnTick.Add(onTick)
