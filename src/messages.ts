import { plainJson, jsonArray, jsonPrimitive, StringEnum } from "@clusterio/lib";
import { Type, Static } from "@sinclair/typebox";

export class PluginExampleEvent {
	declare ["constructor"]: typeof PluginExampleEvent;
	static type = "event" as const;
	static src = ["host", "control"] as const;
	static dst = ["controller", "host", "instance"] as const;
	static plugin = "clusterio_trains" as const;
	static permission = "clusterio_trains.example.permission.event";

	constructor(
		public myString: string,
		public myNumberArray: number[],
	) {
	}

	static jsonSchema = Type.Object({
		"myString": Type.String(),
		"myNumberArray": Type.Array(Type.Number()),
	});

	static fromJSON(json: Static<typeof PluginExampleEvent.jsonSchema>) {
		return new PluginExampleEvent(json.myString, json.myNumberArray);
	}
}

export class PluginExampleRequest {
	declare ["constructor"]: typeof PluginExampleRequest;
	static type = "request" as const;
	static src = ["host", "control"] as const;
	static dst = ["controller", "host", "instance"] as const;
	static plugin = "clusterio_trains" as const;
	static permission = "clusterio_trains.example.permission.request";

	constructor(
		public myString: string,
		public myNumberArray: number[],
	) {
	}

	static jsonSchema = Type.Object({
		"myString": Type.String(),
		"myNumberArray": Type.Array(Type.Number()),
	});

	static fromJSON(json: Static<typeof PluginExampleRequest.jsonSchema>) {
		return new PluginExampleRequest(json.myString, json.myNumberArray);
	}

	static Response = plainJson(Type.Object({
		"myResponseString": Type.String(),
		"myResponseNumbers": Type.Array(Type.Number()),
	}));
}

export class InstanceDetails {
	constructor(
		public readonly id: number,
		public name: string
	) {}

	static jsonSchema = Type.Object({
		"id": Type.Number(),
		"name": Type.String()
	})

	static fromJSON(json: Static<typeof InstanceDetails.jsonSchema>) {
		return new InstanceDetails(
			json.id, json.name
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
		"name": Type.String()
	})

	static Response = jsonArray(InstanceDetails);
}

let ClearenceResult = StringEnum(["Ready", "Offline"])
export type ClearenceResult = Static<typeof ClearenceResult>

let ClearenceResponse = Type.Object({
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
		public readonly zone: string
	) {}

	static jsonSchema = Type.Object({
		length: Type.Number(),
		id: Type.Number(),
		zone: Type.String()
	})

	static fromJSON(json: Static<typeof TrainClearenceRequest.jsonSchema>) {
		return new TrainClearenceRequest(json.length, json.id, json.zone)
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
		public readonly train: object
	) {}

	static jsonSchema = Type.Object({
		zone: Type.String(),
		train: Type.Object({})
	})

	static fromJSON(json: Static<typeof TrainTeleportRequest.jsonSchema>) {
		return new TrainTeleportRequest(
			json.zone,
			json.train
		)
	}

	static Response = plainJson(Type.Object({}))
}