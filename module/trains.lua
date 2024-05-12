local clusterio_api = require("modules/clusterio/api")
local stations_api = require("modules/clusterio_trains/stations")
local zones_api = require("modules/clusterio_trains/zones")
local serialize = require("modules/clusterio/serialize")


local trains_api = {
    events = {}
}


-- Helpers --
-------------

local function serialize_train(train)
    local strain = {
        t = {}, -- Types
        c = {}, -- Inventory
        f = {}, -- Fluids
        g = {}, -- Grid
        b = {}, -- Burner
        s = {} -- Scheduele
    }

    for cid, carriage in ipairs(train.carriages) do
        strain.t[cid] = carriage.name
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
        -- Scheduele
        -- TODO!
    end
    return strain
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
        game.print({'', 'Not at a station'})
    elseif new_state == defines.train_state.wait_station then
        -- Waiting at a station
        local zone_name = stations_api.lookup_station_zone(station)
        if zone_name == nil then
            game.print({'', 'Not stopped in a zone'})
             return
        end
        local zone = zones_api.lookup_zone(zone_name)
        if zone == nil or zone.link == nil or not zone.enabled then
            game.print({'', 'Unlinked, disabled or invalid zone'})
            return
        end

        game.print({'', 'Stopped at a station in zone ', zone_name, ' target teleport ',
            zone.link.instance, ':', zone.link.name })
        game.print({'', game.table_to_json(serialize_train(entity))})
    else
        -- Nothing to do
        -- game.print({'', 'Wrong state'})
    end
end

return trains_api
