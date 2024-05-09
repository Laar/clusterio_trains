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
	if global.clusterio_trains == nil then
		global.clusterio_trains = {}
	end
	if not global.clusterio_trains.zones then
		global.clusterio_trains.zones = {}
	end
	if not global.clusterio_trains.debug_shapes then
		global.clusterio_trains.debug_shapes = {}
	end
	if not global.clusterio_trains.debug_draw then
		global.clusterio_trains.debug_draw = false
	end
	globalData = global.clusterio_trains
end

--- Debug
local function debug_draw()
	local debug_shapes = global.clusterio_trains.debug_shapes;

	if debug_shapes
	then
		for idx, id in ipairs(debug_shapes) do
			rendering.destroy(id)
			debug_shapes[idx] = nil
		end
	end

	if not globalData.debug_draw
	then
		return
	end
	game.print("Drawing")
	-- Actual drawing
	local zones = global.clusterio_trains.zones;
	for zone_name, zone in pairs(zones) do
		game.print("Test")
		game.print(zone_name)
        debug_shapes[#debug_shapes + 1] = rendering.draw_rectangle {
            color = {r = 1, g = 0, b = 0},
            width = 2,
            filled = false,
            left_top = {x = zone.x1, y = zone.y1},
            right_bottom = {x = zone.x2, y = zone.y2},
            surface = zone.surface,
        }
        -- if zone.link then
        --     debug_shapes[#debug_shapes + 1] = rendering.draw_text {
        --         text = {'', zone.link.instance, ':', zone.link.target},
        --         surface = zone.surface,
        --         target = {x = zone.x1, y = zone.y1},
        --         color = {r=1, g=0, b=0},
        --     }
        -- end
    end
	game.print("Drawing end")
end

--- Public methods should be available though your top level module table
function MyModule.foo()
	game.print("foo")
end

function MyModule.sync_zones(zones)
	local zone_table = game.json_to_table(zones)
	local zone_count = 0
	for zone_name, zone in pairs(zone_table) do
		zone_count = zone_count + 1
	end
	global.clusterio_trains.zones = zone_table
	game.print({'', 'Synced ', zone_count, ' zones'})
	debug_draw();
end

function MyModule.sync_zone(name, zone)
	if (zone)
	then
		-- Update
		game.print({'', 'Zone ', name, ' update ', zone})
		local zone = game.json_to_table(zone);
		global.clusterio_trains.zones[name] = zone
	else
		global.clusterio_trains.zones[name] = nil
	end
	debug_draw();
end

function MyModule.add_zone(name, x1, y1, x2, y2, surface)
	-- local surface = surface or game.player.surface.name or ''
	-- local surface = 
	clusterio_api.send_json("clusterio_trains_zone_add", {
		name = name,
		surface = 'nauvis',
		x1 = x1,
		y1 = y1,
		x2 = x2,
		y2 = y2
	});
end

function MyModule.delete_zone(name)
	clusterio_api.send_json("clusterio_trains_zone_delete", {
		name = name
	});
end

function MyModule.link_zone(name, instance, target_name)
	clusterio_api.send_json("clusterio_trains_zone_link", {
		name = name,
		instance = instance,
		target_name = target_name
	});
end

function MyModule.zone_status(name, enabled)
	clusterio_api.send_json("clusterio_trains_zone_status", {
		name = name,
		enabled = enabled
	});
end

function MyModule.toggle_debug()
	globalData.debug_draw = not globalData.debug_draw;
	local draw = globalData.debug_draw;
	if (draw)
	then
		game.print("Debug draw enabled");
	else
		game.print("Debug draw disabled");
	end
	debug_draw();
end

--- Private methods should be local to the file, this will prevent others from calling it
-- local function bar()
-- 	game.print("bar")
-- end

--- Clusterio provides a few custom events, on_server_startup is the most useful and should be used in place of on_load
MyModule.events[clusterio_api.events.on_server_startup] = function(event)
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
return MyModule
