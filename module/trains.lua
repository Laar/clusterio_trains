local clusterio_api = require("modules/clusterio/api")
local stations_api = require("modules/clusterio_trains/stations")
local zones_api = require("modules/clusterio_trains/zones")
local serialize = require("modules/clusterio/serialize")


local trains_api = {
    events = {}
}

local function other_rail_direction(direction)
    if direction == defines.rail_direction.front
    then
        return defines.rail_direction.back
    elseif direction == defines.rail_direction.back
    then
        return defines.rail_direction.front
    else
        error('Unknown rail direction')
    end
end

local opposite_direction = {}
local direction_pairs = {
    {defines.direction.north, defines.direction.south},
    {defines.direction.northeast, defines.direction.southwest},
    {defines.direction.east, defines.direction.west},
    {defines.direction.southeast, defines.direction.northwest}
}

for _, p in pairs(direction_pairs) do
    opposite_direction[p[1]] = p[2]
    opposite_direction[p[2]] = p[1]
end

local function effective_rail_direction(rail_direction, entity_direction)
    if rail_direction == defines.rail_direction.front then
        return entity_direction
    else
        return opposite_direction[entity_direction]
    end
end

-- Init --
----------
trains_api.init = function ()
    global.clusterio_trains.clearence_queue = {}
end

-- Helpers --
-------------

local function is_train_stopped_forwards(train)
    -- Obtain train arrival direction relative to the LuaTrain direction
    if not train.valid or train.station == nil then return nil end
    local station = train.station
    local station_rail = station.connected_rail
    if not station_rail then return end
    -- Train does not end up on the station rail but 1 rail before it
    local station_rail_dir = station.connected_rail_direction
    local front_rail = train.front_rail
    local back_rail = train.back_rail

    for _, connect_dir in ipairs({defines.rail_connection_direction.straight,
        defines.rail_connection_direction.left, defines.rail_connection_direction.right}) do
        local et, _, _ = station_rail.get_connected_rail{
            rail_direction = 1 - station_rail_dir,
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
    log({'', 'Failed to determine train direction'})
    return true -- Guess the most likely option
end

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


local function spawn_train(stop, strain)
    -- TODO xpcall
    local carriage_positions = {}
    local linear_position = 0
    for idx, ctype in ipairs(strain.t) do
        local proto = game.entity_prototypes[ctype]
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

-- Teleporting --
-----------------

local function request_clearence (train, link)
    if not train.valid then return end
    game.print({'', 'Requesting clearence for train ', train.id})
    global.clusterio_trains.clearence_queue[train.id] = {
        train = train,
        link = link
    }
    clusterio_api.send_json('clustorio_trains_clearence', {
        length = 1,
        id = train.id,
        instanceId = link.instanceId,
        targetZone = link.zoneName
    })
end

trains_api.on_clearence = function (event_data)
    local event = game.json_to_table(event_data)
    local trainId = event.id
    local result = event.result
    local queue = global.clusterio_trains.clearence_queue[trainId]
    if not queue then
        game.print({'', 'Train ', trainId, ' was not queued'})
        return
    end
    if result ~= 'Ready' then
        game.print({'', 'Train ', trainId, ' got negative clearence request'})
        -- TODO: Need to somehow rerequest
        return
    end
    local train = queue.train
    local link = queue.link
    if not train.valid or train.manual_mode or train.station == nil or not train.station.valid then
        return
    end
    -- Start actual teleport
    local strain = serialize_train(train)
    clusterio_api.send_json("clusterio_trains_teleport", {
        instanceId = link.instanceId,
        targetZone = link.zoneName,
        train = strain
    })
    destroy_train(train)
end

trains_api.on_teleport_receive = function (event_data)
    local event = game.json_to_table(event_data)
    local zone_name = event.zone
    local strain = event.train
    local target_train_stop = stations_api.find_station_in_zone(zone_name)
    if target_train_stop == nil then return end
    local new_train_carriages = spawn_train(target_train_stop, strain)
    if new_train_carriages ~= nil then
        deserialize_train(new_train_carriages, strain)
        local train = new_train_carriages[1].train
        if train.schedule then
            train.go_to_station(train.schedule.current)
        end
    end
end

-- Events --
------------

trains_api.events[defines.events.on_train_changed_state] = function (event)
    local entity = event.train
    if not entity.valid then return end
    local old_state = event.old_state
    local new_state = entity.state
    local station = entity.station
    if station == nil then
        -- game.print({'', 'Not at a station'})
    elseif new_state == defines.train_state.wait_station then
        -- Waiting at a station
        local zone_name = stations_api.lookup_station_zone(station)
        if zone_name == nil then
            -- game.print({'', 'Not stopped in a zone'})
            return
        end
        local zone = zones_api.lookup_zone(zone_name)
        if zone == nil or zone.link == nil then
            -- game.print({'', 'Unlinked, disabled or invalid zone'})
            return
        end
        local link = zone.link
        local instanceName = global.clusterio_trains.instances[link.instanceId].name

        game.print({'', 'Stopped at a station in zone ', zone_name, ' target teleport ',
            instanceName, ':', link.zoneName })
        request_clearence(entity, link)
        -- local serialized = serialize_train(entity)
        -- local target_zone_name = link.zoneName
        -- clusterio_api.send_json('clustorio_trains_clearence', {
        --     length = 1,
        --     id = 1,
        --     instanceId = link.instanceId,
        --     targetZone = target_zone_name
        -- })
        -- -- game.print({'', game.table_to_json(serialize_train(entity))})

        -- -- Try and spawn
        -- local target_train_stop = stations_api.find_station_in_zone(target_zone_name)
        -- if (target_train_stop == nil) then return end
        -- local new_train_carriages = spawn_train(target_train_stop, serialized)
        -- if new_train_carriages ~= nil then
        --     deserialize_train(new_train_carriages, serialized)
        --     train = new_train_carriages[1].train
        --     if train.schedule then
        --         train.go_to_station(train.schedule.current)
        --     end
        --     destroy_train(entity)
        -- end

    else
        -- Nothing to do
        -- game.print({'', 'Wrong state'})
    end
end

return trains_api
