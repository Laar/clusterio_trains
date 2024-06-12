
local user_feedback = {}
-------------------------------------------
-- Functions for rendering user feedback --
-------------------------------------------


---comment
---@param train LuaTrain
---@param clearence_response OnClearenceRCON
function user_feedback.show_train_clearence_feedback(train, clearence_response)
    ---@type LuaEntity
    local target_entity
    if train.station then
        target_entity = train.station
    else
        target_entity = train.carriages[1]
    end
    if target_entity == nil then return end -- Should not happen
    local surface = target_entity.surface
    surface.create_entity{
        name = 'flying-text',
        position = target_entity.position,
        text = {'', clearence_response.result}
    }
end

return user_feedback