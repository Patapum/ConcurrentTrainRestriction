local temporaryStop = table.deepcopy(data.raw["train-stop"]["train-stop"])
temporaryStop.name = "ctr-temporary-stop"
temporaryStop.collision_box = {{0.0, 0.0}, {0.0, 0.0}}
temporaryStop.selection_box = {{0.0, 0.0}, {0.0, 0.0}}
temporaryStop.collision_mask = {"resource-layer"}
temporaryStop.flags = {"not-blueprintable", "not-deconstructable"}
temporaryStop.animations = nil
temporaryStop.light1 = nil
temporaryStop.light2 = nil
temporaryStop.rail_overlay_animations = nil
temporaryStop.top_animations = nil

local temporaryStopControl = table.deepcopy(data.raw["item"]["train-stop"])
temporaryStopControl.name = "ctr-temporary-stop"
temporaryStopControl.place_result = "ctr-temporary-stop"
temporaryStopControl.flags = {"hidden"}

data:extend {
    temporaryStop,
    temporaryStopControl
}
