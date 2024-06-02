/*
 * In Lua assigning 'nil' to a table entry means that the entry gets removed. 
 * Hence, it is not possible to distinguish between 'key is absent' and 'no 
 * value is associated with this key'. This becomes challenging when exporting a
 * diff, as we can not distinguish between 'key is not updated' and 'key/value is 
 * removed'.
 * 
 * To support sending an update we remap the removed case to sending an update
 * with an empty object. The functions below are a means to remap this empty 
 * object to null.
 */
export type EmptyObject = {[K in any] : never}
/**
 * Object type where all 'null's have been replaced by empty objects
 */
export type LuaPartial<T> = {
	[P in keyof T]? : LuaNull<T[P]>
}
/**
 * Value where null is replaced by the empty object. The empty object is not allowed as parameter.
 */
type LuaNull<V> = null extends V ? EmptyObject | Exclude<V, null> : Exclude<V, EmptyObject>

export function isEmptyObject(arg: any): arg is EmptyObject {
	if (arg === null || arg === undefined)
		return false
	if(typeof arg !== "object")
		return false
	return Object.keys(arg).length === 0
}

export function fromLuaNull<V>(arg: V) : Exclude<V, EmptyObject>;
export function fromLuaNull<V>(arg: V | EmptyObject): V | null {
	if (isEmptyObject(arg)) {
		return null
	} else {
		return arg
	}
}
export function fromLuaPartial<T>(arg: LuaPartial<T>) : Partial<T> {
	let t : keyof T
	let result: Partial<T> = {}
	for(t in arg) {
		result[t] = fromLuaNull(arg[t])
	}
	return result
}
