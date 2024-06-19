import * as lib from "@clusterio/lib";
import { BaseControllerPlugin, InstanceInfo } from "@clusterio/controller";

import * as Msg from "./lib/messages";
import { InstanceDetails } from "./lib/messages";
import { TrainDB } from "./lib/traindb";
import { InstanceStatus } from "@clusterio/lib";

function reducedStatus(status: InstanceStatus) : Msg.SimpleInstanceStatus {
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
	private trainsDB! : TrainDB

	async init() {
		this.controller.handle(Msg.InstanceDetailsPatchEvent, this.handleInstancePatchEvent.bind(this))
		this.controller.handle(Msg.InstanceDetailsListRequest, this.handleInstanceDetailsListRequest.bind(this))
		this.controller.handle(Msg.TrainIdRequest, this.handleTrainIdRequest.bind(this))
		this.controller.handle(Msg.TrainTeleportRequest, this.handleTeleportRequest.bind(this))

		this.trainsDB = await TrainDB.load(this.controller.config.get('controller.database_directory'), this.logger)

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

	async handleInstancePatch(patch: Msg.InstanceDetailsPatch) {
		let instance = this.instanceDB.get(patch.id)
		if (instance != null) {
			instance.patch(patch)
			this.controller.sendTo("allInstances", new Msg.InstanceDetailsPatchEvent(patch))

		} else {
			this.logger.error(`Unknown instance with id: ${patch.id}`)
		}
	}
	async handleInstancePatchEvent(event: Msg.InstanceDetailsPatchEvent) {
		this.handleInstancePatch(event.patch);
	}

	async handleInstanceDetailsListRequest(event: Msg.InstanceDetailsListRequest) {
		let result : Array<InstanceDetails> = []
		this.instanceDB.forEach((value, _) => {
			result.push(value)
		})
		return result
	}

	async onSaveData() {
		this.trainsDB.save(this.controller.config.get('controller.database_directory'))
	}

	async onShutdown() {
		this.logger.info("controller::onShutdown");
	}

	async handleTrainIdRequest(request : Msg.TrainIdRequest) : Promise<Msg.TrainIdResponse>{
		const registration = this.trainsDB.register(request)
		return {id: registration.id, trainId: request.trainId}
	}

	async handleTeleportRequest(request: Msg.TrainTeleportRequest) : Promise<Msg.TrainTeleportResponse> {
		this.trainsDB.handleTeleportStart(request)
		// TODO: Check target is actually online
		let response: Msg.TrainTeleportResponse
			= await this.controller.sendTo({"instanceId": request.dst.instance}, request)
		this.trainsDB.handleTeleportFinished(response)
		return response
	}
} 
