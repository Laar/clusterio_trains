
local clusterio_api = require("modules/clusterio/api")

-----------------
--- IPC types ---
-----------------

--- @class ClearenceIPC
--- @field length number
--- @field dst ZoneInstance
--- @field targetStation string

--- @class TeleportIPC
--- @field trainId number
--- @field src {zone: ZoneName}
--- @field dst ZoneInstance
--- @field tick number
--- @field train SerializedTrain
--- @field station string

--- @class InstanceDetailsIPC
--- @field stations? string[]

--- @class TrainIdIPC
--- @field ref integer
--- @field trainLId integer
--- @field tick number


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
--- @field dst ZoneInstance
--- @field station string

--- @class OnClearenceRCON
--- @field id integer
--- @field result string

--- @class OnTeleportReceiveRCON
--- @field trainId integer
--- @field dst ZoneInstance
--- @field train SerializedTrain
--- @field station string

--- @class OnTrainIdRCON
--- @field id number
--- @field ref number

--- @class TeleportReceivedRCON
--- @field tick number
--- @field trainId number?

--- @class OnDepartureReceived
--- @field trainId integer
--- @field arrival TeleportReceivedRCON

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