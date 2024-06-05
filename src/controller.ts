import * as lib from "@clusterio/lib";
import { BaseControllerPlugin, InstanceInfo } from "@clusterio/controller";
import { Static } from "@sinclair/typebox";

import {
	SimpleInstanceStatus,
	InstanceDetails,
	InstanceDetailsPatch,
	InstanceDetailsListRequest,
	InstanceDetailsPatchEvent,
} from "./messages";
import { InstanceStatus } from "@clusterio/lib";

function reducedStatus(status: InstanceStatus) : SimpleInstanceStatus {
	switch(status) {
		case "starting":
			return "starting"
		case "running":
			return "available"
		case "creating_save":
		case "exporting_data":
		case "unknown": 
		case "unassigned":
		case "deleted":
		case "stopped":
		case "stopping":
			return "unavailable"
	}
}

export class ControllerPlugin extends BaseControllerPlugin {
	private instanceDB : Map<number, InstanceDetails> = new Map()

	async init() {
		this.controller.handle(InstanceDetailsPatchEvent, this.handleInstancePatchEvent.bind(this))
		this.controller.handle(InstanceDetailsListRequest, this.handleInstanceDetailsListRequest.bind(this))

		this.controller.instances.forEach((val, id) => {
			this.instanceDB.set(id, new InstanceDetails(id,
				val.config.get("instance.name"), reducedStatus(val.status),
				[] // TODO restore from database
			))
		})
	}

	async onControllerConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
	}

	async onInstanceConfigFieldChanged(instance: InstanceInfo, field: string, curr: unknown, prev: unknown) {
		this.logger.info(`controller::onInstanceConfigFieldChanged ${instance.id} ${field}`);
		if(field === "instance.name") {
			let name = instance.config.get("instance.name")
			let patch = {
				id: instance.id,
				name: name
			}
			await this.handleInstancePatch(patch)
		}
	}
	
	async onInstanceStatusChanged(instance: InstanceInfo, prev?: InstanceStatus): Promise<void> {
		let oldStatus = prev === undefined ? "unavailable" : reducedStatus(prev)
		let newStatus = reducedStatus(instance.status)
		if (oldStatus != newStatus) {
			let patch = {
				id: instance.id,
				status: newStatus
			}
			await this.handleInstancePatch(patch)
		}
	}

	async handleInstancePatch(patch: InstanceDetailsPatch) {
		let instance = this.instanceDB.get(patch.id)
		if (instance != null) {
			instance.patch(patch)
			this.controller.sendTo("allInstances", new InstanceDetailsPatchEvent(patch))

		} else {
			this.logger.error(`Unknown instance with id: ${patch.id}`)
		}
	}
	async handleInstancePatchEvent(event: InstanceDetailsPatchEvent) {
		this.handleInstancePatch(event.patch);
	}

	async handleInstanceDetailsListRequest(event: InstanceDetailsListRequest) {
		let result : Array<InstanceDetails> = []
		this.instanceDB.forEach((value, _) => {
			result.push(value)
		})
		return result
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
}
