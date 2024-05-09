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
	export interface ControllerConfigFields {
		"clusterio_trains.myControllerField": string;
	}
	export interface HostConfigFields {
		"clusterio_trains.myHostField": string;
	}
	export interface InstanceConfigFields {
		"clusterio_trains.myInstanceField": string;
	}
}

export const plugin: lib.PluginDeclaration = {
	name: "clusterio_trains",
	title: "Clusterio Trains",
	description: "Teleporting trains for clusterio",

	controllerEntrypoint: "./dist/node/controller",
	controllerConfigFields: {
		"clusterio_trains.myControllerField": {
			title: "My Controller Field",
			description: "This should be removed from index.js",
			type: "string",
			initialValue: "Remove Me",
		},
	},

	hostEntrypoint: "./dist/node/host",
	hostConfigFields: {
		"clusterio_trains.myHostField": {
			title: "My Host Field",
			description: "This should be removed from index.js",
			type: "string",
			initialValue: "Remove Me",
		},
	},

	instanceEntrypoint: "./dist/node/instance",
	instanceConfigFields: {
		"clusterio_trains.myInstanceField": {
			title: "My Instance Field",
			description: "This should be removed from index.js",
			type: "string",
			initialValue: "Remove Me",
		},
	},

	messages: [
		Messages.PluginExampleEvent,
		Messages.PluginExampleRequest,
	],

	webEntrypoint: "./web",
	routes: [],
};
