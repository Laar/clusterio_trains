
local clusterio_api = require("modules/clusterio/api")

-----------------
--- IPC types ---
-----------------


--- @class ClearenceIPC
--- @field length number
--- @field instanceId InstanceId
--- @field targetZone ZoneName
--- @field targetStation string

--- @class TeleportIPC
--- @field trainId number
--- @field instanceId InstanceId
--- @field targetZone ZoneName
--- @field train SerializedTrain
--- @field station string

--- @class InstanceDetailsIPC
--- @field stations? string[]

--- @class TrainIdIPC
--- @field trainId integer


------------------
--- RCON types ---
------------------

--- @alias InstanceListRCON InstanceData[]

--- @class InstanceDataPatch
--- @field id InstanceId
--- @field name string?
--- @field status InstanceStatus?
--- @field stations string[]

--- @alias AllZonesRCON {[ZoneName]: Zone}

--- @class ClearenceRequestRCON
--- @field length number
--- @field id number
--- @field zone ZoneName
--- @field station string

--- @class OnClearenceRCON
--- @field id integer
--- @field result string

--- @class OnTeleportReceiveRCON
--- @field trainId integer
--- @field instance InstanceId
--- @field zone ZoneName
--- @field train SerializedTrain
--- @field station string

--- @class OnTrainIdRCON
--- @field id number
--- @field trainId number


-----------------
--- Interface ---
-----------------

local ipc = {
    rcon_handlers = {}
}

--- @generic T
--- @param channel string
--- @param type `T`
--- @return fun(data: T): nil
function ipc.register_json_ipc(channel, type)
    return function (data)
        clusterio_api.send_json(channel, data)
    end
end

--- @generic T
--- @param type `T` Type of the IPC
--- @return fun(data: T): nil
function ipc.register_rcon_ipc(type)
    return function (data)
        rcon.print(game.table_to_json(data))
    end
end


--- @generic T
--- @param name string
--- @param type `T`
--- @param handler fun(data: T): nil
function ipc.register_rcon(name, type, handler)
    if ipc.rcon_handlers[name] then
        error("Duplicate rcon handler for " .. name)
    end
    ipc.rcon_handlers[name] = function (event_data)
        local data = game.json_to_table(event_data)
        handler(data)
    end
end

function ipc.register_untyped_rcon(name, handler)
    if ipc.rcon_handlers[name] then
        error("Duplicate rcon handler for " .. name)
    end
    ipc.rcon_handlers[name] = function (event_data)
        handler(event_data)
    end
end

return ipc