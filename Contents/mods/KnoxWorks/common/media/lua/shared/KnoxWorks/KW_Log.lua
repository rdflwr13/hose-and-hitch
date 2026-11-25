-- The mod's journal: off unless switched on. Switched by a file, so it can be
-- turned on and off while the game or the server runs, with no restart:
--   the file Zomboid/Lua/knoxworks/log_on.txt exists  -> the journal is written
--   no such file                                       -> nothing is written
-- (on a server it is the Zomboid folder of the server's own user).
-- Looked at every few seconds by the clock. With the journal off the mod
-- prints nothing and does not put its readings into text every frame.

KnoxWorks = KnoxWorks or {}
KnoxWorks.Log = KnoxWorks.Log or {}
local L = KnoxWorks.Log

L.FILE = "knoxworks/log_on.txt"
L.EVERY = 5000   -- ms between looks at the file
L.on = false

function L.check()
    local r = getFileReader(L.FILE, false)
    L.on = r ~= nil
    if r then r:close() end
    return L.on
end

local lastLook = 0
local function onTick()
    local now = getTimestampMs()
    if now - lastLook < L.EVERY then return end
    lastLook = now
    L.check()
end
Events.OnTick.Add(onTick)
L.check()
