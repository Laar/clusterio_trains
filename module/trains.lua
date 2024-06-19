local ipc = require("modules/clusterio_trains/types/ipc")
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
}

-- Types --
-----------

---@class ClearenceEntry
---@field train LuaTrain
---@field tick integer
---@field zone ZoneName

--- @alias DepartureState "requested" | "prepared" | "sent" | "rejected"

--- @class Departure Teleport in progress or rejected
--- @field teleport PreparedTeleport
--- @field state DepartureState
--- @field tick integer Last attempt at teleporting

--- @class PreparedTeleport
--- @field trainId integer Global train id
--- @field dst ZoneInstance
--- @field src {zone: ZoneName}
--- @field train SerializedTrain
--- @field station string
--- @field tick integer When was this train desconstructed
--- @field length integer

--- @class SpawnEntry
--- @field teleport ReceivedTeleport
--- @field tick integer Last attempt at spawning

--- @class ReceivedTeleport
--- @field trainId integer Global train id
--- @field dst ZoneInstance
--- @field src {zone: ZoneName}
--- @field train SerializedTrain
--- @field station string

-- Globals --
-------------

---@type {[integer]: ClearenceEntry}
local clearence_queue
---@type [SpawnEntry]
local spawn_queue
---@type{[integer]: integer} Mapping of train id to global train id
local registered_trains
--- @type{ [integer]: Departure } Mapping of global train id to Departure
local departing_teleport

--- @type fun(registration: StationRegistration) => nil
local check_station

--- @type fun(event: OnClearenceRCON)
local on_clearence

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
    if not global.clusterio_trains.registered_trains then
        global.clusterio_trains.registered_trains = {}
    end
    if not global.clusterio_trains.departing_teleport then
        global.clusterio_trains.departing_teleport = {}
    end
    --- @type [StationRegistration] | "everything" | nil
    global.clusterio_trains.train_rescan = "everything"
    trains_api.on_load()
end

function trains_api.on_load()
    clearence_queue = global.clusterio_trains.clearence_queue
    spawn_queue = global.clusterio_trains.spawn_queue
    registered_trains = global.clusterio_trains.registered_trains
    departing_teleport = global.clusterio_trains.departing_teleport
end

-- Teleporting --
-----------------

--- @param teleport ReceivedTeleport
--- @return LuaTrain? # Created train when succesful
--- @nodiscard
local function create_train(teleport)
    local strain = teleport.train
    local zone_name = teleport.dst.zone
    local station_name = teleport.station
    local global_train_id = teleport.trainId
    -- Tries to create a serialized train in a given zone
    -- returns a success boolean
    local length = serialize.linear_train_position(strain.t)
    local stations = stations_api.find_stations({zone=zone_name,ingress=true,length=length, name=station_name})
    --- @type LuaEntity_RollingStock[]
    local new_train_carriages = {}
    --- @type LuaTrain?
    local result_train = nil
    for _, station in pairs(stations) do
        local target_train_stop = station.entity
        local success = xpcall(function ()
            serialize.spawn_train(target_train_stop, strain, new_train_carriages)
            if #new_train_carriages ~= #strain.t then
                error("Incorrect number of entities")
            end
            serialize.deserialize_train(new_train_carriages, strain)
            result_train = new_train_carriages[1].train
            if result_train.schedule then
                result_train.go_to_station(result_train.schedule.current)
            end
            registered_trains[result_train.id] = global_train_id
        end, function (error_msg)
            log(error_msg)
            for _, e in ipairs(new_train_carriages) do
                e.destroy()
            end
        end)
        if success then
            return result_train
        end
    end
    return nil
end

---Finds the next station name in the schedule
---@param train LuaTrain
local function target_station(train)
    local schedule = train.schedule
    if not schedule then return end
    local next_record = schedule.records[(schedule.current% #schedule.records) + 1]
    return next_record.station
end

local request_train_id_ipc = ipc.register_json_ipc("clusterio_trains_trainid", "TrainIdIPC")

---@param train LuaTrain
local function request_train_id(train)
    if not train or not train.valid then return end
    request_train_id_ipc({ref = train.id, tick = game.tick, trainLId = train.id})
end

ipc.register_rcon("on_train_id", "OnTrainIdRCON", function (event)
    local train = game.get_train_by_id(event.ref)
    if not train or not train.valid then return end
    registered_trains[event.ref] = event.id
end)

local clearence_ipc = ipc.register_json_ipc("clustorio_trains_clearence", "ClearenceIPC")

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
    local gtrainid = registered_trains[train.id]
    if not gtrainid then
        -- Unregistered train
        request_train_id(train)
        return
    end

    local instance = instance_api.get_instance(link.instanceId)
    if (instance ~= nil and instance.status == "available") then
        clearence_ipc({
            length = length,
            id = train.id,
            dst = {
                instance = link.instanceId,
                zone = link.zoneName,
            },
            -- TODO: The case where the next part is not a station
            targetStation = target_station(train) or ""
        })
    else
        game.print("Instance offline")
        -- TODO: This should not go via json (or rcon)
        on_clearence({
            id = train.id,
            result = "Offline"
        })
    end
end

--- @param deparature Departure
local function send_departure_clearence_request(deparature)
    local instance = instance_api.get_instance(deparature.teleport.dst.instance)
    if instance == nil or instance.status ~= "available" then
        -- TODO: Better handling of instance == nil
        deparature.tick = game.tick
        return
    end
    clearence_ipc({
        length = deparature.teleport.length,
        id = deparature.teleport.trainId,
        dst = deparature.teleport.dst,
        targetStation = deparature.teleport.station
    })
    deparature.tick = game.tick
    deparature.state = "requested"
end

trains_api.on_nth_tick[TELEPORT_WORK_INTERVAL] = function ()
    -- Rescan
    local rescan = global.clusterio_trains.train_rescan
    if rescan ~= nil then
        if rescan == 'everything' then
            for _, registration in pairs(stations_api.find_stations{}) do
                check_station(registration)
            end
        else
            --- @cast rescan StationRegistration[]
            for _, registration in pairs(rescan) do
                check_station(rescan)
            end
        end
        global.clusterio_trains.train_rescan = nil
    end
    if global.clusterio_trains.teleports_active then
        for _, departure in pairs(departing_teleport) do
            if departure.state =="requested" or departure.state == "sent" then
                goto continue
            end
            if departure.tick - game.tick < TELEPORT_COOLDOWN_TICKS then goto continue end
            send_departure_clearence_request(departure)
            ::continue::
        end
    end

    -- Resend requests
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
    -- Spawn
    --- @type SpawnEntry[]
    local updated_spawn_queue = {}
    for _, pending in ipairs(spawn_queue) do
        if game.tick - pending.tick > TELEPORT_COOLDOWN_TICKS
        then
            if create_train(pending.teleport)
            then
                -- Nothing to do, will remove it from the queue
            else
                --- @type SpawnEntry
                local updatedEntry = {
                    teleport = pending.teleport,
                    tick = game.tick
                }
                updated_spawn_queue[#updated_spawn_queue+1] = updatedEntry
            end
        else
            updated_spawn_queue[#updated_spawn_queue+1] = pending
        end
    end
    global.clusterio_trains.spawn_queue = updated_spawn_queue
    spawn_queue = global.clusterio_trains.spawn_queue
end

ipc.register_rcon("request_clearence", "ClearenceRequestRCON", function (event)
    local id = event.id
    local zone_name = event.dst.zone
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
    -- TODO: Type this
    rcon.print(jsonresponse)
end)

local teleport_ipc = ipc.register_json_ipc("clusterio_trains_teleport", "TeleportIPC")


---@param train_id integer
local function send_teleport(train_id)
    local departure = departing_teleport[train_id]
    if not departure then
        log("Warning: trying to teleport non existent train")
        return
    end
    local teleport = departure.teleport
    teleport_ipc({
        trainId = teleport.trainId,
        dst = teleport.dst,
        src = { zone = teleport.src.zone },
        tick = game.tick,
        train = teleport.train,
        station = teleport.station
    })
    departure.state = "sent"
    departure.tick = game.tick
end

on_clearence = function(event)
    local trainId = event.id
    if departing_teleport[trainId] then
        send_teleport(trainId)
        return
    end

    local result = event.result
    local queue = clearence_queue[trainId]
    local global_train_id = registered_trains[trainId]
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
    if global_train_id == nil then
        -- Should not happen
        log('Warning received clearence for train without id')
        request_train_id(train)
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
    local target_station_name = target_station(train)
    if not target_station_name then return end
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
    local length = serialize.linear_train_position(train)
    clearence_queue[trainId] = nil
    for _, e in ipairs(train.carriages) do
        e.destroy()
    end
    departing_teleport[global_train_id] = {
        tick = game.tick,
        state = "prepared",
        teleport = {
            trainId = global_train_id,
            dst = {
                instance = link.instanceId,
                zone = link.zoneName
            },
            src = { zone = source_zone },
            train = strain,
            station = target_station_name,
            tick = game.tick,
            length = length
        }
    }
    send_teleport(global_train_id)
end
ipc.register_rcon("on_clearence", "OnClearenceRCON", on_clearence)

ipc.register_rcon("on_departure_received", "OnDepartureReceived", function (event)
    local departure = departing_teleport[event.trainId]
    if departure then
        if event.arrival then
            departing_teleport[event.trainId] = nil
        else
            departure.state = "rejected"
            departure.tick = game.tick
        end
    else
        log("Warning: Received departure for non registered train ".. event.trainId)
    end
end)

ipc.register_rcon("on_teleport_receive", "OnTeleportReceiveRCON", function(event)
    local global_train_id = event.trainId
    local strain = event.train
    local zone_name = event.dst.zone
    local station = event.station
    local zone = zones_api.lookup_zone(zone_name)
    -- Always insert,  just to be safe
    --- @type ReceivedTeleport
    local stored_teleport = {
        trainId = global_train_id,
        train = strain,
        dst = event.dst,
        src = {zone = ""}, -- TODO
        station = station
    }
    spawn_queue[#spawn_queue+1] = {
        teleport = stored_teleport,
        tick = game.tick
    }
    if zone == nil then
        game.print({'', 'Warning received train for unknown zone ', zone_name})
        return
    end
    local train = create_train(stored_teleport)
    if train then
        spawn_queue[#spawn_queue] = nil
    end
    --- @type TeleportReceivedRCON
    local result = {
        tick = game.tick,
        trainId = train and train.id
    }
    -- TODO: Abstract this
    rcon.print(game.table_to_json(result))
end)

---Check a station for a stopped train and put it in the teleport queue if needed
---@param registration StationRegistration
check_station = function(registration)
    local station = registration.entity
    if not station.valid or not registration.egress then return end
    local train = station.get_stopped_train()
    if not train or train.manual_mode or clearence_queue[train.id] ~= nil then return end
    send_clearence_request(train, registration)
end

-- Events --
------------
-- TODO: Delay to next work cycle

trains_api.events[stations_api.defines.on_station_data_reload] = function (event)
    global.clusterio_trains.train_rescan = "everything"
end

trains_api.events[stations_api.defines.on_station_registration_refresh] = function (event)
    --- @cast event EventData.CT.StationRegistrationRefresh
    if global.clusterio_trains.train_rescan == nil then
        global.clusterio_trains.train_rescan = event.registrations
    else
        -- TODO: Merge with previous rescan list
        global.clusterio_trains.train_rescan = "everything"
    end
end

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
