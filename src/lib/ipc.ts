import { LuaPartial } from "../util/luapartial"
import * as T from "./types"

export type ZoneUpdateIPC = {
	z : LuaPartial<T.ZoneDefinition>,
	t : T.UpdateType
}

export type ClearenceIPC = {
	length: number
	id: number
	instanceId: T.InstanceId
	targetZone: T.ZoneName
	targetStation: string
}

export type TeleportIPC = {
	trainId: T.GTrainId
	instanceId: T.InstanceId
	targetZone: T.ZoneName
	train: object
	station: string
}

export type InstanceDetailsIPC = {
	stations? : string[]
}

export type TrainIdIPC = {
	trainId: number
}

