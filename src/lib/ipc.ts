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
	src: {zone: T.ZoneName}
	dst: T.ZoneInstance
	tick: number
	train: object
	station: string
	historyId: number
}

export type InstanceDetailsIPC = {
	stations? : string[]
}

export type TrainIdIPC = {
	ref: number
	trainLId: number,
	tick: number
}

export type TeleportReceivedRCON = {
	trainId?: number,
	tick: number
}

