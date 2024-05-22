import * as lib from "@clusterio/lib";
import { BaseInstancePlugin } from "@clusterio/host";
import { InstanceDetails, InstanceListRequest, PluginExampleEvent, PluginExampleRequest } from "./messages";
import { Type, Static } from "@sinclair/typebox";

export type ZoneConfig = Record<string, ZoneDefinition>;

export type ZoneDefinition = {
	// Name of the zone
	name: string,
	// Linking target
	link: ZoneTarget | null,
	// Whether enabled
	enabled: boolean,
	// Surface on this host
	surface: string,
	x1: number,
	y1: number,
	x2 : number
	y2: number
};

export type ZoneTarget = {
	instance: number
	name: string
}

class InputValidationError extends Error {};

type ZoneAddIPC = {
	name: string,
	surface: string,
	x1: number,
	y1: number,
	x2 : number
	y2: number
}

type ZoneDeleteIPC = {
	name: string
}

type ZoneLinkIPC = {
	name: string
	instance: number
	target_name: string
}

type ZoneStatusIPC = {
	name: string
	enabled: boolean
}

export class InstancePlugin extends BaseInstancePlugin {
	private instanceDB : Map<number, InstanceDetails> = new Map()

	async init() {
		this.instance.handle(PluginExampleEvent, this.handlePluginExampleEvent.bind(this));
		this.instance.handle(PluginExampleRequest, this.handlePluginExampleRequest.bind(this));

		this.instance.server.handle("clusterio_trains_zone_add", 
			this.wrapEventFeedback(this.handleZoneAddIPC.bind(this)));
		this.instance.server.handle("clusterio_trains_zone_delete", 
			this.wrapEventFeedback(this.handleZoneDeleteIPC.bind(this)));
		this.instance.server.handle("clusterio_trains_zone_link", 
			this.wrapEventFeedback(this.handleZoneLinkIPC.bind(this)));
		this.instance.server.handle("clusterio_trains_zone_status", 
			this.wrapEventFeedback(this.handleZoneStatusIPC.bind(this)));
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

	async handleZoneAddIPC(event: ZoneAddIPC) {
		this.logger.info(`Received zone add ${JSON.stringify(event)}`);
		// Check validity
		if (event.x1 >= event.x2 || event.y1 >= event.y2)
			throw new InputValidationError('Ordering of x or y coordinates incorrect');
		if (event.name.trim().length == 0)
			throw new InputValidationError('Empty name');
		this.logger.info(JSON.stringify(event));
		const zones = this.instance.config.get("clusterio_trains.zones");
		for(const key in zones) {
			if (key == event.name)
				// Duplicate name
				throw new InputValidationError('Duplicate zone name');
			let zone = zones[key];
			let overlap = !(zone.x1 > event.x2 || zone.x2 < event.x1) && !(zone.y1 > event.y1 || zone.y2 < event.y2);
			if(overlap)
				throw new InputValidationError(`New zone overlaps with ${zone.name}`);
		}
		let newZones = {...zones};
		let newZone = {...event,
			link: null,
			enabled: false // Can't enable an unlinked zone
		}
		newZones[event.name] = newZone;
		this.instance.config.set("clusterio_trains.zones", newZones);
		this.logger.info(`Created zone ${event.name}`);
		await this.syncZone(event.name);
		this.logger.info(`Finished creating zone ${event.name}`);
	}

	async handleZoneDeleteIPC(event: ZoneDeleteIPC) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		if (event.name in zones) {
			let newZones = {...zones};
			delete newZones[event.name];
			this.instance.config.set("clusterio_trains.zones", newZones);
			this.logger.info(`Deleting zone ${event.name}`);
			await this.syncZone(event.name);
		} else {
			throw new InputValidationError(`Unknown zone ${event.name}`);
		}
	}

	async handleZoneStatusIPC(event : ZoneStatusIPC) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		if(event.name in zones) {
			let newZones = {...zones};
			zones[event.name].enabled = event.enabled;
			this.instance.config.set("clusterio_trains.zones", newZones);
			this.logger.info(`Setting zone ${event.name} status ${event.enabled}`);
			await this.syncZone(event.name);
		} else {
			throw new InputValidationError(`Unknown zone ${event.name}`);
		}
	}

	async handleZoneLinkIPC(event: ZoneLinkIPC) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		if(event.name in zones) {
			let newZones = {...zones};
			
			zones[event.name].link = {instance: event.instance, name: event.target_name};
			this.instance.config.set("clusterio_trains.zones", newZones);
			this.logger.info(`Linking zone ${event.name} to ${event.instance}:${event.target_name}`);
			await this.syncZone(event.name);
		} else {
			throw new InputValidationError(`Unknown zone ${event.name}`);
		}
	}

	async syncZone(name: string) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		this.logger.info(`Sending data about zone ${name}`)
		if (name in zones) {
			// Update
			let data = lib.escapeString(JSON.stringify(zones[name]));
			this.sendRcon(`/c clusterio_trains.zones.sync("${name}", "${data}")`);
		} else {
			// Delete
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
