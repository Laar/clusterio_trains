local clusterio_api = require("modules/clusterio/api")
local zones_api = require("modules/clusterio_trains/zones")

local stations_api = {
}

-- Reload --
------------

local function create_registration(station, zone_name)
    local crail = station.connected_rail
    local rail_dir = station.connected_rail_direction
    local length = crail.get_rail_segment_length()

    -- Backside of the station is connected to a longer rail
    local segment_end, segment_out_dir = crail.get_rail_segment_end(1 - rail_dir)
    local egress = false
    for _, connection_dir in ipairs({defines.rail_connection_direction.left,
        defines.rail_connection_direction.straight,
        defines.rail_connection_direction.right}) do
            local next_rail = segment_end.get_connected_rail{rail_direction=segment_out_dir, rail_connection_direction=connection_dir}
            if next_rail ~= nil then
                egress = true
            end
    end
    -- front side of the station is connected to a longer rail
    segment_end, segment_out_dir = crail.get_rail_segment_end(rail_dir)
    local ingress = false
    for _, connection_dir in ipairs({defines.rail_connection_direction.left,
        defines.rail_connection_direction.straight,
        defines.rail_connection_direction.right}) do
            local next_rail = segment_end.get_connected_rail{rail_direction=segment_out_dir, rail_connection_direction=connection_dir}
            if next_rail ~= nil then
                ingress = true
            end
    end
    -- 
    game.print({'', 'Registration ', station.backer_name, ' in zone ', zone_name, ' length ', length, ' ingress ', ingress, ' egress ', egress})
    return {
        zone = zone_name,
        entity = station,
        length = length,
        egress = egress,
        ingress = ingress
    }
end

local function rebuild_station_mapping()
    global.clusterio_trains.stations = {}
    local stations = global.clusterio_trains.stations
    local found_stations = 0
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{type='train-stop'}) do
            local zone_name = zones_api.find_zone(entity.surface, entity.position)
            if zone_name then
                found_stations = found_stations + 1
                stations[entity.unit_number] = create_registration(entity, zone_name)
            end
        end
    end
    game.print({'', 'Found ', found_stations, ' stations'})
end

-- Init --
----------

function stations_api.init()
    -- Uses save-specific numbers -> needs updating on reload
    global.clusterio_trains.stations = {}
    rebuild_station_mapping()
end

-- Interface --
---------------
function stations_api.lookup_station_zone(entity)
    local registration = global.clusterio_trains.stations[entity.unit_number]
    if registration then
        return registration.zone
    else
        return nil
    end
end

function stations_api.find_station_in_zone(zone_name)
    for _, registration in pairs(global.clusterio_trains.stations) do
        if (registration.zone == zone_name) then
            return registration.entity
        end
    end
    return nil
end

-- Handlers --
--------------
local function on_built(entity)
    local zone_name = zones_api.find_zone(entity.surface, entity.position)
    if zone_name
    then
        global.clusterio_trains.stations[entity.unit_number] = create_registration(entity, zone_name)
        game.print({'', 'Trainstop built inside zone ', zone_name})
    else
        game.print({'', 'Trainstop built outside zone'})
    end
end

local function on_remove(entity)
    global.clusterio_trains.stations[entity.unit_number] = nil
    game.print({'', 'Trainstop removed'})
end

local function on_rename(entity)
    game.print({'', 'Trainstop renamed'})
end

-- Events --
------------

-- Helpers
local function check_entity(entity)
    return entity and entity.valid and entity.type == 'train-stop'
    -- TODO: Check for ghosts?
end


-- Script teleport?
stations_api.events = {}

-- Player
stations_api.events[defines.events.on_built_entity] = function (event)
    if not event then return end
    local entity = event.created_entity
    if check_entity(entity) then
        on_built(entity)
    end
end

stations_api.events[defines.events.on_player_mined_entity] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        on_remove(entity)
    end
end

-- Robot
stations_api.events[defines.events.on_robot_built_entity] = function(event)
    if not event then return end
    local entity = event.created_entity
    if check_entity(entity) then
        on_built(entity)
    end
end
stations_api.events[defines.events.on_robot_mined_entity] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        on_remove(entity)
    end
end

-- Script
stations_api.events[defines.events.script_raised_built] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        on_built(entity)
    end
end

stations_api.events[defines.events.script_raised_destroy] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        on_remove(entity)
    end
end

-- General
stations_api.events[defines.events.on_entity_renamed] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        on_rename(entity)
    end
end

stations_api.events[defines.events.on_entity_died] = function (event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        on_remove(entity)
    end
end

return stations_api
