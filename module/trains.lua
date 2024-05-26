local clusterio_api = require("modules/clusterio/api")
local stations_api = require("modules/clusterio_trains/stations")
local zones_api = require("modules/clusterio_trains/zones")
local serialize = require("modules/clusterio_trains/train_serialize")

local trains_api = {
    events = {}
}

-- Init --
----------
trains_api.init = function ()
    global.clusterio_trains.clearence_queue = {}
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

local function request_clearence (train, link)
    if not train.valid then return end
    game.print({'', 'Requesting clearence for train ', train.id})
    local length = serialize.linear_train_position(train)
    global.clusterio_trains.clearence_queue[train.id] = {
        train = train,
        link = link
    }
    clusterio_api.send_json('clustorio_trains_clearence', {
        length = length,
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
    local target_train_stop = stations_api.find_station_in_zone(zone_name)
    if target_train_stop == nil then return end
    local new_train_carriages = serialize.spawn_train(target_train_stop, strain)
    if new_train_carriages ~= nil then
        serialize.deserialize_train(new_train_carriages, strain)
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
    else
        -- Nothing to do
        -- game.print({'', 'Wrong state'})
    end
end

return trains_api
