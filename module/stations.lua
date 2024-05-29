local clusterio_api = require("modules/clusterio/api")
local zones_api = require("modules/clusterio_trains/zones")

local stations_api = {
}

---@class StationRegistration
---@field zone zone_name Name of the zone
---@field entity LuaEntity_TrainStop The train stop entity
---@field length number Size of the track associated with the train stop
---@field egress boolean Whether to use it as an egress from this server
---@field ingress boolean Whether to use it as an ingress to this server

-- Override of LuaEntity when it is a TrainStop
--- @class LuaEntity_TrainStop: LuaEntity
--- @field unit_number integer
--- @field backer_name string


local connection_directions = {
    defines.rail_connection_direction.left,
    defines.rail_connection_direction.straight,
    defines.rail_connection_direction.right
}

local invalidation_types = {
    ["rail-signal"] = true,
    ["rail-chain-signal"] = true,
    ["straight-rail"] = true,
    ["curved-rail"] = true
}

---Create a staiton registration
---@param station LuaEntity_TrainStop
---@param zone_name zone_name
---@return StationRegistration
local function create_registration(station, zone_name)
    local crail = station.connected_rail
    local rail_dir = station.connected_rail_direction
    local length = 0
    local ingress = false
    local egress = false
    if crail ~= nil
    then
        length = crail.get_rail_segment_length()

        -- Backside of the station is connected to a longer rail
        local segment_end, segment_out_dir = crail.get_rail_segment_end(1 - rail_dir)
        egress = false
        for _, connection_dir in ipairs(connection_directions) do
                local next_rail = segment_end.get_connected_rail{rail_direction=segment_out_dir, rail_connection_direction=connection_dir}
                if next_rail ~= nil then
                    egress = true
                end
        end
        -- front side of the station is connected to a longer rail
        segment_end, segment_out_dir = crail.get_rail_segment_end(rail_dir)
        ingress = false
        for _, connection_dir in ipairs(connection_directions) do
            local next_rail = segment_end.get_connected_rail{rail_direction=segment_out_dir, rail_connection_direction=connection_dir}
            if next_rail ~= nil then
                ingress = true
            end
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

-- Reload --
------------

local function rebuild_station_mapping()
    ---@type {[integer]: StationRegistration}
    global.clusterio_trains.stations = {}
    local stations = global.clusterio_trains.stations
    local found_stations = 0
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{type='train-stop'}) do
            ---@cast entity LuaEntity_TrainStop
            local zone_name = zones_api.find_zone(entity.surface, entity.position)
            if zone_name then
                found_stations = found_stations + 1
                stations[entity.unit_number] = create_registration(entity, zone_name)
            end
        end
    end
    global.clusterio_trains.station_invalid = false
    game.print({'', 'Found ', found_stations, ' stations'})
end

local function ensure_valid_stations()
    if not global.clusterio_trains.station_invalid then return end
    local stations = global.clusterio_trains.stations
    for key, registration in pairs(stations) do
        stations[key] = create_registration(registration.entity, registration.zone)
    end
    global.clusterio_trains.station_invalid = false
end

-- Init --
----------

function stations_api.init()
    -- Uses save-specific numbers -> needs updating on reload
    global.clusterio_trains.stations = {}
    global.clusterio_trains.station_invalid = true
    rebuild_station_mapping()
end

-- Interface --
---------------
---Lookup zone corresponding to a station
---@param entity LuaEntity_TrainStop
---@return zone_name?
function stations_api.lookup_station_zone(entity)
    ensure_valid_stations()
    local registration = global.clusterio_trains.stations[entity.unit_number]
    if registration then
        return registration.zone
    else
        return nil
    end
end

--- Lookup a station in a specific zone
--- @param zone_name zone_name
--- @return LuaEntity_TrainStop?
function stations_api.find_station_in_zone(zone_name)
    ensure_valid_stations()
    for _, registration in pairs(global.clusterio_trains.stations) do
        if (registration.zone == zone_name) then
            return registration.entity
        end
    end
    return nil
end

-- Handlers --
--------------
---@param entity LuaEntity_TrainStop
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

---@param entity LuaEntity_TrainStop
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
--- @param entity LuaEntity
--- @return boolean
local function check_entity(entity)
    return entity and entity.valid and entity.type == 'train-stop'
    -- TODO: Check for ghosts?
end


-- Script teleport?
stations_api.events = {}

-- Player

---@param event EventData.on_built_entity
stations_api.events[defines.events.on_built_entity] = function (event)
    if not event then return end
    local entity = event.created_entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_built(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end

---@param event EventData.on_player_mined_entity
stations_api.events[defines.events.on_player_mined_entity] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end

-- Robot
---@param event EventData.on_robot_built_entity
stations_api.events[defines.events.on_robot_built_entity] = function(event)
    if not event then return end
    local entity = event.created_entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_built(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end
---@param event EventData.on_robot_mined_entity
stations_api.events[defines.events.on_robot_mined_entity] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end

-- Script
---@param event EventData.script_raised_built
stations_api.events[defines.events.script_raised_built] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_built(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end

---@param event EventData.script_raised_destroy
stations_api.events[defines.events.script_raised_destroy] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end

-- General
---@param event EventData.on_entity_renamed
stations_api.events[defines.events.on_entity_renamed] = function(event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_rename(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end

---@param event EventData.on_entity_died
stations_api.events[defines.events.on_entity_died] = function (event)
    if not event then return end
    local entity = event.entity
    if check_entity(entity) then
        ---@cast entity LuaEntity_TrainStop
        on_remove(entity)
    elseif invalidation_types[entity.type] then
        global.clusterio_trains.station_invalid = true
    end
end

return stations_api
