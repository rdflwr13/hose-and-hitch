require "KnoxWorks/KW_Fuel"

-- Every ten game minutes the server tops up each loaded generator
-- from its linked barrel. Generators in unloaded areas wait until loaded.
local F = KnoxWorks.Fuel

local function tick()
    if isClient() then return end
    local reg = F.registry()
    local cell = getCell()
    if not cell then return end
    local gone = {}   -- removed after the walk: the game's tables dislike changes mid-walk
    for key, _ in pairs(reg.list) do
        local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        if x then
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local gen = F.generatorOnSquare(sq)
                if gen and F.linkOf(gen) then
                    F.topUp(gen)
                else
                    -- the linked generator was picked up: the hose drops where it stood
                    sq:AddWorldInventoryItem(F.HOSE, 0.5, 0.5, 0)
                    table.insert(gone, key)
                end
            end
        end
    end
    for _, key in ipairs(gone) do reg.list[key] = nil end
end

Events.EveryTenMinutes.Add(tick)
