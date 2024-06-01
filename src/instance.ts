import * as lib from "@clusterio/lib";
import { BaseInstancePlugin, Instance } from "@clusterio/host";
import { ClearenceResponse, InstanceDetails, InstanceListRequest, InstanceUpdateEvent, TrainClearenceRequest, TrainTeleportRequest } from "./messages";
import { Type, Static } from "@sinclair/typebox";
import { Value } from "@sinclair/typebox/value";

export type ZoneConfig = Record<string, ZoneDefinition>;

export type ZoneDefinition = {
	// Name of the zone
	name: string
	// Linked target
	link: ZoneTarget | null
	// Region on the map
	region: Region
}

export type ZoneTarget = {
	instanceId: number
	zoneName: string
}

export type Region = {
	surface: string
	x1: number
	y1: number
	x2: number
	y2: number
}

enum UpdateType {
	Add = "Add",
	Update = "Update",
	Delete = "Delete"
}

type ZoneUpdateIPC = {
	z : Partial<ZoneDefinition>,
	t : UpdateType
}

class InputValidationError extends Error {};


type ClearenceIPC = {
	length: number
	id: number
	instanceId: number
	targetZone: string
}

type TeleportIPC = {
	instanceId: number
	targetZone: string
	train: object
}

export class InstancePlugin extends BaseInstancePlugin {
	private instanceDB : Map<number, InstanceDetails> = new Map()
	private uplinkAvailable? : boolean = undefined
	private rconAvailable : boolean = false

	async init() {
		this.instance.server.handle("clusterio_trains_zone",
			this.wrapEventFeedback(this.handleZoneUpdateIPC.bind(this)))

		this.instance.server.handle("clustorio_trains_clearence", this.handleClearenceIPC.bind(this))
		this.instance.handle(TrainClearenceRequest, this.handleClearenceRequest.bind(this))
		this.instance.server.handle("clusterio_trains_teleport", this.handleTeleportIPC.bind(this))
		this.instance.handle(TrainTeleportRequest, this.handleTeleportRequest.bind(this))

		this.instance.handle(InstanceUpdateEvent, this.handleInstanceUpdate.bind(this))
		await this.refreshInstances()
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
		this.sendRcon(`/sc clusterio_trains.rcon.sync_all("${lib.escapeString(data)}")`);
		this.sendInstances();
		// Wait till the initialization has completed
		if (this.uplinkAvailable === undefined) {
			this.uplinkAvailable = true
		}
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
		await this.instance.server.sendRcon('/c global.clusterio_trains.teleports_active=' + this.uplinkAvailable, true)
		
	}

	async onStop() {
		this.rconAvailable = false
	}

	async onPlayerEvent(event: lib.PlayerEvent) {
		this.logger.info(`onPlayerEvent::onPlayerEvent ${JSON.stringify(event)}`);
		// this.sendRcon("/sc clusterio_trains.foo()");
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

	async handleZoneUpdateIPC(event: ZoneUpdateIPC) {
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
				let newZone = {name: name, region: region, link: zone.link ?? null}
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
				let updatedZone = {...zones[name], ...zone}
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
	async refreshInstances() {
		let instances : Array<InstanceDetails>
			= await this.instance.sendTo("controller", new InstanceListRequest())
		this.instanceDB.clear()
		instances.forEach(instance => {
			this.instanceDB.set(instance.id, {id: instance.id, name: instance.name, available: instance.available})
		})
		this.logger.info(`Updated instances found ${instances.length}`)
	}

	async sendInstances() {	 
		if (!this.rconAvailable) {
			this.logger.error('Sending instances without running factorio')
			return
		}
		this.logger.info('Overwriting instance list')
		let data = JSON.stringify(Array.from(this.instanceDB.values()))
		this.sendRcon(`/sc clusterio_trains.rcon.set_instances("${lib.escapeString(data)}")`)
	}

	async handleInstanceUpdate(event: InstanceUpdateEvent) {
		let data = JSON.stringify(event)
		this.instanceDB.set(event.id, event)
		if (this.rconAvailable) {
			this.sendRcon(`/c clusterio_trains.rcon.set_instance("${lib.escapeString(data)}")`)
		}
	}

	// Clearence
	async handleClearenceIPC(event: ClearenceIPC) {
		const instance = this.instanceDB.get(event.instanceId)
		let response
		if (instance === undefined) {
			this.logger.error('Invalid target instance id')
			response = {
				id: event.id,
				result: "Failure"
			}
		} else {
			const request = new TrainClearenceRequest(
				event.length,
				event.id,
				event.targetZone
			)
			if(event.instanceId == this.instance.id) {
				response = await this.handleClearenceRequest(request)
			} else if(!instance.available) {
				response = {
					id: event.id,
					response: "Offline"
				}
			} else {
				response = await this.instance.sendTo({"instanceId" : event.instanceId}, request).catch(error=>{
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

	async handleClearenceRequest(event: TrainClearenceRequest) : Promise<ClearenceResponse> {
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
		if (Value.Check(ClearenceResponse, parsedResponse)) {
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

	// Teleport
	async handleTeleportIPC(event: TeleportIPC) {
		const request = new TrainTeleportRequest(event.targetZone, event.train)
		this.logger.info(`Teleporting train to instance ${event.instanceId} zone ${request.zone}`)
		let response
		if (event.instanceId == this.instance.id) {
			response = await this.handleTeleportRequest(request)
		} else {
			response = await this.instance.sendTo({"instanceId": event.instanceId}, request)
		}
	}
	async handleTeleportRequest(request: TrainTeleportRequest) {
		this.logger.info(`Received train for zone ${request.zone}`)
		let data = JSON.stringify(request)
		if (this.rconAvailable) {
			this.sendRcon(`/sc clusterio_trains.rcon.on_teleport_receive("${lib.escapeString(data)}")`)
		} else {
			this.logger.warn('Discarded train as rcon was not available')
		}
		return {}
	}
}
