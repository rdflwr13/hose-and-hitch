require "KnoxWorks/KW_Water"
require "KnoxWorks/KW_Hoist"

-- Every ten game minutes the server refills house taps from the barrels
-- connected to each house. Houses far from players wait until loaded.
local W = KnoxWorks.Water
local F = KnoxWorks.Fuel

local function tick()
    if isClient() then return end
    local reg = W.registry()
    local cell = getCell()
    if not cell then return end

    local houses = {}   -- building key -> { building, barrels }
    local gone = {}   -- removed after the walk: the game's tables dislike changes mid-walk
    for key, _ in pairs(reg.list) do
        local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        if x then
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local barrel = nil
                local objects = sq:getObjects()
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    if F.isBarrel(obj) and W.isConnected(obj) then barrel = obj break end
                end
                if not barrel then
                    table.insert(gone, key)   -- barrel taken away
                else
                    -- under the sky the barrel stands open; indoors it keeps its lid
                    if sq:isOutside() then KnoxWorks.Hoist.openToRain(barrel) end
                    local building = W.buildingOf(barrel)
                    local bkey = W.buildingKey(building)
                    if bkey then
                        houses[bkey] = houses[bkey] or { building = building, barrels = {} }
                        table.insert(houses[bkey].barrels, barrel)
                    end
                end
            end
        end
    end

    for _, key in ipairs(gone) do reg.list[key] = nil end

    for _, house in pairs(houses) do
        W.supply(house.building, house.barrels)
    end
end

Events.EveryTenMinutes.Add(tick)
