import { LuaPartial } from "../util/luapartial"
import * as T from "./types"

export type ZoneUpdateIPC = {
	z : LuaPartial<T.ZoneDefinition>,
	t : T.UpdateType
}

export type ClearenceIPC = {
	length: number
	id: number
	dst: T.ZoneInstance
	targetStation: string
}

export type TeleportIPC = {
	trainId: T.GTrainId
	dst: T.ZoneInstance
	train: object
	station: string
}

export type InstanceDetailsIPC = {
	stations? : string[]
}

export type TrainIdIPC = {
	trainId: number
}

