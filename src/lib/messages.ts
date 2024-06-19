import { plainJson, jsonArray, jsonPrimitive, StringEnum } from "@clusterio/lib";
import { Type, Static } from "@sinclair/typebox";
import { ZoneInstance, zoneInstanceSchema } from "./types";

export const SimpleInstanceStatus = Type.Union([
	Type.Literal("unavailable"),
	Type.Literal("starting"),
	Type.Literal("available")])
export type SimpleInstanceStatus = Static<typeof SimpleInstanceStatus>

export class InstanceDetails {
	public readonly id: number
	private _name: string
	private _status: SimpleInstanceStatus
	private _stations: string[]

	constructor(id: number, name: string, status: InstanceDetails["_status"], stations: string[]) {
		this.id = id
		this._name = name
		this._status = status
		this._stations = stations
	}

	get name() {return this._name}
	get status() { return this._status }
	get stations() { return this._stations }


	static jsonSchema = Type.Object({
		"id": Type.Number(),
		"name": Type.String(),
		"status": SimpleInstanceStatus,
		"stations": Type.Array(Type.String())
	})

	static fromJSON(json: Static<typeof InstanceDetails.jsonSchema>) {
		return new InstanceDetails(
			json.id,
			json.name,
			json.status,
			json.stations)
	}

	toJSON() {
		return {
			id: this.id,
			name: this.name,
			status: this.status,
			stations: this.stations,
		}
	}

	public patch(update: InstanceDetailsPatch) : void {
		if(this.id != update.id) {throw new Error("Incorrect instance")}
		if(update.name !== undefined) this._name = update.name
		if(update.status !== undefined) this._status = update.status
		if(update.stations !== undefined) this._stations = update.stations
	}
}

// This would be nicer with the Type.Mapped
export const InstanceDetailsPatch = Type.Object({
	"id": Type.Number(),
	"name": Type.Optional(Type.String()),
	"status": Type.Optional(SimpleInstanceStatus),
	"stations": Type.Optional(Type.Array(Type.String()))
})
export type InstanceDetailsPatch = Static<typeof InstanceDetailsPatch>

// Request to the controller to get all instance details
export class InstanceDetailsListRequest {
	declare ["constructor"]: typeof InstanceDetailsListRequest
	static type = "request" as const
	static src = ["instance"] as const
	static dst = ["controller"] as const
	static plugin = "clusterio_trains" as const

	constructor() {}
	static jsonSchema = Type.Object({})
	static fromJSON(json: Static<typeof InstanceDetailsListRequest.jsonSchema>) {
		return new InstanceDetailsListRequest()
	}

	static Response = jsonArray(InstanceDetails)
}

export class InstanceDetailsPatchEvent {
	declare ["constructor"]: typeof InstanceDetailsPatchEvent
	static type = "event" as const
	static src = ["instance", "controller"] as const
	static dst = ["instance", "controller"] as const
	static plugin = "clusterio_trains" as const

	private _patch: InstanceDetailsPatch
	public constructor(patch: InstanceDetailsPatch) {
		this._patch = patch
	}

	get patch() {
		return this._patch
	}

	static jsonSchema = InstanceDetailsPatch
	static fromJSON(json: Static<typeof InstanceDetailsPatch>) {
		return new InstanceDetailsPatchEvent(json)
	}
	toJSON() {
		return this._patch;
	}
}

// let ClearenceResult = StringEnum(["Ready", "Offline", "Failure"])
let ClearenceResult = Type.Union([
	Type.Literal("Ready"),
	Type.Literal("Offline"),
	Type.Literal("Failure"),
	Type.Literal("TooLong"),
	Type.Literal("Full"),
	Type.Literal("NoIngress"),
	Type.Literal("NoStations"),
	Type.Literal("NoSuchStation"),
	Type.Literal("NoZone")
])
export type ClearenceResult = Static<typeof ClearenceResult>

export let ClearenceResponse = Type.Object({
	"result" : ClearenceResult,
	"id": Type.Number()
})

export type ClearenceResponse = Static<typeof ClearenceResponse>

export class TrainClearenceRequest {
	declare ["constructor"]: typeof TrainClearenceRequest
	static type = "request" as const
	static src = ["instance"] as const
	static dst = ["instance"] as const
	static plugin = "clusterio_trains" as const
	// permissions

	constructor(
		public readonly length: number,
		public readonly id: number,
		public readonly dst: ZoneInstance,
		public readonly station: string
	) {}

	static jsonSchema = Type.Object({
		length: Type.Number(),
		id: Type.Number(),
		dst: zoneInstanceSchema,
		station: Type.String()
	})

	static fromJSON(json: Static<typeof TrainClearenceRequest.jsonSchema>) {
		return new TrainClearenceRequest(json.length, json.id, json.dst, json.station)
	}

	static Response = plainJson(ClearenceResponse)
}

export class TrainTeleportRequest {
	declare ["constructor"]: typeof TrainTeleportRequest
	static type = "request" as const
	static src = ["instance", "controller"] as const
	static dst = ["instance", "controller"] as const
	static plugin = "clusterio_trains" as const

	constructor(
		public readonly trainId: number,
		public readonly dst: ZoneInstance,
		public readonly src: ZoneInstance,
		public readonly tick: number,
		public readonly train: object,
		public readonly station: string
	) {}

	static jsonSchema = Type.Object({
		trainId: Type.Number(),
		dst: zoneInstanceSchema,
		src: zoneInstanceSchema,
		tick: Type.Number(),
		train: Type.Object({}),
		station: Type.String(),
	})

	static fromJSON(json: Static<typeof TrainTeleportRequest.jsonSchema>) {
		return new TrainTeleportRequest(
			json.trainId,
			json.dst,
			json.src,
			json.tick,
			json.train,
			json.station
		)
	}

	static Response = plainJson(Type.Object({
		trainId: Type.Number(),
		arrival: Type.Optional(Type.Object({
			tick: Type.Number(),
			trainId: Type.Optional(Type.Number())
		}))
	}))
}

export type TrainTeleportResponse 
	= Static<typeof TrainTeleportRequest.Response.jsonSchema>

export class TrainIdRequest {
	declare ["constructor"]: typeof TrainIdRequest
	static type = "request" as const
	static src = ["instance"] as const
	static dst = ["controller"] as const
	static plugin = "clusterio_trains" as const

	constructor(
		public readonly instance: number,
		public readonly trainId: number,
		public readonly tick: number
	) {}

	static jsonSchema = Type.Object({
		instance: Type.Number(), 
		trainId: Type.Number(),
		tick: Type.Number()
	})
	static fromJSON(json: Static<typeof TrainIdRequest.jsonSchema>) {
		return new TrainIdRequest(json.instance, json.trainId, json.tick)
	}

	static Response = plainJson(Type.Object({id : Type.Number(), trainId: Type.Number()}))
}

export type TrainIdResponse
	= Static<typeof TrainIdRequest.Response.jsonSchema>