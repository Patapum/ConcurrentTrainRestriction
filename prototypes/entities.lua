local function CreateInvisible(type, name)
    local newItem = table.deepcopy(data.raw[type][name])
    newItem.name = "ConcurrentTrainRestriction-invisible-" .. name
    newItem.collision_box = {{0.0, 0.0}, {0.0, 0.0}}
    newItem.selection_box = {{0.0, 0.0}, {0.0, 0.0}}
    newItem.collision_mask = {"resource-layer"}
    newItem.flags = {"not-blueprintable", "not-deconstructable"}

    local newItemControl = table.deepcopy(data.raw["item"][name])
    newItemControl.name = "ConcurrentTrainRestriction-invisible-" .. name
    newItemControl.place_result = "ConcurrentTrainRestriction-invisible-" .. name
    newItemControl.flags = {"hidden"}

    data:extend {newItem, newItemControl}
    return newItem
end

local trainStop = CreateInvisible("train-stop", "train-stop")

for _, field in pairs(
    {"animations", "light1", "light2", "rail_overlay_animations", "top_animations"}
) do
    trainStop[field] = nil
end

local combinator = CreateInvisible("constant-combinator", "constant-combinator")

combinator.circuit_wire_connection_points = trainStop.circuit_wire_connection_points

for _, field in pairs({"east", "north", "south", "west"}) do
    combinator.sprites[field].height = 0
    combinator.sprites[field].width = 0
end

combinator.activity_led_sprites.west.shift = {-0.21875, 0.65}
combinator.activity_led_sprites.north.shift = {0.296875, 0.22}
