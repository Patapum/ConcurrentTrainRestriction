script.on_load(
    function()
        script.on_event(
            {defines.events.on_tick},
            function(e)
                if e.tick % 10 == 0 then
                    UpdateTrainPaths()
                end
            end
        )
    end
)

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
                    train = trainsToTemporary[index]
                    if train.station == nil then
                        RemoveCurrentFromSchedule(train)
                    end
                end
            elseif #trainsToTemporary < station.maxTrains then
                for index = 1, station.maxTrains - #trainsToTemporary do
                    train = trainsToActual[index]
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

function RemoveCurrentFromSchedule(train)
    local records = train.schedule.records
    table.remove(records, train.schedule.current)
    train.schedule = {records = records, current = train.schedule.current - 1}
end

function RemoveTemporaryFromSchedule(train, removeCurrent)
    if train.schedule == nil then
        return
    end
    local records = train.schedule.records
    local current = train.schedule.current
    for index = #records, 1, -1 do
        if
            (removeCurrent or index ~= current) and
                records[index].station:find("⇡") ~= nil
         then
            table.remove(records, index)
            if current >= index then
                current = current - 1
            end
        end
    end
    train.schedule = {records = records, current = current}
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
                name = "ctr-temporary-stop",
                position = station.entity.position,
                direction = station.entity.direction,
                force = station.entity.force
            }
            temporaryEntity.backer_name = "⇡" .. station.entity.unit_number
            local temporary = {
                actualEntityUnitNumber = station.entity.unit_number,
                actualEntity = station.entity,
                temporaryEntity = temporaryEntity
            }
            global.actualStations[station.entity.unit_number] = temporary
            global.temporaryStations[temporaryEntity.unit_number] = temporary
        end

        local circuit_condition = station.entity.get_control_behavior().circuit_condition
        circuit_condition.condition.constant = #station.trains
        station.entity.get_control_behavior().circuit_condition = circuit_condition
    end

    local temporary = global.actualStations[station.entity.unit_number]
    if temporary ~= nil then
        if #station.trains == 0 then
            global.temporaryStations[temporary.temporaryEntity.unit_number] = nil
            global.actualStations[temporary.actualEntityUnitNumber] = nil
            temporary.temporaryEntity.destroy()
        else
            station.temporaryEntity = temporary.temporaryEntity
            for w = 2, 3 do
                temporary.temporaryEntity.connect_neighbour({wire = w, target_entity = station.entity})
            end
            local behavior = station.entity.get_control_behavior()
            local temporaryBehavior = temporary.temporaryEntity.get_or_create_control_behavior()
            temporaryBehavior.send_to_train = behavior.send_to_train
            temporaryBehavior.read_from_train = behavior.read_from_train
            temporaryBehavior.read_stopped_train = behavior.read_stopped_train
            temporaryBehavior.stopped_train_signal = behavior.stopped_train_signal
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
    end
    return maxTrains
end
