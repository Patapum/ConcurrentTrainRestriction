script.on_event(
    {defines.events.on_tick},
    function(e)
        UpdateTrainPaths()
    end
)

script.on_event(
    {defines.events.on_train_changed_state},
    function(e)
        UpdateTrainPaths()
    end
)

function UpdateTrainPaths()
    local stations = {}
    local stuckTrains = {}

    for _, force in pairs(game.forces) do
        for _, train in pairs(force.get_trains()) do
            local entity = train.path_end_stop
            if entity then
                local station = GetOrCreateStation(stations, entity)
                table.insert(station.trains, train)
            else
                table.insert(stuckTrains, train)
            end
        end
    end

    for _, station in pairs(stations) do
        CheckOverload(station)
    end

    for _, station in pairs(stations) do
        local index = station.maxTrains + 1
        while #station.trains >= index do
            local train = table.remove(station.trains, index)
            RecalculatePath(train, stations)
        end
    end

    for _, train in pairs(stuckTrains) do
        RecalculatePath(train, stations)
    end

    for _, station in pairs(stations) do
        if station.entity.backer_name == "" then
            station.entity.backer_name = station.name
        end
    end
end

function SetTrainState(train, enable)
end

function RecalculatePath(train, stations)
    if train.state == defines.train_state.arrive_signal then
        return
    end
    local entity = train.path_end_stop
    SetTrainState(train, true)
    train.recalculate_path(true)
    local newEntity = train.path_end_stop
    if newEntity ~= entity and newEntity ~= nil then
        local newStation = GetOrCreateStation(stations, newEntity)
        table.insert(newStation.trains, train)
        if CheckOverload(newStation) then
            RecalculatePath(train, stations)
        end
    else
        SetTrainState(train, false)
    end
end

function GetOrCreateStation(stations, entity)
    local station = stations[entity.unit_number]

    if station == nil then
        station = {
            entity = entity,
            maxTrains = GetMaxTrains(entity),
            trains = {},
            name = entity.backer_name
        }
        stations[entity.unit_number] = station
    end

    return station
end

function CheckOverload(station)
    if station.entity.backer_name ~= "" and #station.trains >= station.maxTrains then
        station.entity.backer_name = ""
    end
    return #station.trains > station.maxTrains
end

function GetMaxTrains(entity)
    local maxTrains = nil
    local behavior = entity.get_control_behavior()
    if
        behavior and
            behavior.enable_disable and
            behavior.circuit_condition.condition.comparator == ">" and
            behavior.circuit_condition.condition.first_signal and
            behavior.circuit_condition.condition.first_signal.name == "locomotive" and
            behavior.circuit_condition.condition.second_signal == nil and
            behavior.circuit_condition.condition.constant == 0
     then
        for w = 2, 3 do
            local network = entity.get_circuit_network(w)
            if network then
                local signal = network.get_signal({["name"] = "locomotive", ["type"] = "item"})
                if signal and signal ~= 0 then
                    maxTrains = (maxTrains or 0) + signal
                end
            end
        end
    end
    return math.max(maxTrains or 999999999, 0)
end
