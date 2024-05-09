import { plainJson, jsonArray, JsonBoolean, JsonNumber, JsonString, StringEnum } from "@clusterio/lib";
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
