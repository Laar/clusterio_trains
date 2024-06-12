
local clusterio_api = require("modules/clusterio/api")

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


local ipc = {}

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

return ipc