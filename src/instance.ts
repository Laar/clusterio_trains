import * as lib from "@clusterio/lib";
import { BaseInstancePlugin, Instance } from "@clusterio/host";
import  * as Msg from "./lib/messages";
import { InstanceDetails } from "./lib/messages";
import { Value } from "@sinclair/typebox/value";
import { fromLuaPartial, fromLuaNull } from "./util/luapartial";
import { ZoneDefinition, ZoneTarget, Region, UpdateType } from "./lib/types";
import * as IPC from "./lib/ipc"

export type ZoneConfig = Record<string, ZoneDefinition>;

class InputValidationError extends Error {};

export class InstancePlugin extends BaseInstancePlugin {
	private instanceDB : Map<number, InstanceDetails> = new Map()
	private uplinkAvailable? : boolean = undefined
	private rconAvailable : boolean = false

	async init() {
		this.instance.server.handle("clusterio_trains_zone",
			this.wrapEventFeedback(this.handleZoneUpdateIPC.bind(this)))

		this.instance.server.handle("clustorio_trains_clearence", this.handleClearenceIPC.bind(this))
		this.instance.handle(Msg.TrainClearenceRequest, this.handleClearenceRequest.bind(this))
		this.instance.server.handle("clusterio_trains_trainid", this.handleTrainIdIPC.bind(this))
		this.instance.server.handle("clusterio_trains_teleport", this.handleTeleportIPC.bind(this))
		this.instance.handle(Msg.TrainTeleportRequest, this.handleTeleportRequest.bind(this))

		this.instance.handle(Msg.InstanceDetailsPatchEvent, this.handleInstanceDetailsPatchEvent.bind(this))
		this.instance.server.handle("clusterio_trains_instancedetails", this.handleInstanceDetailsIPC.bind(this))

		if (this.uplinkAvailable === undefined) {
			this.uplinkAvailable = true
		}
		await this.refreshInstancesDB();
	}

	async onInstanceConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
		this.logger.info(`instance::onInstanceConfigFieldChanged ${field}`);
		this.logger.info(`old ${JSON.stringify(prev)}`);
		this.logger.info(`new ${JSON.stringify(curr)}`);
	}

	async onStart() {
		this.rconAvailable = true
		let zones = this.instance.config.get("clusterio_trains.zones");
		let data = JSON.stringify(zones);
		this.logger.info(`Uploading zone data ${data}`);
		await this.sendRcon(`/sc clusterio_trains.rcon.sync_all("${lib.escapeString(data)}")`);
		//
		await this.sendInstances();
		// Wait till the initialization has completed
		await this.updateTeleportState()
	}

	async onPrepareControllerDisconnect(connection: Instance): Promise<void> {
		this.uplinkAvailable = false
		await this.updateTeleportState()
	}

	onControllerConnectionEvent(event: "close" | "resume" | "drop" | "connect"): void {
		this.uplinkAvailable = ["resume", "connect"].indexOf(event) != -1
		this.updateTeleportState()
	}

	async updateTeleportState() {
		if (this.uplinkAvailable === undefined)
			this.logger.error('Undefined uplink status')
		if (!this.rconAvailable)
			this.logger.info("Not updating teleporation state due to lack of server")
		this.logger.info('Setting teleport state: ' + this.uplinkAvailable)
		await this.instance.server.sendRcon('/sc global.clusterio_trains.teleports_active=' + this.uplinkAvailable, true)
		
	}

	async onStop() {
		this.rconAvailable = false
	}

	wrapEventFeedback<T>(handler: (event: T) => Promise<void>) : ((event: T) => Promise<void>) {
		return async (event) => {
			try {
				await handler(event)
			} catch (err: unknown) {
				if (err instanceof InputValidationError) {
					this.logger.info(`Command failed with error ${err.message}`);
					if (this.rconAvailable) {
						this.sendRcon(`/sc game.print("${err.message}")`);
					}
				} else {
					throw err;
				}
			}
		};
	}

	validateZone(zone: Readonly<ZoneDefinition>, zones: Readonly<ZoneConfig>) : void {
		if(zone.region !== undefined) {
			const region = zone.region
			if (region.surface.trim().length == 0)
				throw new InputValidationError('Empty surface specification')
			if(region.x1 >= region.x2 || region.y1 >= region.y2) {
				throw new InputValidationError('Invalid region specification')
			}

			for(const key in zones) {
				if (key == zone.name)
					continue
				let otherZone = zones[key]
				if (otherZone.region === undefined)
					continue
				let otherRegion = otherZone.region
				if (otherRegion.surface !== region.surface)
					continue
				let overlap = !(otherRegion.x1 > region.x2 || otherRegion.x2 < region.x1) 
					&& !(otherRegion.y1 > region.y1 || otherRegion.y2 < region.y2);
				if (overlap)
					throw new InputValidationError(`Zone region overlaps with zone ${otherZone.name}`)
			}
		}
		if (zone.link != null)  {
			const link = zone.link
			if(!this.instanceDB.has(link.instanceId)) {
				throw new InputValidationError(`Unknown target instance with id ${link.instanceId}`)
			}
		}
	}

	async handleZoneUpdateIPC(event: IPC.ZoneUpdateIPC) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		let newZones = {...zones};

		const zone = event.z
		if (zone.name === undefined) {
			throw new InputValidationError(`Update without a zone name`)
		}
		const name = zone.name
		switch(event.t) {
			case "Add": {
				if (zone.region === undefined) {
					throw new InputValidationError("Zone creation without region")
				}
				const region = zone.region
				let newZone = {name: name, region: region, link: fromLuaNull(zone.link ?? null)}
				if (name in zones) {
					throw new InputValidationError(`Zone ${zone.name} already exists`);
				}
				this.validateZone(newZone, zones)
				newZones[name] = newZone
				this.logger.audit(`Created zone ${zone.name}`)
				break
			}
			case "Update": {
				if (!(name in zones)) {
					throw new InputValidationError(`Zone ${zone.name} does not exists`);
				}
				let updatedZone = {...zones[name], ...fromLuaPartial(zone)}
				this.validateZone(updatedZone, zones)
				newZones[name] = updatedZone
				this.logger.audit(`Updated zone ${zone.name}`)
				break
			}
			case "Delete": {
				if (!(name in zones)) {
					throw new InputValidationError(`Zone ${zone.name} does not exists`);
				}
				this.logger.audit(`Removing zone ${zone.name}`)
				delete newZones[zone.name];
				break
			}
		}
		this.instance.config.set("clusterio_trains.zones", newZones);

		if (!this.rconAvailable) {
			return // No factorio to sync to
		}
		this.logger.info(`Syncing zone ${name}`)
		if (event.t !== "Delete") {
			let data = lib.escapeString(JSON.stringify(newZones[name]));
			this.sendRcon(`/sc clusterio_trains.rcon.sync("${name}", "${data}")`);
		} else {
			this.sendRcon(`/sc clusterio_trains.rcon.sync("${name}")`);
		}
	}

	// Instance
	async refreshInstancesDB() {
		let instances : Array<InstanceDetails>
			= await this.instance.sendTo("controller", new Msg.InstanceDetailsListRequest())
		this.instanceDB.clear()
		instances.forEach(instance => {
			this.instanceDB.set(instance.id, instance)
		})
		this.logger.info(`Updated instances found ${instances.length}`)
		if (this.rconAvailable) {
			await this.sendInstances()
		}
	}

	async handleInstanceDetailsPatchEvent(event: Msg.InstanceDetailsPatchEvent) {
		const patch = event.patch
		const updateInstance = this.instanceDB.get(patch.id)
		if (updateInstance === undefined) {
			this.refreshInstancesDB()
		} else {
			updateInstance.patch(patch)
			if (this.rconAvailable) {
				let data = JSON.stringify(updateInstance)
				this.sendRcon(`/sc clusterio_trains.rcon.set_instance("${lib.escapeString(data)}")`)
			}
		}
	}
	async handleInstanceDetailsIPC(event: IPC.InstanceDetailsIPC) {
		let patch = {
			...event,
			id: this.instance.id
		}
		this.instance.sendTo("controller", new Msg.InstanceDetailsPatchEvent(patch))
	}

	async sendInstances() {	 
		if (!this.rconAvailable) {
			this.logger.error('Sending instances without running factorio')
			return
		}
		if (this.instanceDB.size == 0) {
			// Not yet loaded
			return;
		}
		this.logger.info('Overwriting instance list')
		let data = JSON.stringify(Array.from(this.instanceDB.values()))
		this.sendRcon(`/sc clusterio_trains.rcon.set_instances("${lib.escapeString(data)}")`)
	}

	// Clearence
	async handleClearenceIPC(event: IPC.ClearenceIPC) {
		const dstInstanceId = event.dst.instance
		const instance = this.instanceDB.get(event.dst.instance)
		let response
		if (instance === undefined) {
			this.logger.error('Invalid target instance id')
			response = {
				id: event.id,
				result: "Failure"
			}
		} else {
			const request = new Msg.TrainClearenceRequest(
				event.length,
				event.id,
				event.dst,
				event.targetStation
			)
			if(dstInstanceId == this.instance.id) {
				response = await this.handleClearenceRequest(request)
			} else if(instance.status !== "available") {
				response = {
					id: event.id,
					response: "Offline"
				}
			} else {
				response = await this.instance.sendTo({"instanceId" : dstInstanceId}, request).catch(error=>{
					if (error instanceof lib.RequestError && error.message === 'Instance is not running.') {
						return {
							id: event.id,
							result: "Offline"
						}
						
					}
					this.logger.error(`${error.message}:${error.name}`)
					return {
						id: event.id,
						result: "Failure"
					}
				})
			}
		}
		const data = JSON.stringify(response)
		if (this.rconAvailable) {
			this.sendRcon(`/sc clusterio_trains.rcon.on_clearence("${lib.escapeString(data)}")`)
		}
	}

	async handleClearenceRequest(event: Msg.TrainClearenceRequest) : Promise<Msg.ClearenceResponse> {
		if (!this.rconAvailable) {
			return {
				id: event.id,
				result: "Offline"
			}
		}
		const data = JSON.stringify(event)
		const rawResponse = await this.sendRcon(`/sc clusterio_trains.rcon.request_clearence("${lib.escapeString(data)}")`)
		this.logger.info(`Received response ${rawResponse}`)
		let parsedResponse
		try {
			parsedResponse = JSON.parse(rawResponse)
		} catch(e) {
			parsedResponse = {
				id: event.id,
				result: "Failure",
			}
		}
		if (Value.Check(Msg.ClearenceResponse, parsedResponse)) {
			this.logger.info('Sending valid response')
			return parsedResponse;
		} else {
			this.logger.info('Sending failure response')
			return {
				id: event.id,
				result: "Failure"
			}
		}
	}
	// Train registration
	async handleTrainIdIPC(event: IPC.TrainIdIPC) {
		if (this.uplinkAvailable) {
			this.logger.info(`Requesting new global train id for train ${event.trainLId}`)
			const request = new Msg.TrainIdRequest(this.instance.id, event.ref, event.trainLId, event.tick)
			const idResponse: Msg.TrainIdResponse = await this.instance.sendTo("controller", request)
			this.logger.info(`Received global train id ${idResponse.id} for train ${event.trainLId}`)
			if (this.rconAvailable) {
				const data = JSON.stringify(idResponse)
				await this.sendRcon(`/c clusterio_trains.rcon.on_train_id("${lib.escapeString(data)}")`)
			}
		}
	}

	// Teleport
	async handleTeleportIPC(event: IPC.TeleportIPC) {
		const request = new Msg.TrainTeleportRequest(event.trainId, event.dst,
			{instance: this.instance.id, zone: event.src.zone}, event.tick, event.train, event.station, event.historyId)
		this.logger.info(`Teleporting train ${event.trainId} to instance ${event.dst.instance} zone ${request.dst.zone}`)
		let response : Msg.TrainTeleportResponse
		if (event.dst.instance == this.instance.id) {
			response = await this.handleTeleportRequest(request)
		} else {
			response = await this.instance.sendTo("controller", request)
		}
		await this.sendRcon(`/sc clusterio_trains.rcon.on_departure_received("${lib.escapeString(JSON.stringify(response))}")`)
	}
	async handleTeleportRequest(request: Msg.TrainTeleportRequest) : Promise<Msg.TrainTeleportResponse> {
		this.logger.info(`Received train ${request.trainId} for zone ${request.dst.zone}`)
		let data = JSON.stringify(request)
		if (this.rconAvailable) {
			let response = await this.sendRcon(`/sc clusterio_trains.rcon.on_teleport_receive("${lib.escapeString(data)}")`)
			let parsedResponse: IPC.TeleportReceivedRCON
			try {
				parsedResponse = JSON.parse(response)
				return {
					trainId: request.trainId,
					arrival: parsedResponse
				}
			} catch(e) {
				// TODO: Is this the best response?
				return {
					trainId: request.trainId
				}
			}
		} else {
			this.logger.warn('Discarded train as rcon was not available')
			return {
				trainId: request.trainId,
			}
		}
	}
}
