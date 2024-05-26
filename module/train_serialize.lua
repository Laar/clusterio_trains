local serialize = require("modules/clusterio/serialize")

-- Helpers --
-------------

local connected_directions = {
    defines.rail_connection_direction.straight,
    defines.rail_connection_direction.left,
    defines.rail_connection_direction.right,
}

local opposite_rail_direction = function (direction)
    -- Assumes that defines.rail_direction is an enum 0,1
    return 1 - direction
end

local function distance(p1, p2)
    local dx = p1.x - p2.x
    local dy = p1.y - p2.y
    return math.sqrt(dx*dx + dy*dy)
end

local function lerp(p1, p2, t)
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    return {
        x = p1.x + t * dx,
        y = p1.y + t * dy
    }
end

local function pointing_orientation(p1, p2)
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    local angle = math.atan2(dy, dx) / (2 * math.pi)
    angle = -(angle + 0.25)
    return angle % 1
end

local function best_direction(orientation)
    return math.floor(8*orientation + 0.5) % 8
end

-- Train functions --
---------------------

local is_train_stopped_forwards = function(train)
    -- For a LuaTrain stopped at a station, determine if it is stopped in the
    -- forward direction of the train
    if not train.valid or train.station == nil then return nil end
    local station = train.station
    local station_rail = station.connected_rail
    if not station_rail then return nil end
    -- Train does not end up on the station rail but 1 rail before it
    local station_rail_dir = station.connected_rail_direction
    local front_rail = train.front_rail
    local back_rail = train.back_rail
    for _, connect_dir in ipairs(connected_directions) do
        local et, _, _ = station_rail.get_connected_rail{
            rail_direction = opposite_rail_direction(station_rail_dir),
            rail_connection_direction = connect_dir
        }
        if et and et.valid then
            if et == front_rail then
                return true
            end
            if et == back_rail then
                return false
            end
        end
    end
    return true -- Guess the most likely option
end

local linear_train_position = function (carriages_or_luatrain)
    -- Given a set of train carriages or a LuaTrain compute:
    -- The total length of the train
    -- The position of the centre of each carriage along a straight line, such
    -- that the first carriages is correctly stopped a station at len=0
    local object_name = carriages_or_luatrain.object_name
    local iter
    if object_name == 'LuaTrain'
    then
        local next_proto = function (carriages, i)
            i = i + 1
            local v = carriages[i]
            if v then 
                return i, v.name
            end
        end
        iter = function (lua_train)
            return next_proto, lua_train.carriages, 0
        end
    else
        iter = ipairs
    end
    local carriage_positions = {}
    local linear_position = 0
    for idx, cproto_name in iter(carriages_or_luatrain) do
        local proto = game.entity_prototypes[cproto_name]
        local half_length = (proto.joint_distance + proto.connection_distance) / 2
        if (idx == 0) then
            -- Offset of the initial wagons centre
            linear_position = linear_position + proto.collision_box.left_top.y
        else
            linear_position = linear_position + half_length
        end
        carriage_positions[idx] = linear_position
        linear_position = linear_position + half_length
    end
    local total_length = linear_position
    return total_length, carriage_positions
end


-- Scheduele --
---------------

local function serialize_schedule(schedule)
    local srecords = {}
    local c = schedule.current
    for rid, record in ipairs(schedule.records) do
        if record.station and not record.temporary then
            table.insert(srecords, {
                s = record.station,
                w = record.wait_conditions
            })
        elseif rid < c then
            c = c - 1
        end
    end
    -- Case: Only temporary stops
    if #srecords == 0 then return nil end
    -- Advance to the next stop
    c = c % #srecords +1
    return {
        c = c,
        r = srecords
    }
end

local function deserizalize_schedule(sschedule)
    if sschedule == nil then return end
    local records = {}
    for rid, srecord in ipairs(sschedule.r) do
        records[rid] = {
            station = srecord.s,
            wait_conditions = srecord.w
        }
    end
    return {
        current = sschedule.c,
        records = records
    }
end

-- Trains --
------------

local function serialize_train(train)
    local forwards = is_train_stopped_forwards(train)
    -- Iteration direction
    local sstart, send, sinc
    if forwards
    then
        -- Forward direction
        sstart = 1
        send = #train.carriages
        sinc = 1
    else
        -- Backwards direction
        sstart = #train.carriages
        send = 1
        sinc = -1
    end
    -- TODO: health, color
    local strain = {
        t = {}, -- Types
        d = {}, -- Directions
        c = {}, -- Inventory
        f = {}, -- Fluids
        g = {}, -- Grid
        h = {}, -- health
        co = {}, -- Colors
        b = {}, -- Burner
         -- schedule, assumed to be present
        s = serialize_schedule(train.schedule)
    }

    local cid = 0
    for sind = sstart, send, sinc do
        cid = cid + 1
        local carriage = train.carriages[sind]
        strain.t[cid] = carriage.name
        strain.d[cid] = carriage.is_headed_to_trains_front == forwards
        -- Inventory
        local inventories = {}
        for i = 1, carriage.get_max_inventory_index() do
            local inventory = carriage.get_inventory(i)
            if (inventory) then
                inventories[i] = serialize.serialize_inventory(inventory)
            end
        end
        strain.c[cid] = inventories
        -- Fluids
        local fluidbox = carriage.fluidbox
        if #fluidbox > 0 then
            local fluids = {}
            for i = 1, #fluidbox do
                fluids[i] = fluidbox[i]
            end
            strain.f[cid] = fluids
        end
        -- Grid
        if carriage.grid then
            strain.g[cid] = serialize.serialize_equipment_grid(carriage.grid)
        end
        -- Burner
        if carriage.burner and carriage.burner.currently_burning then
            local cburner = carriage.burner
            strain.b[cid] = {
                r = cburner.remaining_burning_fuel,
                b = cburner.currently_burning.name
            }
        end
        if carriage.health ~= carriage.prototype.max_health then
            strain.h[cid] = carriage.health
        end
        if carriage.color ~= nil and carriage.color ~= carriage.prototype.color then
            local co = carriage.color
            strain.co[cid] = {co.r, co.g, co.b, co.a}
        end
    end
    return strain
end

local function spawn_train(stop, strain)
    -- TODO xpcall
    local total_length, carriage_positions = linear_train_position(strain.t)
    local crail = stop.connected_rail
    local rail_dir = stop.connected_rail_direction
    local segment_length = crail.get_rail_segment_length()
    if segment_length < total_length then
        -- Might want some margin
        game.print({'', 'Too short segment'})
        return
    end
    local segment_rails = crail.get_rail_segment_rails(rail_dir)
    -- Actual creation
    local created_entities = {}
    -- TODO: Take from the trainstop registration
    local surface = game.get_surface('nauvis')
    local rail_index = 1
    local rail_length = 0
    local rail_distance = 0

    for idx, ctype in ipairs(strain.t) do
        local target_distance = carriage_positions[idx]
        while rail_distance < target_distance and rail_index < #segment_rails do
            rail_index = rail_index + 1
            rail_length = distance(segment_rails[rail_index-1].position, segment_rails[rail_index].position)
            rail_distance = rail_distance + rail_length
        end
        local interpolant = (rail_distance - target_distance) / rail_length
        local placement_pos = lerp(segment_rails[rail_index].position, segment_rails[rail_index-1].position, interpolant)
        local direction = best_direction(pointing_orientation(segment_rails[rail_index-1].position, segment_rails[rail_index].position))
        if not strain.d[idx]
        then
            direction = (direction + 4) % 8
        end
        local et = surface.create_entity{
            name = ctype,
            position = placement_pos,
            force = game.forces.player,
            direction = direction
        }
        -- TODO: Handling of not placing trains, merging trains
        if et then
            table.insert(created_entities, et)
        else
            game.print({'', 'Unsuccesful spawn ', idx})
            return nil
        end
    end
    return created_entities
end

local function deserialize_train(train_carriages, strain)
    -- Inventory, fluids, grid, burner, schedule
    for cid, carriage in ipairs(train_carriages) do
        local sinventory = strain.c[cid]
        for iidx, sinv in pairs(sinventory) do
            serialize.deserialize_inventory(carriage.get_inventory(iidx), sinv)
        end

        -- Fluids
        local sfluids = strain.f[cid]
        if sfluids ~= nil then
            local fluidbox = carriage.fluidbox
            for sidx, sfluid in pairs(sfluids) do
                fluidbox[sidx] = {
                    name = sfluid.name,
                    amount = sfluid.amount,
                    temperature = sfluid.temperature
                }
            end
        end

        -- grid
        local sgrid = strain.g[cid]
        if sgrid ~= nil then
            serialize.deserialize_equipment_grid(carriage.grid, sgrid)
        end
        -- Burner
        local sburner = strain.b[cid]
        if sburner ~= nil then
            local cburner = carriage.burner
            cburner.currently_burning = game.item_prototypes[sburner.b]
            cburner.remaining_burning_fuel = sburner.r
        end
        if strain.h[cid] ~= nil then
            carriage.health = strain.h[cid]
        end
        if strain.co[cid] ~= nil then
            carriage.color = strain.co[cid]
        end
    end
    train_carriages[1].train.schedule = deserizalize_schedule(strain.s)
end

local function destroy_train(train)
    for _, carriage in ipairs(train.carriages) do
        -- TODO: raise_destroy?
        carriage.destroy{}
    end
end


return {
    linear_train_position = linear_train_position,
    serialize_train = serialize_train,
    spawn_train = spawn_train,
    deserialize_train = deserialize_train
}