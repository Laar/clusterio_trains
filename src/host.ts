import * as lib from "@clusterio/lib";
import { BaseHostPlugin } from "@clusterio/host";
import { } from "./messages";

export class HostPlugin extends BaseHostPlugin {
	async init() {
	}

	async onHostConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
		this.logger.info(`host::onInstanceConfigFieldChanged ${field}`);
	}

	async onShutdown() {
		this.logger.info("host::onShutdown");
	}
}
