local clusterio_api = require("modules/clusterio/api")
local zones_api = require("modules/clusterio_trains/zones")
local stations_api = require("modules/clusterio_trains/stations")
local trains_api = require("modules/clusterio_trains/trains")

local clusterio_trains = {
	events = {},
	on_nth_tick = {},
}

local merge_events = function (apis)
	local event_keys = {}
	for _, api in ipairs(apis) do
		if (api.events) then
			for key, handler in pairs(api.events) do
				if (event_keys[key] == nil) then event_keys[key] = {} end
				table.insert(event_keys[key], handler)
			end
		end
	end

	local events = {}
	for key, handlers in pairs(event_keys) do
		if (#handlers == 1) then
			events[key] = handlers[1]
		else
			error('Not implemented')
		end
	end
	return events
end
clusterio_trains.events = merge_events({stations_api, trains_api})

clusterio_trains.zones = {
	sync_all = zones_api.sync_all,
	sync = zones_api.sync,
	set_instances = zones_api.set_instances,
	add = zones_api.add,
	delete = zones_api.delete,
	link = zones_api.link,
	debug = zones_api.debug
}

clusterio_trains.trains = {
	on_clearence = trains_api.on_clearence,
	on_teleport_receive = trains_api.on_teleport_receive
}

local function setupGlobalData()
	if global.clusterio_trains == nil then
		global.clusterio_trains = {}
	end
	zones_api.init()
	stations_api.init()
	trains_api.init()
end

--- Clusterio provides a few custom events, on_server_startup is the most useful and should be used in place of on_load
clusterio_trains.events[clusterio_api.events.on_server_startup] = function(event)
	setupGlobalData()
end

--- Factorio events are accessible through defines.events, you can have one handler per event per module
-- MyModule.events[defines.events.on_player_crafted_item] = function(event)
-- 	game.print(game.table_to_json(event))
-- 	clusterio_api.send_json("clusterio_trains-plugin_example_ipc", {
-- 		tick = game.tick, player_name = game.get_player(event.player_index).name
-- 	})
-- end

--- Nth tick is a special case that requires its own table, the index represents the time period between calls in ticks
-- MyModule.on_nth_tick[300] = function()
-- 	game.print(game.tick)
-- 	bar()
-- end

--- Always return the top level module table from control, this is how clusterio will access your event handlers
return clusterio_trains
