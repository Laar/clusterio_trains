import * as lib from "@clusterio/lib";
import * as Messages from "./messages";

lib.definePermission({
	name: "clusterio_trains.example.permission.event",
	title: "Example permission event",
	description: "Example Description. Event. Change me in index.ts",
});

lib.definePermission({
	name: "clusterio_trains.example.permission.request",
	title: "Example permission request",
	description: "Example Description. Request. Change me in index.ts",
});

declare module "@clusterio/lib" {
	export interface InstanceConfigFields {
		"clusterio_trains.zones": object;
	}
}

export const plugin: lib.PluginDeclaration = {
	name: "clusterio_trains",
	title: "Clusterio Trains",
	description: "Teleporting trains for clusterio",

	controllerEntrypoint: "./dist/node/controller",
	controllerConfigFields: {
	},

	hostEntrypoint: "./dist/node/host",
	hostConfigFields: {
	},

	instanceEntrypoint: "./dist/node/instance",
	instanceConfigFields: {
		"clusterio_trains.zones" : {
			title: "Zones",
			description: "Teleportation zones",
			type: "object",
			initialValue: {}
		},
	},

	messages: [
		Messages.PluginExampleEvent,
		Messages.PluginExampleRequest,
	],

	webEntrypoint: "./web",
	routes: [],
};
