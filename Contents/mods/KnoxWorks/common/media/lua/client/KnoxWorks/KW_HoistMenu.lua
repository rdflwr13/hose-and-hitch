require "KnoxWorks/KW_Hoist"
require "TimedActions/KWHoistBarrelAction"
require "TimedActions/KWLowerBarrelAction"

-- Hoist a barrel onto the roof, or lower one back down.
-- The option shows up wherever a player looks for it:
--   right-click on a barrel standing on the ground,
--   right-click on a barrel in the inventory,
--   right-click on the ground by the house wall with a barrel in the inventory.
-- Away from a house wall it is shown greyed out with a hint where to stand.
local H = KnoxWorks.Hoist
local W = KnoxWorks.Water

local function hasRope(playerObj)
    return H.rope(playerObj) ~= nil
end

local function hasWrench(playerObj)
    local inv = playerObj:getInventory()
    return inv:getFirstTypeRecurse("Base.PipeWrench") ~= nil or inv:getFirstTagRecurse(ItemTag.PIPE_WRENCH) ~= nil
end

local function onHoist(target, playerObj, item, ground, spot)
    if item then
        if playerObj:getPrimaryHandItem() == item or playerObj:getSecondaryHandItem() == item then
            ISTimedActionQueue.add(ISUnequipAction:new(playerObj, item, 50))
        end
        ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    end
    ISTimedActionQueue.add(KWHoistBarrelAction:new(playerObj, item, spot.x, spot.y, spot.z, ground))
end

local function onLower(target, playerObj, barrel)
    ISTimedActionQueue.add(KWLowerBarrelAction:new(playerObj, barrel))
end

local function summary(building)
    local count, water = H.roofSummary(building)
    return getText("Tooltip_KW_RoofSummary", tostring(count), string.format("%.0f", water))
end

-- One "Hoist Barrel onto the Roof" option, with the reason when it can't be done.
local function addHoistOption(context, target, playerObj, item, ground)
    local houseSq, building = H.houseNextTo(playerObj)
    local opt = context:addOption(getText("ContextMenu_KW_Hoist"), target, nil)
    local tip = ISWorldObjectContextMenu.addToolTip()
    opt.toolTip = tip
    opt.notAvailable = true

    if not houseSq or not building:getDef() then
        tip.description = getText("Tooltip_KW_StandByWall")
        return
    end
    if #W.housetaps(building) == 0 then
        tip.description = getText("Tooltip_KW_NoHouseTaps")
        return
    end
    local hasFuel = (item and H.itemHasFuel(item)) or (ground and H.objectHasFuel(ground))
    if hasFuel then
        tip.description = getText("Tooltip_KW_HoistFuel")
        return
    end
    if ground and KnoxWorks.Fuel.feedsGenerator(ground) then
        tip.description = getText("Tooltip_KW_HoistLinked")
        return
    end
    local spot = H.freeSpot(houseSq, building)
    if not spot then
        tip.description = getText("Tooltip_KW_RoofFull") .. " <LINE> " .. summary(building)
        return
    end
    tip.description = getText("Tooltip_KW_Hoist") .. " <LINE> " .. summary(building)
    if not hasRope(playerObj) or not hasWrench(playerObj) then
        tip.description = tip.description .. " <LINE> " .. getText("Tooltip_KW_NeedRopeWrench")
        return
    end
    opt.notAvailable = false
    opt.target = target
    opt.onSelect = onHoist
    opt.param1, opt.param2, opt.param3, opt.param4 = playerObj, item, ground, spot
end

local function groundBarrelClicked(worldobjects, playerObj)
    for _, obj in ipairs(worldobjects) do
        if H.groundBarrelNear(playerObj, obj) then return obj end
        local sq = obj:getSquare()
        if sq then
            local objects = sq:getObjects()
            for i = 0, objects:size() - 1 do
                local o = objects:get(i)
                if H.groundBarrelNear(playerObj, o) then return o end
            end
        end
    end
    return nil
end

local function onFillWorldMenu(player, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(player)

    local ground = groundBarrelClicked(worldobjects, playerObj)
    if ground then
        addHoistOption(context, worldobjects, playerObj, nil, ground)
    else
        local item = H.barrelItem(playerObj)
        if item and H.houseNextTo(playerObj) then
            addHoistOption(context, worldobjects, playerObj, item, nil)
        end
    end

    local houseSq, building = H.houseNextTo(playerObj)
    if not houseSq or not building:getDef() then return end
    local barrel = H.barrelWithinReach(houseSq, building)
    if barrel then
        local opt = context:addOption(getText("ContextMenu_KW_Lower"), worldobjects, onLower, playerObj, barrel)
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip.description = getText("Tooltip_KW_Lower") .. " <LINE> " .. summary(building)
        if not hasRope(playerObj) then
            opt.notAvailable = true
            tip.description = tip.description .. " <LINE> " .. getText("Tooltip_KW_NeedRope")
        end
        opt.toolTip = tip
    end
end

local function onFillInventoryMenu(player, context, items)
    local playerObj = getSpecificPlayer(player)
    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" and entry.items then item = entry.items[1] end
        if item and H.isBarrelItem(item) then
            addHoistOption(context, items, playerObj, item, nil)
            return
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryMenu)
