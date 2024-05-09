import * as lib from "@clusterio/lib";
import { BaseInstancePlugin } from "@clusterio/host";
import { PluginExampleEvent, PluginExampleRequest } from "./messages";

type PuginExampleIPC = {
	tick: number,
	player_name: string,
};

export class InstancePlugin extends BaseInstancePlugin {
	async init() {
		this.instance.handle(PluginExampleEvent, this.handlePluginExampleEvent.bind(this));
		this.instance.handle(PluginExampleRequest, this.handlePluginExampleRequest.bind(this));
		this.instance.server.handle("clusterio_trains-plugin_example_ipc", this.handlePluginExampleIPC.bind(this));
		this.logger.info(`instance with zone config ${this.instance.config.get("clusterio_trains.zones")}`);
	}

	async onInstanceConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
		this.logger.info(`instance::onInstanceConfigFieldChanged ${field}`);
	}

	async onStart() {
		this.logger.info("instance::onStart");
	}

	async onStop() {
		this.logger.info("instance::onStop");
	}

	async onPlayerEvent(event: lib.PlayerEvent) {
		this.logger.info(`onPlayerEvent::onPlayerEvent ${JSON.stringify(event)}`);
		this.sendRcon("/sc clusterio_trains.foo()");
	}

	async handlePluginExampleEvent(event: PluginExampleEvent) {
		this.logger.info(JSON.stringify(event));
	}

	async handlePluginExampleRequest(request: PluginExampleRequest) {
		this.logger.info(JSON.stringify(request));
		return {
			myResponseString: request.myString,
			myResponseNumbers: request.myNumberArray,
		};
	}

	async handlePluginExampleIPC(event: PuginExampleIPC) {
		this.logger.info(JSON.stringify(event));
	}
}
