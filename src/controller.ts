import * as lib from "@clusterio/lib";
import { BaseControllerPlugin, InstanceInfo } from "@clusterio/controller";
import { Static } from "@sinclair/typebox";

import {
	InstanceListRequest,
	PluginExampleEvent, PluginExampleRequest,
} from "./messages";

export class ControllerPlugin extends BaseControllerPlugin {
	async init() {
		this.controller.handle(PluginExampleEvent, this.handlePluginExampleEvent.bind(this));
		this.controller.handle(PluginExampleRequest, this.handlePluginExampleRequest.bind(this));
		this.controller.handle(InstanceListRequest, this.handleInstanceListRequest.bind(this))
	}

	async onControllerConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
		this.logger.info(`controller::onControllerConfigFieldChanged ${field}`);
	}

	async onInstanceConfigFieldChanged(instance: InstanceInfo, field: string, curr: unknown, prev: unknown) {
		this.logger.info(`controller::onInstanceConfigFieldChanged ${instance.id} ${field}`);
	}

	async onSaveData() {
		this.logger.info("controller::onSaveData");
	}

	async onShutdown() {
		this.logger.info("controller::onShutdown");
	}

	async onPlayerEvent(instance: InstanceInfo, event: lib.PlayerEvent) {
		this.logger.info(`controller::onPlayerEvent ${instance.id} ${JSON.stringify(event)}`);
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

	async handleInstanceListRequest(request: InstanceListRequest) {
		let result : Array<Static<typeof InstanceListRequest.instanceResponse>> = []
		this.controller.instances.forEach((info: InstanceInfo, id: number) => {
			let name: string = info.config.get("instance.name")
			result.push({
				id: id,
				name: name
			})
		})
		return result
	}
}
