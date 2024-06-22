
import * as lib from "@clusterio/lib";

import fs from "fs-extra";
import path from "path";
import { InstanceId, ZoneInstance, ZoneName } from "./types";
import * as Msg from "./messages";


export type TrainLocation = {
    readonly historyId: number
    readonly instance: InstanceId
    readonly tick: number
    readonly trainId?: number,
    exitZone?: ZoneName,
    exitTick?: number
}

export type TeleportLocation = TrainLocation & {
    readonly entryZone: ZoneName
    readonly entryTick: number
}


export type PendingTeleport = {
    readonly dst: ZoneInstance
}

export type TrainRegistration = {
    readonly id: number,
    history: (TrainLocation | TeleportLocation)[],
    teleport?: PendingTeleport
}

export class TrainDB {
    private trains: Map<number, TrainRegistration> = new Map()
    private logger: lib.Logger

    private constructor(logger: lib.Logger, trains?: Map<number, TrainRegistration>) {
        this.logger = logger
        if (trains) {
            this.trains = trains
        }
    }

    public static async load(basepath: string, logger: lib.Logger): Promise<TrainDB> {
        let file = path.resolve(basepath, "trains.json")
        logger.verbose(`Loading ${file}`)
        try {
            let content = await fs.readFile(file, {encoding: "utf-8"})
            let result = new Map()
            for(let entry of JSON.parse(content)) {
                result.set(entry[0], entry[1])
            }
            logger.verbose(`Loaded train db with ${result.size} trains`)
            return new TrainDB(logger, result)
        } catch(err: any) {
            if (err.code === "ENOENT") {
                logger.verbose("Creating new Train database")
                return new TrainDB(logger)
            } else {
                throw err
            }
        }
    }

    public async save(basepath: string) {
        let file = path.resolve(basepath, "trains.json")
        this.logger.verbose(`Wraiting train database ${file}`)
        let content = JSON.stringify(Array.from(this.trains))
        await lib.safeOutputFile(file, content)
    }

    private nextId(): number {
        return Array.from(this.trains.keys()).reduce((a, b) => a < b ? b : a, 0) + 1
    }

    public register(msg: Msg.TrainIdRequest) : TrainRegistration {
        const id = this.nextId()
        let registration = {
            id: id,
            history: [{
                historyId: 0,
                instance: msg.instance,
                tick: msg.tick,
                trainId: msg.trainLId
            }]
        }
        this.trains.set(id, registration)
        return registration
    }

    public handleTeleportStart(msg: Msg.TrainTeleportRequest) {
        let registration = this.trains.get(msg.trainId)
        let historyId = msg.historyId
        if (registration === undefined) {
            this.logger.warn(`Teleporting unknown train ${msg.trainId}`)
            registration = {
                id: msg.trainId,
                history: []
            }
            this.trains.set(msg.trainId, registration)
        }
        let current = registration.history.at(historyId)
        if (current === undefined || current.instance !== msg.src.instance) {
            // Fix history by inserting a new entry
            current = {
                historyId: historyId,
                instance: msg.src.instance,
                tick: msg.tick
            }
            registration.history[historyId] = current
        }
        // TODO: Check if it has already teleported
        if (registration.teleport) {
            // TODO: Do something
        }
        current.exitTick = msg.tick
        current.exitZone = msg.src.zone
        registration.teleport = {
            dst: msg.dst
        }
    }

    public handleTeleportFinished(msg: Msg.TrainTeleportResponse, historyId: number) {
        let registration = this.trains.get(msg.trainId)
        if (registration === undefined) {
            this.logger.warn(`Teleported unknown train ${msg.trainId}`)
            // TODO: Add registration
            throw new Error()
        }
        let current = registration.history.at(historyId)
        if(current === undefined) {
            this.logger.warn(`Incomplete history`)
        }
        if (registration.teleport === undefined) {
            // TODO: Do something   
        } else {
            let arrival = msg.arrival
            if(arrival !== undefined) {
                let historyItem: TeleportLocation = {
                    historyId: historyId + 1,
                    instance: registration.teleport.dst.instance,
                    tick: arrival.tick,
                    entryZone: registration.teleport.dst.zone,
                    entryTick: arrival.tick,
                    ... (arrival.trainId !== undefined ? {trainId: arrival.trainId} : {})
                }
                registration.history[historyId + 1] = historyItem
            }
            // Delete pending teleport whether received or not
            delete registration.teleport
            // TODO: Trim history
        }
    }
}