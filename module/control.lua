local clusterio_api = require("modules/clusterio/api")
local zones_api = require("modules/clusterio_trains/zones")
local stations_api = require("modules/clusterio_trains/stations")

local clusterio_trains = {
	events = stations_api.events,
	on_nth_tick = {},
}

clusterio_trains.zones = {
	sync_all = zones_api.sync_all,
	sync = zones_api.sync,
	add = zones_api.add,
	delete = zones_api.delete,
	link = zones_api.link,
	status = zones_api.status,
	debug = zones_api.debug
}

local function setupGlobalData()
	if global.clusterio_trains == nil then
		global.clusterio_trains = {}
	end
	zones_api.init()
	stations_api.init()
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
