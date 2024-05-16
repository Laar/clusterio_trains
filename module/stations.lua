local clusterio_api = require("modules/clusterio/api")
local zones_api = require("modules/clusterio_trains/zones")

local stations_api = {
}

-- Reload --
------------

local function rebuild_station_mapping()
    global.clusterio_trains.stations = {}
    local stations = global.clusterio_trains.stations
    local found_stations = 0
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{type='train-stop'}) do
            local zone_name = zones_api.find_zone(entity.surface, entity.position)
            if zone_name then
                found_stations = found_stations + 1
                stations[entity.unit_number] = {
                    zone = zone_name,
                    entity = entity
                }
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
        global.clusterio_trains.stations[entity.unit_number] = {
            zone = zone_name,
            entity = entity
        }
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
