script.on_event(
    {defines.events.on_tick},
    function(e)
        if e.tick % 10 == 0 then
                UpdateTrainPaths()
        end
    end
)

script.on_configuration_changed(
    function()
        Migrations()
    end
)

function Migrations()
    if global.version == nil then
        local temporaryStations = global.temporaryStations or {}
        for _, temporary in pairs(temporaryStations) do
            if temporary.actualEntity.valid then
                local circuit_condition = temporary.actualEntity.get_control_behavior().circuit_condition
                circuit_condition.condition.constant = 0
                temporary.actualEntity.get_control_behavior().circuit_condition = circuit_condition
            end
        end
        global.temporaryStations = {}
        global.actualStations = {}
    end
    global.version = "0.2.0"
end

function UpdateTrainPaths()
    global.temporaryStations = global.temporaryStations or {}
    global.actualStations = global.actualStations or {}
    local stations = {}

    for _, temporary in pairs(global.temporaryStations) do
        if temporary.actualEntity.valid then
            GetOrCreateStation(stations, temporary.actualEntity)
        else
            global.temporaryStations[_] = nil
            global.actualStations[temporary.actualEntityUnitNumber] = nil
            temporary.temporaryEntity.destroy()
            temporary.temporaryCombinator.destroy()
        end
    end

    for _, force in pairs(game.forces) do
        for _, train in pairs(force.get_trains()) do
            RemoveTemporaryFromSchedule(train, train.manual_mode)
            if train.manual_mode == false then
                local entity = train.path_end_stop or train.station
                if entity then
                    local station = GetOrCreateStation(stations, entity)
                    table.insert(station.trains, train)
                end
            end
        end
    end

    for _, station in pairs(stations) do
        if CheckOverload(station) then
            local trainsToTemporary = {}
            local trainsToActual = {}
            for _, train in pairs(station.trains) do
                if
                    (train.path_end_stop or train.station).unit_number ==
                        station.entity.unit_number
                 then
                    table.insert(trainsToActual, train)
                else
                    table.insert(trainsToTemporary, train)
                end
            end
            if #trainsToTemporary > station.maxTrains then
                for index = station.maxTrains + 1, #trainsToTemporary do
                    local train = trainsToTemporary[index]
                    if train.station == nil then
                        RemoveTemporaryFromSchedule(train, true)
                    end
                end
            elseif #trainsToTemporary < station.maxTrains then
                for index = 1, station.maxTrains - #trainsToTemporary do
                    local train = trainsToActual[index]
                    AddTemporaryToSchedule(train, station.temporaryEntity.backer_name)
                end
            end
        end
    end
end

function AddTemporaryToSchedule(train, name)
    local records = train.schedule.records
    local current = train.schedule.current
    table.insert(
        records,
        current + 1,
        {
            station = name,
            wait_conditions = records[current].wait_conditions
        }
    )
    train.schedule = {records = records, current = current + 1}
end

function RemoveTemporaryFromSchedule(train, removeCurrent)
    if train.schedule == nil then
        return
    end
    local records = train.schedule.records
    local current = train.schedule.current
    local updated = false
    local wait_conditions = nil
    for index = #records, 1, -1 do
        if
            (removeCurrent or index ~= current) and
                records[index].station ~= nil and
                records[index].station:find("⇡") ~= nil
         then
            updated = true
            wait_conditions = records[index].wait_conditions
            table.remove(records, index)
            if current >= index then
                current = current - 1
            end
        end
    end
    if updated then
        if current > 0 then
            train.schedule = {records = records, current = current}
        elseif train.has_path then
            current = 1
            records[current] = {rail = train.path_end_rail, wait_conditions = wait_conditions, temporary = true }
            train.schedule = {records = records, current = current}
        else
            train.schedule = nil
        end
    end
end

function GetOrCreateStation(stations, entity)
    local station = stations[entity.unit_number]

    if station == nil then
        local temporary = global.temporaryStations[entity.unit_number]
        if temporary ~= nil then
            entity = temporary.actualEntity
            station = stations[entity.unit_number]
        end
    end

    if station == nil then
        station = {
            entity = entity,
            temporaryEntity = nil,
            temporaryConstant = nil,
            maxTrains = GetMaxTrains(entity),
            trains = {},
            name = entity.backer_name
        }
        stations[entity.unit_number] = station
    end

    return station
end

function CheckOverload(station)
    if station.maxTrains ~= nil then
        if
            global.actualStations[station.entity.unit_number] == nil and
                #station.trains > 0 and
                #station.trains >= station.maxTrains
         then
            local temporaryEntity =
                station.entity.surface.create_entity {
                    name = "ConcurrentTrainRestriction-invisible-train-stop",
                    position = station.entity.position,
                    direction = station.entity.direction,
                    force = station.entity.force
                }
            local temporaryCombinator =
                station.entity.surface.create_entity {
                    name = "ConcurrentTrainRestriction-invisible-constant-combinator",
                    position = station.entity.position,
                    direction = station.entity.direction,
                    force = station.entity.force
                }
            temporaryEntity.backer_name = "⇡" .. station.entity.unit_number
            local temporary = {
                actualEntityUnitNumber = station.entity.unit_number,
                actualEntity = station.entity,
                temporaryEntity = temporaryEntity,
                temporaryCombinator = temporaryCombinator
            }
            global.actualStations[station.entity.unit_number] = temporary
            global.temporaryStations[temporaryEntity.unit_number] = temporary
        end

    end

    local temporary = global.actualStations[station.entity.unit_number]
    if temporary ~= nil then
        if #station.trains == 0 then
            global.temporaryStations[temporary.temporaryEntity.unit_number] = nil
            global.actualStations[temporary.actualEntityUnitNumber] = nil
            temporary.temporaryEntity.destroy()
            temporary.temporaryCombinator.destroy()
        else
            station.temporaryEntity = temporary.temporaryEntity
            for w = 2, 3 do
                temporary.temporaryEntity.connect_neighbour({wire = w, target_entity = station.entity})
                temporary.temporaryEntity.connect_neighbour({wire = w, target_entity = station.entity})
            end
            temporary.temporaryEntity.connect_neighbour({wire = 2, target_entity = temporary.temporaryCombinator})
            temporary.temporaryCombinator.get_control_behavior().set_signal(1, {signal = {["name"] = "locomotive", ["type"] = "item"}, count = -#station.trains})
            local behavior = station.entity.get_control_behavior()
            local temporaryBehavior = temporary.temporaryEntity.get_or_create_control_behavior()
            temporaryBehavior.send_to_train = behavior.send_to_train
            temporaryBehavior.read_from_train = behavior.read_from_train
            temporaryBehavior.read_stopped_train = behavior.read_stopped_train
            if behavior.read_stopped_train and behavior.stopped_train_signal ~= nil then
                temporaryBehavior.stopped_train_signal = behavior.stopped_train_signal
            end
        end
    end

    return station.maxTrains ~= nil and #station.trains >= station.maxTrains
end

function GetMaxTrains(entity)
    local maxTrains = nil
    local behavior = entity.get_control_behavior()
    if
        behavior and behavior.enable_disable and
            behavior.circuit_condition.condition.comparator == ">" and
            behavior.circuit_condition.condition.first_signal and
            behavior.circuit_condition.condition.first_signal.name == "locomotive" and
            behavior.circuit_condition.condition.second_signal == nil
     then
        local temporary = global.actualStations[entity.unit_number]
        for _, definition in pairs(entity.circuit_connection_definitions) do
            if temporary == nil or 
                (definition.target_entity.unit_number ~= temporary.temporaryCombinator.unit_number and
                definition.target_entity.unit_number ~= temporary.temporaryEntity.unit_number)
             then
                maxTrains = 0
                for w = 2, 3 do
                    local network = entity.get_circuit_network(w)
                    if network then
                        local signal =
                            network.get_signal({["name"] = "locomotive", ["type"] = "item"})
                        if signal and signal ~= 0 then
                            maxTrains = maxTrains + signal
                        end
                    end
                end
                if temporary ~= nil and temporary.temporaryCombinator ~= nil then
                    maxTrains = maxTrains - temporary.temporaryCombinator.get_control_behavior().get_signal(1).count
                end
                maxTrains = math.max(maxTrains, 0)
                break
            end
        end
    end
    return maxTrains
end
