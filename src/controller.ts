import * as lib from "@clusterio/lib";
import { BaseControllerPlugin, InstanceInfo } from "@clusterio/controller";
import { Static } from "@sinclair/typebox";

import {
	InstanceListRequest,
	InstanceUpdateEvent,
} from "./messages";
import { InstanceStatus } from "@clusterio/lib";

export class ControllerPlugin extends BaseControllerPlugin {
	async init() {
		this.controller.handle(InstanceListRequest, this.handleInstanceListRequest.bind(this))
	}

	async onControllerConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
		this.logger.info(`controller::onControllerConfigFieldChanged ${field}`);
	}

	async onInstanceConfigFieldChanged(instance: InstanceInfo, field: string, curr: unknown, prev: unknown) {
		this.logger.info(`controller::onInstanceConfigFieldChanged ${instance.id} ${field}`);
	}

	async onInstanceStatusChanged(instance: InstanceInfo, prev?: InstanceStatus): Promise<void> {
		let changed = prev == undefined || ((instance.status == 'running') != (prev == 'running'))
		if(changed) {
			this.controller.sendTo("allInstances", new InstanceUpdateEvent(
				instance.id,
				instance.config.get("instance.name"),
				instance.status == 'running'
			))
		}
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

	async handleInstanceListRequest(request: InstanceListRequest) {
		let result : Array<Static<typeof InstanceListRequest.instanceResponse>> = []
		this.controller.instances.forEach((info: InstanceInfo, id: number) => {
			let name: string = info.config.get("instance.name")
			result.push({
				id: id,
				name: name,
				available: info.status == 'running'
			})
		})
		return result
	}
}
