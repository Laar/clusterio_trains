local clusterio_api = require("modules/clusterio/api")
local zones_api = require("modules/clusterio_trains/zones")
local stations_api = require("modules/clusterio_trains/stations")
local trains_api = require("modules/clusterio_trains/trains")

local clusterio_trains = {
	events = {},
	on_nth_tick = {},
	rcon = {},
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

local merge_rcon = function (tables)
	local result = {}
	for _, tab in ipairs(tables) do
		if tab.rcon then
			for key, handler in pairs(tab.rcon) do
				if (result[key]) then
					error('Duplicate rcon function ' .. key)
				end
				result[key] = handler
			end
		end
	end
	return result
end

clusterio_trains.events = merge_events({stations_api, trains_api})
clusterio_trains.on_nth_tick = trains_api.on_nth_tick

clusterio_trains.rcon = merge_rcon({zones_api, trains_api})

clusterio_trains.zones = {
	add = zones_api.add,
	delete = zones_api.delete,
	link = zones_api.link,
	debug = zones_api.debug
}

local function setupGlobalData()
	if global.clusterio_trains == nil then
		global.clusterio_trains = {}
	end
	zones_api.init()
	stations_api.init()
	trains_api.init()
end

clusterio_trains.events[clusterio_api.events.on_server_startup] = function(event)
	setupGlobalData()
end

clusterio_trains.on_load = function ()
	if global.clusterio_trains ~= nil then
		-- Not safe on the first load due to lacking init
		zones_api.on_load()
		stations_api.on_load()
		trains_api.on_load()
	end
end

--- Top level module table that gets registered
return clusterio_trains
