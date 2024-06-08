local clusterio_api = require("modules/clusterio/api")
local instance_api = require("modules/clusterio_trains/instances")

local gui = {
    events = {}
}

--- @class PlayerGuiGlobal
--- @field frame LuaGuiElement
--- @field offworld LuaGuiElement
--- @field locomotive? LuaEntity_RollingStock
--- @field station_list string[]

--- @type {[integer]: PlayerGuiGlobal}
local guiglobal

---@param player LuaPlayer
local function build_interface(player)
    local index = player.index
    -- Close previous gui
    if guiglobal and guiglobal[index] and guiglobal[index].frame then
        guiglobal[index].frame.destroy()
    end

    local anchor = {gui=defines.relative_gui_type.train_gui, position=defines.relative_gui_position.left}
    local frame = player.gui.relative.add{type="frame", anchor=anchor,
        name = "clusterio_trains_frame", caption={'', 'Clusterio Schedule'},
        direction = "vertical",
        style = "frame",
    }
    frame.style.vertically_stretchable = true

    local offworld_list = frame.add{type="list-box"}
    guiglobal[index] = {
        frame = frame,
        offworld = offworld_list,
        station_list = {}
    }
end


---@param player LuaPlayer
---@param locomotive LuaEntity_RollingStock
local function set_train(player, locomotive)
    local pgui = guiglobal[player.index]
    if not pgui then
        build_interface(player)
        pgui = guiglobal[player.index]
    end
    pgui.locomotive = locomotive
end

---

function gui.set_offworld_stations()
    game.print('Updating gui')
    local instances = instance_api.get_all_instances()
    local all_stations = {}
    local this_id = clusterio_api.get_instance_id()
    for id, instance in pairs(instances) do
        if id ~= this_id and instance.stations then
            game.print({'', 'Adding stations for ', instance.name})
            for _, name in ipairs(instance.stations) do
                all_stations[name] = true
            end
        end
    end
    game.print({'', 'All stations ', game.table_to_json(all_stations)})
    local raw_stations = {}
    local formatted_stations = {}
    for name, _ in pairs(all_stations) do
        raw_stations[#raw_stations+1] = name
        formatted_stations[#formatted_stations+1] = {'', name}
    end
    for _, pgui in pairs(guiglobal) do
        pgui.offworld.items = formatted_stations
        pgui.station_list = raw_stations
    end
end

---

function gui.init()
    if not global.clusterio_trains.gui then
        global.clusterio_trains.gui = {}
    end
    for index, pgui in pairs(global.clusterio_trains.gui) do
        build_interface(game.players[index])
    end
    gui.on_load()
    gui.set_offworld_stations()
end

function gui.on_load()
    guiglobal = global.clusterio_trains.gui
end

gui.events[defines.events.on_player_created] = function (event)
    ---@cast event EventData.on_player_created
    local player = game.get_player(event.player_index)
    if player then
        build_interface(player)
    end
end

---@param event EventData.on_gui_opened
gui.events[defines.events.on_gui_opened] = function (event)
    local player = game.players[event.player_index]
    local entity = event.entity
    if entity and entity.valid and entity.type == 'locomotive' then
        --- @cast entity LuaEntity_RollingStock
        set_train(player, entity)
    end
end

--- @param event EventData.on_gui_closed
gui.events[defines.events.on_gui_closed] = function (event)
    local entity = event.entity
    if not entity or not entity.valid or entity.type ~= 'locomotive' then return end
    local pgui = guiglobal and guiglobal[event.player_index]
    if pgui ~= nil then
        pgui.locomotive = nil
    end
end

--- @param event EventData.on_gui_selection_state_changed
gui.events[defines.events.on_gui_selection_state_changed] = function (event)
    local index = event.player_index
    local pgui = guiglobal[index]
    -- Nothing selected
    if not pgui or not pgui.offworld or not pgui.offworld.valid
        or pgui.offworld.selected_index == 0 then return end
    -- Not valid train selected
    if not pgui.locomotive or not pgui.locomotive.valid then return end

    local offworld = pgui.offworld
    local selected_item = pgui.station_list[offworld.selected_index]
    if selected_item == nil then return end -- TODO add warning

    local train = pgui.locomotive.train
    if not train or not train.valid then return end

    -- train.schedule
    local schedule = train.schedule
    if schedule then
        table.insert(schedule.records, {station = selected_item})
        train.schedule = schedule
    else
        -- Empty schedule
        train.schedule = {
            current = 1,
            records = {{station = selected_item}}
        }
    end

    -- Clear selection
    pgui.offworld.selected_index = 0
end

--- @param event EventData.on_player_removed
gui.events[defines.events.on_player_removed] = function (event)
    local pgui = guiglobal and guiglobal[event.player_index]
    if pgui and pgui.frame and pgui.frame.valid then
        pgui.frame.destroy()
    end
end

gui.events[instance_api.defines.on_stations_changed] = function (event)
    gui.set_offworld_stations()
end

return gui