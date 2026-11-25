require "KnoxWorks/KW_Fuel"
require "TimedActions/KWLinkBarrelAction"
require "TimedActions/KWUnlinkBarrelAction"
require "TimedActions/KWPourFromBarrelAction"

-- Generator right-click menu: connect / disconnect a fuel barrel.
local F = KnoxWorks.Fuel

local function litres(n)
    return string.format("%.1f", n)
end

local function walkToGenerator(playerObj, generator)
    return luautils.walkAdj(playerObj, generator:getSquare(), true)
end

local function onLink(worldobjects, playerObj, generator, barrel)
    local hose = playerObj:getInventory():getFirstTypeRecurse(F.HOSE)
    if not hose then return end
    if walkToGenerator(playerObj, generator) then
        ISInventoryPaneContextMenu.transferIfNeeded(playerObj, hose)
        ISTimedActionQueue.add(KWLinkBarrelAction:new(playerObj, generator, barrel, hose))
    end
end

local function onUnlink(worldobjects, playerObj, generator)
    if walkToGenerator(playerObj, generator) then
        ISTimedActionQueue.add(KWUnlinkBarrelAction:new(playerObj, generator))
    end
end

local function onPour(worldobjects, playerObj, generator)
    if walkToGenerator(playerObj, generator) then
        ISTimedActionQueue.add(KWPourFromBarrelAction:new(playerObj, generator))
    end
end

-- Barrel on the ground: pour by hand into the switched-off generator.
local function addPourOption(context, worldobjects, playerObj, generator, barrel)
    local opt = context:addOption(getText("ContextMenu_KW_PourFromBarrel"), worldobjects, onPour, playerObj, generator)
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = getText("Tooltip_KW_BarrelPetrol", litres(F.petrolIn(barrel)))
    if generator:isActivated() then
        opt.notAvailable = true
        tip.description = getText("Tooltip_KW_PourOff")
    elseif generator:getMaxFuel() - generator:getFuel() < 0.1 then
        opt.notAvailable = true
        tip.description = getText("Tooltip_KW_PourFull")
    elseif F.petrolIn(barrel) < 0.01 then
        opt.notAvailable = true
        tip.description = getText("Tooltip_KW_PourEmpty")
    end
    opt.toolTip = tip
end

local function findGenerator(worldobjects)
    for _, obj in ipairs(worldobjects) do
        if instanceof(obj, "IsoGenerator") then return obj end
        local sq = obj:getSquare()
        local gen = sq and F.generatorOnSquare(sq)
        if gen then return gen end
    end
    return nil
end

local function findBarrel(worldobjects)
    for _, obj in ipairs(worldobjects) do
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

-- The same options when the player clicks the barrel instead of the generator.
local function onFillBarrelMenu(player, context, worldobjects, test)
    if test or findGenerator(worldobjects) then return end
    local barrel = findBarrel(worldobjects)
    if not barrel or barrel:getModData()[F.WATERKEY] == true then return end
    local generator = F.generatorNear(barrel)
    if not generator then return end
    local playerObj = getSpecificPlayer(player)
    if F.linkOf(generator) then
        if F.linkedBarrel(generator) == barrel and not F.isSpoiled(barrel) and not F.isAbove(barrel, generator) then
            addPourOption(context, worldobjects, playerObj, generator, barrel)
        end
        return
    end
    if not F.isPetrolBarrel(barrel) then return end
    local hose = playerObj:getInventory():getFirstTypeRecurse(F.HOSE)
    local opt = context:addOption(getText("ContextMenu_KW_LinkBarrel"), worldobjects, onLink, playerObj, generator, barrel)
    local tip = ISWorldObjectContextMenu.addToolTip()
    if hose then
        tip.description = getText(F.isAbove(barrel, generator) and "Tooltip_KW_LinkBarrel" or "Tooltip_KW_LinkLow", litres(F.petrolIn(barrel)))
        if F.catchesRain(barrel) then
            tip.description = tip.description .. " <LINE> " .. getText("Tooltip_KW_BarrelOpen")
        end
    else
        opt.notAvailable = true
        tip.description = getText("Tooltip_KW_NeedHose")
    end
    opt.toolTip = tip
end

local function onFillMenu(player, context, worldobjects, test)
    if test then return end
    local generator = findGenerator(worldobjects)
    if not generator then return end
    local playerObj = getSpecificPlayer(player)

    if F.linkOf(generator) then
        local barrel = F.linkedBarrel(generator)
        local opt = context:addOption(getText("ContextMenu_KW_UnlinkBarrel"), worldobjects, onUnlink, playerObj, generator)
        local tip = ISWorldObjectContextMenu.addToolTip()
        if barrel and F.isSpoiled(barrel) then
            tip.description = getText("Tooltip_KW_BarrelSpoiled")
        elseif barrel and not F.isAbove(barrel, generator) then
            tip.description = getText("Tooltip_KW_BarrelLow", litres(F.petrolIn(barrel)))
        elseif barrel then
            tip.description = getText("Tooltip_KW_BarrelPetrol", litres(F.petrolIn(barrel)))
            if F.catchesRain(barrel) then
                tip.description = tip.description .. " <LINE> " .. getText("Tooltip_KW_BarrelOpen")
            end
        else
            tip.description = getText("Tooltip_KW_BarrelGone")
        end
        opt.toolTip = tip
        if barrel and not F.isSpoiled(barrel) and not F.isAbove(barrel, generator) then
            addPourOption(context, worldobjects, playerObj, generator, barrel)
        end
        return
    end

    local barrels = F.barrelsNear(generator)
    if #barrels == 0 then
        local opt = context:addOption(getText("ContextMenu_KW_LinkBarrel"), worldobjects, nil)
        opt.notAvailable = true
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip.description = getText("Tooltip_KW_NoBarrel")
        opt.toolTip = tip
        return
    end
    local barrel = barrels[1]
    local hose = playerObj:getInventory():getFirstTypeRecurse(F.HOSE)
    local opt = context:addOption(getText("ContextMenu_KW_LinkBarrel"), worldobjects, onLink, playerObj, generator, barrel)
    local tip = ISWorldObjectContextMenu.addToolTip()
    if hose then
        tip.description = getText(F.isAbove(barrel, generator) and "Tooltip_KW_LinkBarrel" or "Tooltip_KW_LinkLow", litres(F.petrolIn(barrel)))
        if F.catchesRain(barrel) then
            tip.description = tip.description .. " <LINE> " .. getText("Tooltip_KW_BarrelOpen")
        end
    else
        opt.notAvailable = true
        tip.description = getText("Tooltip_KW_NeedHose")
    end
    opt.toolTip = tip
end

Events.OnFillWorldObjectContextMenu.Add(onFillMenu)
Events.OnFillWorldObjectContextMenu.Add(onFillBarrelMenu)
