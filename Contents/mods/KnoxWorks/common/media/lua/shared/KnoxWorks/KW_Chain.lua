-- A third vehicle behind a towed one: a "virtual drawbar". Behind a towed
-- car a trailer or another car, behind a towed trailer another trailer.
-- Below, "first trailer" is the towed vehicle, "second trailer" the one
-- behind it, whatever they are.
--
-- The engine keeps one hitch per vehicle and drops the old hitch when a new
-- one is made, so nothing can be hitched behind a towed vehicle the game's
-- way. Instead the second one stays a free vehicle with its own wheels and
-- collisions, and the mod pulls it by its front tow point towards the rear
-- of the first one with small physics impulses, like a drawbar.
-- Only whoever simulates the second trailer's physics can push it, so the
-- server hands that job to the driver of the truck.
--
-- Safety first: the pull per frame is small and capped; if the trailers end
-- up too far apart the drawbar lets go and the second trailer just stays.
--
-- The link lives in the second trailer's first part modData (parts are what
-- the game syncs and saves). Two ids of the first trailer are kept there:
-- its saved id, which only the server and singleplayer know, and its id in
-- this server session, which players know. The server keeps the second one
-- up to date, because it changes after a restart.

require "KnoxWorks/KW_Log"

KnoxWorks = KnoxWorks or {}
KnoxWorks.Chain = KnoxWorks.Chain or {}
local C = KnoxWorks.Chain

C.KEY = "KnoxWorksChainParent"         -- saved id of the first trailer
C.KEY_NOW = "KnoxWorksChainParentNow"  -- its id in this server session
C.ATTACH = "trailer"        -- attachment the game uses for hitching
C.CONNECT_DIST = 2.0        -- hitch points this close can be connected
C.BREAK_DIST = 3.5          -- further apart than this, the drawbar lets go
C.SLACK = 0.03              -- play in the drawbar, no pull inside it
C.PARK_PLAY = 0.10          -- extra play while the first one stands, m
C.ROPE = 1.5                -- a car behind a car goes on a rope, as the game tows
                            -- cars (Bullet.addRopeConstraint, length 1.5): no pull
                            -- until it is taut
-- The hitch is held like a stiff spring with a damper. The damper works on
-- the speed of the two hitch points themselves (not of the vehicles' middles),
-- so a turning first trailer drags the hitch round with it at once instead
-- of the second one swinging along its tail. Damping is set to the critical
-- value 2*sqrt(stiffness): no bouncing.
C.STIFF = 100.0             -- pull per metre the hitch is off: m/s²
C.DAMP = 20.0               -- 2*sqrt(STIFF)
C.MAX_ACCEL = 50.0          -- strongest pull, m/s² (about 5 g)
C.LIFT_STIFF = 60.0         -- holding the nose up at the hitch height
C.LIFT_DAMP = 16.0          -- about 2*sqrt(LIFT_STIFF)
C.MAX_LIFT = 25.0           -- strongest lift, m/s²
C.LIFT_GROW = 8.0           -- how fast the steady lift grows per metre of sag, m/s² per second
C.LIFT_START = 2.5          -- steady lift to start from: what the game's trailers settled at, m/s²
C.LIFT_SHARE = 0.0          -- upwards: 1 holds the whole mass, 0 only the turning nose
C.LIFT_REACH = 0.15         -- the steady lift only grows with the nose this close to the hitch height, m
C.SIDE_SCALE = 2.0          -- how heavy the nose is taken to be sideways, times what its size gives (measured in the game)
C.SEARCH = 8                -- squares to look for vehicles around
C.FRAME_DAMP = 0.35          -- damper times frame time never above this: no shaking on slow frames
C.SMOOTH = 0.5              -- share of a new speed reading taken in (the rest is the old one)
C.STILL_SPEED = 0.3         -- below this the hitch points count as standing together, m/s
C.PARKED_SPEED = 0.2        -- the first one slower than this counts as standing, m/s
C.SLEEP_SPEED = 0.1         -- a parked pair this calm at the hitch is put to sleep, m/s
C.SLEEP_DZ = 0.015          -- with the nose this close to the hitch height, m
C.SLEEP_AFTER = 0.5         -- after being that calm this long, s
C.STILL_TIME = 0.1          -- seconds without any move: both stand still
C.FEED = 1.0                -- share of the first one's speeding up given to the second at once
C.FEED_SMOOTH = 0.1          -- share of a new reading of it taken in
C.MAX_FEED = 15.0           -- at most this much of it, m/s²
C.PULL_GROW = 300.0         -- extra pull growing per metre the drawbar stays stretched, m/s² per second
C.PULL_LEAK = 3.0           -- inside the play the extra pull fades this many times per second
C.MAX_PULL = 20.0           -- at most this much extra pull, m/s²

local function v3() return Vector3f.new() end

function C.linkPart(vehicle)
    if not vehicle or vehicle:getPartCount() < 1 then return nil end
    return vehicle:getPartByIndex(0)
end

function C.parentIdOf(child)
    local part = C.linkPart(child)
    return part and part:getModData()[C.KEY] or nil
end

function C.isChained(child)
    return C.parentIdOf(child) ~= nil
end

-- The second trailer is chained to this first one. Players compare the
-- session id: the saved id of a vehicle is not sent to them.
function C.isParentOf(child, parent)
    local part = C.linkPart(child)
    if not part or not parent then return false end
    local md = part:getModData()
    if md[C.KEY] == nil then return false end
    if isClient() then
        return md[C.KEY_NOW] ~= nil and md[C.KEY_NOW] == parent:getId()
    end
    return md[C.KEY] == parent:getSqlId()
end

C.FRONT = "trailerfront"   -- tow point at the front of a car (trailers have none)

-- A car has tow points at both ends, as the game itself uses for towing;
-- a trailer has only its hitch at the front.
function C.isCar(vehicle)
    local script = vehicle:getScript()
    return script ~= nil and script:getAttachmentById(C.FRONT) ~= nil
end

-- Where the vehicle is pulled from, world coordinates: a car by its front
-- tow point, a trailer by its hitch.
function C.frontHitch(vehicle)
    if C.isCar(vehicle) then return vehicle:getAttachmentWorldPos(C.FRONT, v3()) end
    return vehicle:getTowedByWorldPos(C.ATTACH, v3())
end

-- How far back the vehicle's body reaches (script units, along its length):
-- the back of the rearmost box or ball it collides with, nil if it has none.
C.REAR_CLEAR = 0.02   -- the hitch point stands this far behind the body
function C.bodyRear(script)
    if not script then return nil end
    local rear
    for i = 0, script:getPhysicsShapeCount() - 1 do
        local s = script:getPhysicsShape(i)
        local kind, o = s:getTypeString(), s:getOffset()
        local z
        if kind == "box" then z = o:z() - s:getExtents():z() / 2
        elseif kind == "sphere" then z = o:z() - s:getRadius() end
        if z and (not rear or z < rear) then rear = z end
    end
    return rear
end

-- Where something is hitched behind the vehicle: a car has its own rear tow
-- point; a trailer has none, so its front hitch is mirrored to the back.
-- On a long trailer (one for livestock) the mirrored point falls inside the
-- body, near the rear wheels: the nose of what follows then rams the back
-- wall while the drawbar pulls it in. So the point is never inside the body.
function C.rearHitch(vehicle)
    if C.isCar(vehicle) then return vehicle:getAttachmentWorldPos(C.ATTACH, v3()) end
    local loc = vehicle:getAttachmentLocalPos(C.ATTACH, v3())
    if not loc then return nil end
    local script = vehicle:getScript()
    local mz = 0
    if script and script:getModel() then mz = script:getModel():getOffset():z() end
    local z = 2 * mz - loc:z()
    local back = C.bodyRear(script)
    if back and z > back - C.REAR_CLEAR then z = back - C.REAR_CLEAR end
    return vehicle:getWorldPos(loc:x(), loc:y(), z, v3())
end

-- Where along its length the vehicle stands on its wheels (script units):
-- the middle of all its wheels, nil if it has none.
function C.axleZ(script)
    if not script then return nil end
    local n = script:getWheelCount()
    if n <= 0 then return nil end
    local sum = 0
    for i = 0, n - 1 do sum = sum + script:getWheel(i):getOffset():z() end
    return sum / n
end

-- The height the second one's hitch is held at behind a trailer (world
-- height), nil when the first one's own point is to be used.
-- A trailer has no tow point at the back, and its front hitch mirrored to
-- the back is as low as that hitch: behind a tall trailer (one for
-- livestock) that is ground level, and the nose of what follows would lie on
-- the ground and drag. So behind a trailer the second one is held level with
-- the first: its hitch as high over its own wheels as the first one's
-- lengthwise tilt asks for. Behind a car its real tow point is used.
function C.levelHeight(child, parent)
    if C.isCar(parent) or C.isCar(child) then return nil end
    local wz = C.axleZ(child:getScript())
    if not wz then return nil end
    local loc = child:getAttachmentLocalPos(C.ATTACH, v3())
    if not loc then return nil end
    local lx, ly, lz = loc:x(), loc:y(), loc:z()
    local over = child:getWorldPos(lx, ly, wz, v3()):z()
    local tilt = parent:getWorldPos(0, 0, 1, v3()):z() - parent:getWorldPos(0, 0, 0, v3()):z()
    return over + (lz - wz) * tilt
end

local function dist2d(a, b)
    local dx, dy = a:x() - b:x(), a:y() - b:y()
    return math.sqrt(dx * dx + dy * dy), dx, dy
end

-- Vehicles around a vehicle, each once.
function C.vehiclesNear(vehicle)
    local out, seen = {}, {}
    local cx, cy, z = math.floor(vehicle:getX()), math.floor(vehicle:getY()), math.floor(vehicle:getZ())
    local cell = getCell()
    for x = cx - C.SEARCH, cx + C.SEARCH do
        for y = cy - C.SEARCH, cy + C.SEARCH do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local moving = sq:getMovingObjects()
                for i = 0, moving:size() - 1 do
                    local o = moving:get(i)
                    if instanceof(o, "BaseVehicle") and o ~= vehicle and not seen[o] then
                        seen[o] = true
                        table.insert(out, o)
                    end
                end
            end
        end
    end
    return out
end

function C.findParent(child)
    if not C.isChained(child) then return nil end
    for _, v in ipairs(C.vehiclesNear(child)) do
        if C.isParentOf(child, v) then return v end
    end
    return nil
end

function C.childOf(parent)
    for _, v in ipairs(C.vehiclesNear(parent)) do
        if C.isParentOf(v, parent) then return v end
    end
    return nil
end

-- How far the front of the second vehicle is from the rear of the first.
function C.gap(child, parent)
    local rear, front = C.rearHitch(parent), C.frontHitch(child)
    if not rear or not front then return nil end
    return (dist2d(rear, front))
end

-- A link counts only while the two stand within reach of the drawbar. A
-- link left behind with the vehicles apart (a failed hitch, an old save) is
-- dead: the menu does not offer to unhitch it and it does not block a new one.
function C.isLive(child, parent)
    local d = parent and C.gap(child, parent)
    return d ~= nil and d <= C.BREAK_DIST
end

function C.liveParentOf(child)
    local parent = C.findParent(child)
    if parent and C.isLive(child, parent) then return parent end
    return nil
end

function C.liveChildOf(parent)
    local child = C.childOf(parent)
    if child and C.isLive(child, parent) then return child end
    return nil
end

-- Who can take something behind it on the drawbar:
--   a vehicle the game is towing (a trailer or a car), with nothing behind it;
--   or a free car at the head, when what goes behind it already tows
--   something the game's way (the order of hitching does not matter).
function C.canTakeChild(parent)
    if parent:getVehicleTowing() ~= nil or C.rearHitch(parent) == nil then return false end
    if C.liveParentOf(parent) ~= nil or C.liveChildOf(parent) ~= nil then return false end
    return parent:getVehicleTowedBy() ~= nil or C.isCar(parent)
end

-- The pair is part of a tow: the first is towed the game's way, or the
-- second tows something the game's way, or someone drives the first.
-- A pair left standing on its own is left alone.
function C.onTow(child, parent)
    return parent:getVehicleTowedBy() ~= nil or child:getVehicleTowing() ~= nil or parent:getDriver() ~= nil
end

-- What may go behind what: behind a car a trailer or another car, behind a
-- trailer only a trailer.
function C.canFollow(parent, child)
    return C.isCar(parent) or not C.isCar(child)
end

-- A free vehicle whose front is right behind the parent.
function C.candidateFor(parent)
    if not C.canTakeChild(parent) then return nil end
    local rear = C.rearHitch(parent)
    local best, bestDist = nil, C.CONNECT_DIST
    for _, v in ipairs(C.vehiclesNear(parent)) do
        -- behind a free car only what already tows something: a free pair is the game's own hitch
        local headOk = parent:getVehicleTowedBy() ~= nil or v:getVehicleTowing() ~= nil
        if v ~= parent:getVehicleTowedBy() and C.canFollow(parent, v) and v:getVehicleTowedBy() == nil and headOk
            and C.liveParentOf(v) == nil and v:getDriver() == nil then
            local front = C.frontHitch(v)
            if front then
                local d = dist2d(rear, front)
                if d <= bestDist then best, bestDist = v, d end
            end
        end
    end
    return best
end

-- The vehicle at the head of the chain, the one with the driver.
function C.headOf(child)
    local parent = C.findParent(child)
    if not parent then return nil, nil end
    local head = parent
    local guard = 0
    while head:getVehicleTowedBy() and guard < 4 do
        head = head:getVehicleTowedBy()
        guard = guard + 1
    end
    return head, parent
end

-- One frame of the drawbar. Returns "pulled", "idle", "asleep", "break" or "none".
-- Hitch point positions of the last frame, per second vehicle, to tell how
-- fast the two hitch points move.
C.prev = setmetatable({}, { __mode = "k" })
-- frames the drawbar ran and how many of them the physics had moved on (test readings)
C.stat = { frames = 0, moves = 0 }
-- last force and nose height per second vehicle (test readings)
C.info = setmetatable({}, { __mode = "k" })

function C.step(child, parent, dt)
    -- towed the game's way by something else: the drawbar keeps out of it
    if child:getVehicleTowedBy() then return "none" end
    -- a pair standing on its own (the first one unhitched from the truck) is
    -- still hitched: the nose stays on the drawbar, but nothing pulls it
    -- along, so no trailer ever moves by itself
    local loose = not C.onTow(child, parent)
    -- nobody drives the second: the game puts its brakes on every frame
    -- (CarController.park); on the drawbar they stay off, the game puts them
    -- back from the brake parts once it is unhitched (updatePartStats)
    if child:getBrakingForce() > 0 then child:setBrakingForce(0) end
    local rear = C.rearHitch(parent)
    local front = C.frontHitch(child)
    if not rear or not front then return "none" end
    local d, dx, dy = dist2d(rear, front)
    if d > C.BREAK_DIST then C.prev[child] = nil return "break" end
    -- behind a trailer the nose is held level with it, not at its mirrored hitch
    local level = C.levelHeight(child, parent)
    if level then rear = Vector3f.new(rear:x(), rear:y(), level) end

    -- speed of the hitch points (rear of the first minus front of the second);
    -- world x, world y, height. The physics moves the vehicles in its own
    -- steps, not on every frame of the game: for a few frames the points
    -- stand still, then jump. The speed is taken only when they have moved,
    -- over all the time since the last move, and smoothed; between moves the
    -- last speed holds.
    local rvx, rvy, rvz = 0, 0, 0
    local last = C.prev[child]
    C.stat.frames = C.stat.frames + 1
    if last then
        local moved = rear:x() ~= last.rx or rear:y() ~= last.ry or rear:z() ~= last.rz
            or front:x() ~= last.fx or front:y() ~= last.fy or front:z() ~= last.fz
        last.wait = last.wait + dt
        if moved and last.wait > 0 then
            C.stat.moves = C.stat.moves + 1
            local w = last.wait
            local k = C.SMOOTH
            last.vx = last.vx + k * (((rear:x() - last.rx) - (front:x() - last.fx)) / w - last.vx)
            last.vy = last.vy + k * (((rear:y() - last.ry) - (front:y() - last.fy)) / w - last.vy)
            last.vz = last.vz + k * (((rear:z() - last.rz) - (front:z() - last.fz)) / w - last.vz)
            -- the first one's hitch alone: its speed, and how fast that changes
            local hvx = last.hvx + k * ((rear:x() - last.rx) / w - last.hvx)
            local hvy = last.hvy + k * ((rear:y() - last.ry) / w - last.hvy)
            local kf = C.FEED_SMOOTH
            last.ffx = last.ffx + kf * ((hvx - last.hvx) / w - last.ffx)
            last.ffy = last.ffy + kf * ((hvy - last.hvy) / w - last.ffy)
            last.hvx, last.hvy = hvx, hvy
            last.rx, last.ry, last.rz = rear:x(), rear:y(), rear:z()
            last.fx, last.fy, last.fz = front:x(), front:y(), front:z()
            last.wait = 0
        elseif last.wait > C.STILL_TIME then
            -- nothing moved for a while: both really stand still
            last.vx, last.vy, last.vz = 0, 0, 0
            last.hvx, last.hvy, last.ffx, last.ffy = 0, 0, 0, 0
        end
        rvx, rvy, rvz = last.vx, last.vy, last.vz
    else
        local vp = parent:getLinearVelocity(v3())
        local vc = child:getLinearVelocity(v3())
        -- physics vectors: x east, y up, z south; world: x east, y south
        rvx, rvy, rvz = vp:x() - vc:x(), vp:z() - vc:z(), vp:y() - vc:y()
        C.prev[child] = { rx = rear:x(), ry = rear:y(), rz = rear:z(), fx = front:x(), fy = front:y(), fz = front:z(),
            vx = rvx, vy = rvy, vz = rvz, wait = 0, hvx = vp:x(), hvy = vp:z(), ffx = 0, ffy = 0, pull = 0 }
    end

    -- the first one stands or moves (needed for the play of the drawbar)
    local vp = parent:getLinearVelocity(v3())
    local parked = vp:x() * vp:x() + vp:z() * vp:z() < C.PARKED_SPEED * C.PARKED_SPEED

    -- a car on a rope: slack until taut, and slack means no pull at all.
    -- A standing pair has a wider play: a trailer at rest often comes to
    -- stand just at the edge of the narrow play, and pulling it back each
    -- time it crosses the edge jerks it every second or two
    local onRope = C.isCar(child)
    local play = onRope and C.ROPE or (C.SLACK + (parked and C.PARK_PLAY or 0))
    local gap = math.max(0, d - play)
    if onRope and gap <= 0 then rvx, rvy = 0, 0 end

    -- the first one stands, the hitch is inside the play and hardly moving:
    -- the hitch is left alone sideways, so the physics' own tiny jitter at a
    -- standstill is not pushed back and forth. On the move the damper always
    -- works, a damper switching on and off would jerk the trailer
    if parked and gap <= 0 and rvx * rvx + rvy * rvy < C.STILL_SPEED * C.STILL_SPEED then rvx, rvy = 0, 0 end

    -- how fast the first one's hitch speeds up, slows down and swings
    -- round in a bend (world x, y), read whenever the physics has moved it.
    -- The second is given the same at once: a spring alone has to stretch
    -- before it pulls, and the drawbar then feels like a rubber band
    local feed = C.prev[child]
    local ffx, ffy = 0, 0
    if not parked and not onRope then
        ffx, ffy = C.FEED * feed.ffx, C.FEED * feed.ffy
        local f = math.sqrt(ffx * ffx + ffy * ffy)
        if f > C.MAX_FEED then ffx, ffy = ffx * C.MAX_FEED / f, ffy * C.MAX_FEED / f end
    end

    local nx, ny = 0, 0
    if d > 0.0001 then nx, ny = dx / d, dy / d end
    -- the force acts one frame late, so a damper stronger than the frame can
    -- follow overshoots and shakes the vehicle; on a slow frame it is softened
    local damp, stiff = C.dampFor(dt)
    -- what the game's trailer resists with that the drawbar cannot know
    -- (its wheels in a bend, rolling): while the drawbar stays stretched on
    -- the move, a pull along the drawbar grows slowly until it closes up. It
    -- turns with the drawbar, so in a long bend it keeps up; it fades inside
    -- the play and is dropped once the first one stands
    if parked or onRope or loose then
        feed.pull = 0
    elseif child:isPhysicsActive() then
        if gap > 0 then
            feed.pull = math.min(C.MAX_PULL, feed.pull + C.PULL_GROW * gap * dt)
        else
            feed.pull = feed.pull * math.max(0, 1 - C.PULL_LEAK * dt)
        end
    end
    local ax = ffx + feed.pull * nx + stiff * gap * nx + damp * rvx
    local ay = ffy + feed.pull * ny + stiff * gap * ny + damp * rvy
    local a = math.sqrt(ax * ax + ay * ay)
    if a > C.MAX_ACCEL then ax, ay = ax * C.MAX_ACCEL / a, ay * C.MAX_ACCEL / a end
    if loose then ax, ay, rvx, rvy = 0, 0, 0, 0 end

    -- the hitch holds the nose up, as the game's own hitch does: the front of
    -- the second vehicle is held at the height of the first one's rear
    -- (world height is the third coordinate here, the second in physics)
    local dz = rear:z() - front:z()
    if onRope then dz, rvz = 0, 0 end   -- a car stands on its own front wheels
    local liftDamp = math.min(C.LIFT_DAMP, damp)
    local au = onRope and 0 or (C.LIFT_STIFF * dz + liftDamp * rvz)
    if au > C.MAX_LIFT then au = C.MAX_LIFT elseif au < -C.MAX_LIFT then au = -C.MAX_LIFT end
    -- the nose has a weight of its own: a steady lift for the whole vehicle,
    -- grown slowly while the nose hangs low, so it stands at the hitch
    -- height instead of sagging under the soft spring
    -- It only ever holds up, never presses the nose down, and it does not
    -- grow while the nose stands far above the hitch height: then the nose
    -- rests on something (the first one unhitched and tipped), and a lift
    -- grown against that would throw the nose about once it is free.
    -- Below the hitch it grows at any distance: a heavy nose (the PZK small
    -- tank, 391 kg, 2026-11-24) sagged 0.65 m low, out of reach, and the
    -- lift stayed at its start and could not raise it
    local hold = C.prev[child]
    if not onRope and child:isPhysicsActive() and (dz > 0 or math.abs(dz) < C.LIFT_REACH) then
        hold.lift = math.max(0, math.min(C.MAX_LIFT, (hold.lift or C.LIFT_START) + C.LIFT_GROW * dz * dt))
    end
    local steady = hold.lift or (onRope and 0 or C.LIFT_START)
    local journal = KnoxWorks.Log.on
    if journal then
        C.lastLift = string.format("%.2f/%.1f", dz, steady)
        -- no force this frame unless it is pulled below: the journal must not
        -- show the last pull as if it still acted (2026-11-24 a resting car
        -- showed a 19.8 kN force long after the drawbar had stopped pulling)
        C.lastForce = "0,0,0"
        C.info[child] = { force = C.lastForce, lift = C.lastLift, pull = string.format("%.1f", feed.pull) }
    end
    -- A parked pair is put to sleep once it has settled, the way the game
    -- puts every standing vehicle to sleep: asleep, a vehicle is frozen in
    -- the pose it has, so the nose stays up at the hitch with no force at all,
    -- no jitter, and wherever the player goes. It wakes when the first one
    -- moves off or the second is knocked out of place.
    if parked then
        if not child:isPhysicsActive() then
            if gap <= 0 and math.abs(dz) < C.SLEEP_DZ then return "asleep" end
        elseif gap <= 0 and rvx * rvx + rvy * rvy < C.SLEEP_SPEED * C.SLEEP_SPEED
            and math.abs(rvz) < C.SLEEP_SPEED and math.abs(dz) < C.SLEEP_DZ then
            hold.calm = (hold.calm or 0) + dt
            if hold.calm >= C.SLEEP_AFTER then
                hold.calm = 0
                child:setPhysicsActive(false)
                return "asleep"
            end
        else
            hold.calm = 0
        end
    else
        hold.calm = 0
        -- the first one moves off: a sleeping second one wakes to follow
        if not child:isPhysicsActive() then child:setPhysicsActive(true) end
    end
    -- nothing to do: in place, moving together, nose at the hitch
    if gap <= 0 and math.abs(rvx) + math.abs(rvy) < 0.05 and math.abs(dz) < 0.05 and math.abs(steady) < 0.01 then return "idle" end

    -- addImpulse is not a one-off push: the game hands it to the physics as a
    -- force for the next frame (Bullet.applyCentralForceToVehicle in
    -- BaseVehicle.update), so it is given as a force: mass x acceleration
    -- The force is put at the front hitch, not at the middle. Along the line
    -- from the middle to the hitch it just moves the vehicle (whole mass).
    -- Across that line and upwards it also turns the vehicle, and the hitch
    -- point then gives way several times easier: the same force there would
    -- throw the nose from side to side. So each part of the force is sized for
    -- how heavy the vehicle feels at the hitch in that direction.
    local m = child:getMass()
    local rx, ry = front:x() - child:getX(), front:y() - child:getY()
    local fx, fy, fu = C.hitchForce(child, m, rx, ry, ax, ay, au)
    fu = fu + steady * m
    local force = Vector3f.new(fx, fu, fy)
    local relPos = Vector3f.new(rx, 0, ry)
    if not child:isPhysicsActive() then child:setPhysicsActive(true) end
    child:addImpulse(force, relPos)
    if journal then
        C.lastForce = string.format("%.0f,%.0f,%.0f", fx, fu, fy)
        C.info[child] = { force = C.lastForce, lift = C.lastLift, pull = string.format("%.1f", feed.pull) }
    end
    return "pulled"
end

-- Damper and spring for a frame of dt seconds: at most what a frame can
-- follow (half the speed difference evened out per frame), the spring kept
-- at the critical value for that damper.
function C.dampFor(dt)
    local damp = C.DAMP
    if dt and dt > 0 then damp = math.min(damp, C.FRAME_DAMP / dt) end
    local stiff = math.min(C.STIFF, damp * damp / 4)
    return damp, stiff
end

-- Size of the vehicle for turning it: squared radius of gyration about the
-- vertical axis (length and width) and about the side axis (length and height),
-- as for a solid box.
local function gyration(vehicle)
    local script = vehicle:getScript()
    local e = script and script:getExtents()
    local w, h, l = 1.8, 1.2, 3.0
    if e then w, h, l = math.max(0.5, e:x()), math.max(0.5, e:y()), math.max(0.5, e:z()) end
    return (l * l + w * w) / 12, (l * l + h * h) / 12
end

-- Force at the hitch (world x, world y, up) that gives the hitch point the
-- acceleration ax, ay, au, for a vehicle of mass m whose hitch is rx, ry from
-- its middle.
function C.hitchForce(vehicle, m, rx, ry, ax, ay, au)
    local r2 = rx * rx + ry * ry
    local kYaw, kPitch = gyration(vehicle)
    local mSide = m * kYaw / (kYaw + r2) * C.SIDE_SCALE
    -- upwards: held as the turning nose alone (LIFT_SHARE 0) or as the whole
    -- mass (1); the nose alone stands steady in the game with the slow LIFT_GROW
    local mUp = m * kPitch / (kPitch + r2)
    mUp = mUp + C.LIFT_SHARE * (m - mUp)
    if r2 < 0.0001 then return ax * m, ay * m, au * m end
    local r = math.sqrt(r2)
    local ex, ey = rx / r, ry / r
    local along = ax * ex + ay * ey
    local sx, sy = ax - along * ex, ay - along * ey
    return along * m * ex + sx * mSide, along * m * ey + sy * mSide, au * mUp
end
