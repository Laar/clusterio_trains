local clusterio_api = require("modules/clusterio/api")
local stations_api = require("modules/clusterio_trains/stations")
local zones_api = require("modules/clusterio_trains/zones")
local serialize = require("modules/clusterio_trains/train_serialize")

-- CONSTANTS

-- How many ticks between checking for work
TELEPORT_WORK_INTERVAL = 15

-- How many ticks between two subsequent attempts at teleporting a train
TELEPORT_COOLDOWN_TICKS = 120
--


local trains_api = {
    events = {},
    on_nth_tick = {}
}

-- Init --
----------

trains_api.init = function ()
    global.clusterio_trains.clearence_queue = {}
    global.clusterio_trains.spawn_queue = {}
end

-- Helpers --
-------------

local function destroy_train(train)
    for _, carriage in ipairs(train.carriages) do
        -- TODO: raise_destroy?
        carriage.destroy{}
    end
end

-- Teleporting --
-----------------

local function train_teleport_valid(train)
    -- Is this a valid train for teleporting
    if not train.valid or train.manual_mode or train.station == nil or not train.station.valid
    then
        return false
    end
    -- TODO: More indepth checks on the station, e.g. whether in a zone
    return true
end

local function create_train(strain, zone_name)
    -- Tries to create a serialized train in a given zone
    -- returns a success boolean
    local target_train_stop = stations_api.find_station_in_zone(zone_name)
    if target_train_stop == nil
    then
        return false
    end
    local new_train_carriages = {}
    return xpcall(function ()
        serialize.spawn_train(target_train_stop, strain, new_train_carriages)
        if #new_train_carriages ~= #strain.t then
            error("Incorrect number of entities")
        end
        serialize.deserialize_train(new_train_carriages, strain)
        local train = new_train_carriages[1].train
        if train.schedule then
            train.go_to_station(train.schedule.current)
        end
    end, function (error_msg)
        log(error_msg)
        for _, e in ipairs(new_train_carriages) do
            e.destroy()
        end
    end)
end

local function request_clearence (train, link)
    -- Request clearence for a LuaTrain, assumes that train_teleport_valid
    game.print({'', 'Requesting clearence for train ', train.id})
    local length = serialize.linear_train_position(train)
    global.clusterio_trains.clearence_queue[train.id] = {
        train = train,
        link = link,
        tick = game.tick
    }
    clusterio_api.send_json('clustorio_trains_clearence', {
        length = length,
        id = train.id,
        instanceId = link.instanceId,
        targetZone = link.zoneName
    })
end

trains_api.on_nth_tick[TELEPORT_WORK_INTERVAL] = function ()
    for trainId, request in ipairs(global.clusterio_trains.clearence_queue) do
        if game.tick - request.tick >= TELEPORT_COOLDOWN_TICKS then
            if not train_teleport_valid(request.train) then
                -- Not valid for teleporting any more
                global.clusterio_trains.clearence_queue[trainId] = nil
            else
                -- Will implicitly update the request
                request_clearence(request.train, request.link)
            end
        end
    end
    local updated_spawn_queue = {}
    for _, pending in ipairs(global.clusterio_trains.spawn_queue) do
        local strain = pending.strain
        local zone_name = pending.zone_name
        if game.tick - pending.tick > TELEPORT_COOLDOWN_TICKS
        then
            if create_train(strain, zone_name)
            then
                -- Nothing to do, will remove it from the queue
            else
                table.insert(updated_spawn_queue, {
                    zone_name = zone_name,
                    strain = strain,
                    tick = game.tick
                })
            end
        else
            table.insert(updated_spawn_queue, pending)
        end
    end
    global.clusterio_trains.spawn_queue = updated_spawn_queue
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
    local strain = serialize.serialize_train(train)
    clusterio_api.send_json("clusterio_trains_teleport", {
        instanceId = link.instanceId,
        targetZone = link.zoneName,
        train = strain
    })
    global.clusterio_trains.clearence_queue[trainId] = nil
    destroy_train(train)
end

trains_api.on_teleport_receive = function (event_data)
    local event = game.json_to_table(event_data)
    local zone_name = event.zone
    local strain = event.train
    if not create_train(strain, zone_name) then
        table.insert(global.clusterio_trains.spawn_queue, {
            zone_name = zone_name,
            strain = strain,
            tick = game.tick
        })
    end
end

-- Events --
------------

trains_api.events[defines.events.on_train_changed_state] = function (event)
    local train = event.train
    if not train.valid then return end
    -- Remove any previous clearence requests, done on any event to prevent
    -- previous requests from hanging around
    global.clusterio_trains.clearence_queue[train.id] = nil
    local new_state = train.state
    local station = train.station
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
        request_clearence(train, link)
    else
        -- Nothing to do
        -- game.print({'', 'Wrong state'})
    end
end

return trains_api
