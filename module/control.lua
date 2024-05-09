local clusterio_api = require("modules/clusterio/api")

--- Top level module table, contains event handlers and public methods
local MyModule = {
	events = {},
	on_nth_tick = {},
}

--- global is 'synced' between players, you should use your plugin name to avoid conflicts
-- setupGlobalData should either be removed or called during clusterio_api.events.on_server_startup
local globalData = {}
local function setupGlobalData()
	if global["clusterio_trains"] == nil then
		global["clusterio_trains"] = {
			-- starting values go here
		}
	end
	globalData = global["clusterio_trains"]
end

--- Public methods should be available though your top level module table
function MyModule.foo()
	game.print("foo")
end

--- Private methods should be local to the file, this will prevent others from calling it
local function bar()
	game.print("bar")
end

--- Clusterio provides a few custom events, on_server_startup is the most useful and should be used in place of on_load
MyModule.events[clusterio_api.events.on_server_startup] = function(event)
	setupGlobalData()
	game.print(game.table_to_json(event))
end

--- Factorio events are accessible through defines.events, you can have one handler per event per module
MyModule.events[defines.events.on_player_crafted_item] = function(event)
	game.print(game.table_to_json(event))
	clusterio_api.send_json("clusterio_trains-plugin_example_ipc", {
		tick = game.tick, player_name = game.get_player(event.player_index).name
	})
end

--- Nth tick is a special case that requires its own table, the index represents the time period between calls in ticks
MyModule.on_nth_tick[300] = function()
	game.print(game.tick)
	bar()
end

--- Always return the top level module table from control, this is how clusterio will access your event handlers
return MyModule
