-- Module goal: Storage of instance related information

util = require("util")

local instanceApi = {
    rcon = {},
    defines = {},
}

--- @class GInstance
--- @field data {[InstanceId]: InstanceData} Mapping id to associated data
--- @field names {[string]: InstanceId} Mapping name to id

--- @alias InstanceStatus "unavailable" | "starting" | "available"

--- @class InstanceData
--- @field id InstanceId
--- @field status InstanceStatus
--- @field name string
--- @field stations string[]

--- @class InstanceDataPatch
--- @field id InstanceId
--- @field name string?
--- @field status InstanceStatus?
--- @field stations string[]

---@type GInstance
local ginstance

-- Event names --

--- Event raised when the station data has changed
instanceApi.defines.on_stations_changed = script.generate_event_name()
--- Event raised after an instance changed it name
instanceApi.defines.on_instance_name_changed = script.generate_event_name()
--- Event raised after an instance changed its state
instanceApi.defines.on_instance_state_changed = script.generate_event_name()
--- Even raised after all instance data has been replaced
instanceApi.defines.on_instance_data_reload = script.generate_event_name()

function instanceApi.init()
    if global.clusterio_trains.instance == nil then
        global.clusterio_trains.instance = {
            data = {},
            names = {}
        }
    end
    instanceApi.on_load()
end

function instanceApi.on_load()
    if global.clusterio_trains.instance ~= nil then
        ginstance = global.clusterio_trains.instance
    end
end

---Find instance by id or name
---@param idOrName InstanceIdOrName
---@return InstanceData? instance_data
local function get_instance_data(idOrName)
    local id
    if type(idOrName) == "string" then
        id = ginstance.names[idOrName]
    else
        id = idOrName
    end
    return id and ginstance.data[id]
end
instanceApi.get_instance = get_instance_data

---@return { [integer]: InstanceData }
function instanceApi.get_all_instances()
    return ginstance.data
end

--- Is an instance available
---@param idOrName InstanceIdOrName
---@return boolean? available
function instanceApi.available(idOrName)
    local inst = get_instance_data(idOrName)
    return inst and inst.status == "available"
end

---@param name string name of the instance
---@return InstanceId?
function instanceApi.id_by_name(name)
    return ginstance.names[name]
end

-- RCON --
----------

function instanceApi.rcon.set_instances(instance_data)
    ---@type {[integer]: InstanceData}
	---@diagnostic disable-next-line: assign-type-mismatch
	local instance_table = game.json_to_table(instance_data)
    -- Clear before aliasing and overwriting
    ginstance.data = {}
    ginstance.names = {}
    local data = ginstance.data
    local names = ginstance.names
    for _, instance in ipairs(instance_table) do
        ---@type InstanceData
        local inst = {
            id = instance.id,
            name = instance.name,
            status = instance.status,
            stations = instance.stations,
        }
        data[inst.id] = inst
        names[inst.name] = inst.id
    end
    -- TODO: Event
    script.raise_event(instanceApi.defines.on_instance_data_reload, {})
end

function instanceApi.rcon.set_instance(event_data)
    ---@type InstanceDataPatch
	---@diagnostic disable-next-line: assign-type-mismatch
	local event = game.json_to_table(event_data)
	local current = ginstance.data[event.id]
    local inst = {
        id = event.id,
        name = event.name or current.name,
        status = event.status or current.status,
        stations = event.stations or current.stations,
    }
    ginstance.data[event.id] = inst
    if current and event.name and (current.name ~= inst.name) then
        -- Rename
        ginstance.names[current.name] = nil
        ginstance.names[inst.name] = inst.id
        script.raise_event(instanceApi.defines.on_instance_name_changed,
            {id = inst.id, old = current.name, new = inst.name})
    end
    if (inst.status ~= current.status) then
        script.raise_event(instanceApi.defines.on_instance_state_changed,
        {id = inst.id, old = current.status, new = inst.status})
    end
    if (not util.table.compare(inst.stations, current.stations)) then
        script.raise_event(instanceApi.defines.on_stations_changed, {})
    end
end

return instanceApi