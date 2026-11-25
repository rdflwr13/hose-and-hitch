require "KnoxWorks/KW_Water"
require "TimedActions/KWWaterLinkAction"
require "KnoxWorks/KW_Hoist"

-- Barrel right-click menu: connect to / disconnect from the house water supply.
local W = KnoxWorks.Water
local F = KnoxWorks.Fuel

local function predicateNotBroken(item)
    return not item:isBroken()
end

local function findWrench(playerObj)
    local inv = playerObj:getInventory()
    return inv:getFirstTypeEvalRecurse("PipeWrench", predicateNotBroken)
        or inv:getFirstTagEvalRecurse(ItemTag.PIPE_WRENCH, predicateNotBroken)
end

local function onLink(worldobjects, playerObj, barrel, connect)
    local wrench = findWrench(playerObj)
    if not wrench then return end
    if luautils.walkAdj(playerObj, barrel:getSquare(), true) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
        ISTimedActionQueue.add(KWWaterLinkAction:new(playerObj, barrel, wrench, connect))
    end
end

local function findBarrel(worldobjects)
    for _, obj in ipairs(worldobjects) do
        if F.isBarrel(obj) then return obj end
        local sq = obj:getSquare()
        if sq then
            local objects = sq:getObjects()
            for i = 0, objects:size() - 1 do
                local o = objects:get(i)
                if F.isBarrel(o) then return o end
            end
        end
    end
    return nil
end

local function findTap(worldobjects)
    for _, obj in ipairs(worldobjects) do
        local sq = obj:getSquare()
        if sq then
            local objects = sq:getObjects()
            for i = 0, objects:size() - 1 do
                local o = objects:get(i)
                if W.isHouseTap(o) then return o end
            end
        end
    end
    return nil
end

-- Sink, bath, shower or toilet: how the house supply is doing.
local function addTapInfo(context, worldobjects, tap)
    local building = tap:getSquare():getBuilding()
    if not building or not building:getDef() then return end
    local count, water = KnoxWorks.Hoist.roofSummary(building)
    if count == 0 then return end
    local cur, max = W.reserveOf(tap)
    local opt = context:addOption(getText("ContextMenu_KW_TapInfo"), worldobjects, nil)
    -- information only: grey like a disabled option, not red like a missing
    -- tool (red read as an error on the screenshots, 2026-11-24)
    opt.isDisabled = true
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = getText("Tooltip_KW_RoofSummary", tostring(count), string.format("%.0f", water))
        .. " <LINE> " .. getText("Tooltip_KW_TapWater", string.format("%.0f", cur), string.format("%.0f", max))
    opt.toolTip = tip
end

local function onFillMenu(player, context, worldobjects, test)
    if test then return end
    local tap = findTap(worldobjects)
    if tap then addTapInfo(context, worldobjects, tap) end
    local barrel = findBarrel(worldobjects)
    if not barrel then return end
    local playerObj = getSpecificPlayer(player)
    local wrench = findWrench(playerObj)
    local litres = string.format("%.1f", W.waterIn(barrel))
    local tip = ISWorldObjectContextMenu.addToolTip()

    if W.isConnected(barrel) then
        local opt = context:addOption(getText("ContextMenu_KW_WaterUnlink"), worldobjects, onLink, playerObj, barrel, 0)
        tip.description = getText("Tooltip_KW_WaterConnected", litres)
        if not wrench then
            opt.notAvailable = true
            tip.description = tip.description .. " <LINE> " .. getText("Tooltip_KW_NeedWrench")
        end
        opt.toolTip = tip
        return
    end

    if not W.canConnect(barrel) then return end
    local building = W.buildingOf(barrel)
    local sq = barrel:getSquare()
    if not building or sq:getZ() < 1 then return end   -- only barrels up on a house

    local opt = context:addOption(getText("ContextMenu_KW_WaterLink"), worldobjects, onLink, playerObj, barrel, 1)
    tip.description = getText("Tooltip_KW_WaterLink", litres)
    if not wrench then
        opt.notAvailable = true
        tip.description = tip.description .. " <LINE> " .. getText("Tooltip_KW_NeedWrench")
    end
    opt.toolTip = tip
end

Events.OnFillWorldObjectContextMenu.Add(onFillMenu)
