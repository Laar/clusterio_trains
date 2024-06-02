import { plainJson, jsonArray, jsonPrimitive, StringEnum, InstanceStatus } from "@clusterio/lib";
import { Type, Static } from "@sinclair/typebox";

export class InstanceDetails {
	constructor(
		public readonly id: number,
		public name: string,
		public available: boolean
	) {}

	static jsonSchema = Type.Object({
		"id": Type.Number(),
		"name": Type.String(),
		"available": Type.Boolean()
	})

	static fromJSON(json: Static<typeof InstanceDetails.jsonSchema>) {
		return new InstanceDetails(
			json.id, json.name, json.available
		)
	}
}

export class InstanceListRequest {
	declare ["constructor"]: typeof InstanceListRequest
	static type = "request" as const
	static src = ["instance"] as const
	static dst = ["controller"] as const
	static plugin = "clusterio_trains" as const
	// static permission = ""
	constructor() {}
	static jsonSchema = Type.Object({})

	static fromJSON(json: Static<typeof InstanceListRequest.jsonSchema>) {
		return new InstanceListRequest()
	}

	static instanceResponse = Type.Object({
		"id": Type.Number(),
		"name": Type.String(),
		"available": Type.Boolean()
	})

	static Response = jsonArray(InstanceDetails);
}

export class InstanceUpdateEvent {
	declare ["constructor"]: typeof InstanceUpdateEvent
	static type = "event" as const
	static src = ["controller"] as const
	static dst = ["instance"] as const
	static plugin = "clusterio_trains" as const
	constructor(
		public readonly id : number, 
		public readonly name: string, 
		public readonly available: boolean
	) {}
	
	static jsonSchema = InstanceListRequest.instanceResponse
	static fromJSON(json: Static<typeof InstanceUpdateEvent.jsonSchema>) {
		return new InstanceUpdateEvent(json.id, json.name, json.available)
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
		public readonly zone: string,
		public readonly station: string
	) {}

	static jsonSchema = Type.Object({
		length: Type.Number(),
		id: Type.Number(),
		zone: Type.String(),
		station: Type.String()
	})

	static fromJSON(json: Static<typeof TrainClearenceRequest.jsonSchema>) {
		return new TrainClearenceRequest(json.length, json.id, json.zone, json.station)
	}

	static Response = plainJson(ClearenceResponse)
}

export class TrainTeleportRequest {
	declare ["constructor"]: typeof TrainTeleportRequest
	static type = "request" as const
	static src = ["instance"] as const
	static dst = ["instance"] as const
	static plugin = "clusterio_trains" as const

	constructor(
		public readonly zone: string,
		public readonly train: object,
		public readonly station: string
	) {}

	static jsonSchema = Type.Object({
		zone: Type.String(),
		train: Type.Object({}),
		station: Type.String(),
	})

	static fromJSON(json: Static<typeof TrainTeleportRequest.jsonSchema>) {
		return new TrainTeleportRequest(
			json.zone,
			json.train,
			json.station
		)
	}

	static Response = plainJson(Type.Object({}))
}