import * as lib from "@clusterio/lib";
import { BaseInstancePlugin } from "@clusterio/host";
import { InstanceDetails, InstanceListRequest, PluginExampleEvent, PluginExampleRequest } from "./messages";
import { Type, Static } from "@sinclair/typebox";

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


export class InstancePlugin extends BaseInstancePlugin {
	private instanceDB : Map<number, InstanceDetails> = new Map()

	async init() {
		this.instance.handle(PluginExampleEvent, this.handlePluginExampleEvent.bind(this));
		this.instance.handle(PluginExampleRequest, this.handlePluginExampleRequest.bind(this));

		this.instance.server.handle("clusterio_trains_zone",
			this.wrapEventFeedback(this.handleZoneUpdateIPC.bind(this)))
		await this.refreshInstances()
	}

	async onInstanceConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
		this.logger.info(`instance::onInstanceConfigFieldChanged ${field}`);
		this.logger.info(`old ${JSON.stringify(prev)}`);
		this.logger.info(`new ${JSON.stringify(curr)}`);
	}

	async onStart() {
		let zones = this.instance.config.get("clusterio_trains.zones");
		let data = JSON.stringify(zones);
		this.logger.info(`Uploading zone data ${data}`);
		this.sendRcon(`/c clusterio_trains.zones.sync_all("${lib.escapeString(data)}")`);
		this.sendInstances();
	}

	async onStop() {
		this.logger.info("instance::onStop");
	}

	async onPlayerEvent(event: lib.PlayerEvent) {
		this.logger.info(`onPlayerEvent::onPlayerEvent ${JSON.stringify(event)}`);
		// this.sendRcon("/sc clusterio_trains.foo()");
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

	wrapEventFeedback<T>(handler: (event: T) => Promise<void>) : ((event: T) => Promise<void>) {
		return async (event) => {
			try {
				await handler(event)
			} catch (err: unknown) {
				if (err instanceof InputValidationError) {
					this.logger.info(`Command failed with error ${err.message}`);
					this.sendRcon(`/c game.print("${err.message}")`);
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

		this.logger.info(`Syncing zone ${name}`)
		if (event.t !== "Delete") {
			let data = lib.escapeString(JSON.stringify(newZones[name]));
			this.sendRcon(`/c clusterio_trains.zones.sync("${name}", "${data}")`);
		} else {
			this.sendRcon(`/c clusterio_trains.zones.sync("${name}")`);
		}
	}

	async refreshInstances() {
		let instances : Array<InstanceDetails>
			= await this.instance.sendTo("controller", new InstanceListRequest())
		this.instanceDB.clear()
		instances.forEach(instance => {
			this.instanceDB.set(instance.id, {id: instance.id, name: instance.name})
		})
		this.logger.info(`Updated instances found ${instances.length}`)
	}

	async sendInstances() {	 
		this.logger.info('Overwriting instance list')
		let data = JSON.stringify(Array.from(this.instanceDB.values()))
		this.sendRcon(`/c clusterio_trains.zones.set_instances("${lib.escapeString(data)}")`)
	}
}
