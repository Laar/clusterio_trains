local clusterio_api = require("modules/clusterio/api")
local instance_api = require("modules/clusterio_trains/instances")
local stations_api = require("modules/clusterio_trains/stations")
local zones_api = require("modules/clusterio_trains/zones")
local serialize = require("modules/clusterio_trains/train_serialize")
local user_feedback = require("modules/clusterio_trains/user_feedback")

-- CONSTANTS

-- How many ticks between checking for work
TELEPORT_WORK_INTERVAL = 15

-- How many ticks between two subsequent attempts at teleporting a train
TELEPORT_COOLDOWN_TICKS = 120
--


local trains_api = {
    events = {},
    on_nth_tick = {},
    rcon = {},
}

-- Types --
-----------

---@class ClearenceEntry
---@field train LuaTrain
---@field tick integer
---@field zone zone_name

---@class ClearenceResponse
---@field id integer
---@field result string

---@class SpawnEntry
---@field zone_name zone_name
---@field strain SerializedTrain
---@field tick integer
---@field station string

-- Globals --
-------------

---@type {[integer]: ClearenceEntry}
local clearence_queue
---@type [SpawnEntry]
local spawn_queue

-- Init --
----------

trains_api.init = function ()
    --- Whether teleportation is active
    global.clusterio_trains.teleports_active = false
    --- Queue of all trains stopped at a registered trainstop
    global.clusterio_trains.clearence_queue = {}
    if not global.clusterio_trains.spawn_queue then
        global.clusterio_trains.spawn_queue = {}
    end
    trains_api.on_load()
end

function trains_api.on_load()
    clearence_queue = global.clusterio_trains.clearence_queue
    spawn_queue = global.clusterio_trains.spawn_queue
end

-- Teleporting --
-----------------

---@param strain SerializedTrain
---@param surface string Name of the surface of the strain stop
---@param zone_name zone_name
---@param station string Station where to create the train
---@return boolean # Whether succesful
---@nodiscard
local function create_train(strain, surface, zone_name, station)
    -- Tries to create a serialized train in a given zone
    -- returns a success boolean
    local length = serialize.linear_train_position(strain.t)
    local stations = stations_api.find_stations({zone=zone_name,ingress=true,length=length, name=station})
    local new_train_carriages = {}
    for _, station in pairs(stations) do
        local target_train_stop = station.entity
        local success = xpcall(function ()
            serialize.spawn_train(target_train_stop, surface, strain, new_train_carriages)
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
        if success then
            return true
        end
    end
    return false
end

---Finds the next station name in the schedule
---@param train LuaTrain
local function target_station(train)
    local schedule = train.schedule
    if not schedule then return end
    local next_record = schedule.records[(schedule.current% #schedule.records) + 1]
    return next_record.station
end

---@param train LuaTrain
---@param registration StationRegistration
local function send_clearence_request(train, registration)
    -- Request clearence for a LuaTrain, assumes that train_teleport_valid
    local length = serialize.linear_train_position(train)
    local zone_name = registration.zone
    local zone = zones_api.lookup_zone(zone_name)
    local link = zone and zone.link

    clearence_queue[train.id] = {
        train = train,
        zone = zone_name,
        tick = game.tick
    }
    if not global.clusterio_trains.teleports_active then
        return
    end
    if not link then
        -- Do we want to give userfeedback?
        return
    end

    local instance = instance_api.get_instance(link.instanceId)
    if (instance ~= nil and instance.available) then
        clusterio_api.send_json('clustorio_trains_clearence', {
            length = length,
            id = train.id,
            instanceId = link.instanceId,
            targetZone = link.zoneName,
            -- TODO: The case where the next part is not a station
            targetStation = target_station(train) or ""
        })
    else
        -- TODO: This should not go via json (or rcon)
        trains_api.rcon.on_clearence(game.table_to_json({
            id = train.id,
            result = "Offline"
        }))
    end
end

trains_api.on_nth_tick[TELEPORT_WORK_INTERVAL] = function ()
    for trainId, request in pairs(clearence_queue) do
        if game.tick - request.tick >= TELEPORT_COOLDOWN_TICKS then
            clearence_queue[trainId] = nil
            local train = request.train
            if not train.valid or train.manual_mode or not train.station or not train.station.valid then
                -- Train became invalid or stop disappeared
                -- Manual mode should have also been caught by the train state change
                goto continue
            end
            ---@type LuaEntity_TrainStop
            ---@diagnostic disable-next-line: assign-type-mismatch
            local station = train.station
            local registration = stations_api.lookup_station(station)
            if not registration then
                -- Zone disappeared
                goto continue
            end
            send_clearence_request(train, registration)
        end
        ::continue::
    end
    local updated_spawn_queue = {}
    for _, pending in ipairs(spawn_queue) do
        local strain = pending.strain
        local zone_name = pending.zone_name
        local station_name = pending.station
        if game.tick - pending.tick > TELEPORT_COOLDOWN_TICKS
        then
            local zone = zones_api.lookup_zone(zone_name)
            if zone ~= nil and create_train(strain, zone.region.surface, zone_name, station_name)
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
    spawn_queue = global.clusterio_trains.spawn_queue
end

trains_api.rcon.request_clearence = function (event_data)
    ---@type { length: integer, id: integer, zone: string, station: string}
    ---@diagnostic disable-next-line: assign-type-mismatch
    local event = game.json_to_table(event_data)
    local id = event.id
    local zone_name = event.zone
    local length = event.length
    local target_station = event.station

    local zone = zones_api.lookup_zone(zone_name)
    local response =(function ()
        if zone == nil then
            return {result = "NoZone"}
        end
        local matches, too_long, no_ingress, no_target = table.unpack(stations_api.find_best_stations({
            {ingress = true},
            {length = length},
            {name = target_station},
            {zone = zone_name}
        }))

        if #matches > 0 then
            -- Suitable stations exist, but are they available?
            for _, station in pairs(matches) do
                local ent = station.entity
                local rail = ent.connected_rail
                if rail ~= nil and rail.trains_in_block == 0 then
                    return {result = "Ready"}
                end
            end
            return {result = "Full"}
        elseif #too_long > 0 then
            return {result = "TooLong"}
        elseif #no_ingress > 0 then
            return {result = "NoIngress"}
        elseif #no_target > 0 then
            return { result = "NoSuchStation" }
        else
            return {result = "NoStations"}
        end
    end)()
    response.id = id

    local jsonresponse = game.table_to_json(response)
    -- game.print({'', 'Responding with: ', jsonresponse})
    rcon.print(jsonresponse)
end

trains_api.rcon.on_clearence = function (event_data)
    ---@type ClearenceResponse
    ---@diagnostic disable-next-line: assign-type-mismatch
    local event = game.json_to_table(event_data)
    local trainId = event.id
    local result = event.result
    local queue = global.clusterio_trains.clearence_queue[trainId]
    local source_zone = queue.zone
    local zone = zones_api.lookup_zone(source_zone)
    if not queue then
        -- Train departed or removed from the queue
        return
    end
    local train = queue.train
    if not train.valid then
        clearence_queue[trainId] = nil
        -- TODO: Better handling -> deconstruction of the train should be detected
        log('Train disappeared during clearence')
        return
    end
    if zone == nil then
        -- TODO: Better handling -> zone updates should trigger checking the queue
        clearence_queue[trainId] = nil
        log('Zone disappeared during clearence')
        return
    end
    if not global.clusterio_trains.teleports_active then
        -- Teleporting disabled
        return
    end
    local target_station = target_station(train)
    if not target_station then return end
    if result ~= 'Ready' then
        user_feedback.show_train_clearence_feedback(queue.train, event)
        return
    end
    local link = zone and zone.link
    if link == nil then
        -- TODO: Proper handling
        log('Link disappeared during clearence request')
        return
    end
    -- TODO: Better handling of the case that the station disappears
    if train.manual_mode or train.station == nil or not train.station.valid then
        return
    end
    -- Start actual teleport
    local strain = serialize.serialize_train(train)
    clusterio_api.send_json("clusterio_trains_teleport", {
        instanceId = link.instanceId,
        targetZone = link.zoneName,
        train = strain,
        station = target_station
    })
    clearence_queue[trainId] = nil
    for _, e in ipairs(train.carriages) do
        e.destroy()
    end
end

trains_api.rcon.on_teleport_receive = function (event_data)
    ---@type {zone: zone_name, train: SerializedTrain, station: string}
    ---@diagnostic disable-next-line: assign-type-mismatch
    local event = game.json_to_table(event_data)
    local strain = event.train
    local zone_name = event.zone
    local station = event.station
    local zone = zones_api.lookup_zone(event.zone)
    -- Always insert,  just to be safe
    table.insert(spawn_queue, {
        zone_name = zone_name,
        strain = strain,
        tick = game.tick,
        station = station
    })
    if zone == nil then
        game.print({'', 'Warning received train for unknown zone ', zone_name})
        return
    end
    if create_train(strain, zone.region.surface, zone_name, station) then
        spawn_queue[#spawn_queue] = nil
    end
end

-- Events --
------------

--- Handle train changing
---@param event EventData.on_train_changed_state:EventData
trains_api.events[defines.events.on_train_changed_state] = function (event)
    local train = event.train
    if not train.valid then return end
    -- Remove any previous clearence requests, done on any event to prevent
    -- previous requests from hanging around
    clearence_queue[train.id] = nil
    local new_state = train.state
    local station = train.station
    ---@cast station LuaEntity_TrainStop?
    if station == nil then
        -- game.print({'', 'Not at a station'})
    elseif new_state == defines.train_state.wait_station then
        -- Waiting at a station
        local registration = stations_api.lookup_station(station)
        if registration == nil or not registration.egress then
            return
        end
        send_clearence_request(train, registration)
    else
        -- Nothing to do
        -- game.print({'', 'Wrong state'})
    end
end

return trains_api
