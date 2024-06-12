

import { Type, Static } from "@sinclair/typebox";

export type InstanceId = number
/**
 * Teleport zone name
 */
export type ZoneName = string
/**
 * Global id for a train
 */
export type GTrainId = number

export interface ZoneDefinition {
	// Name of the zone
	name: string
	// Linked target
	link: ZoneTarget | null
	// Region on the map
	region: Region
}

export interface ZoneTarget {
	instanceId: InstanceId
	zoneName: ZoneName
}

export interface Region {
	surface: string
	x1: number
	y1: number
	x2: number
	y2: number
}

export enum UpdateType {
	Add = "Add",
	Update = "Update",
	Delete = "Delete"
}

export const zoneInstanceSchema = Type.Object({
    "zone" : Type.String(),
    "instance": Type.Number()
})
export type ZoneInstance = Static<typeof zoneInstanceSchema>

