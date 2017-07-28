script.on_event(
    {defines.events.on_tick},
    function(e)
        if e.tick % 10 == 0 then
            UpdateTrainPaths()
        end
        if e.tick % 10 == 1 then
            RestoreTrainsFuel()
        end
    end
)

function UpdateTrainPaths()
    local stations = {}
    local stuckTrains = {}
    global.trainsFuel = {}

    for _, force in pairs(game.forces) do
        for _, train in pairs(force.get_trains()) do
            if train.manual_mode == false then
                local entity = train.path_end_stop
                if entity then
                    local station = GetOrCreateStation(stations, entity)
                    table.insert(station.trains, train)
                else
                    if train.has_path == false then
                        table.insert(stuckTrains, train)
                    end
                end
            end
        end
    end

    --log("stations")
    for _, station in pairs(stations) do
        CheckOverload(station)
        --log(station.entity.unit_number .. " " .. station.entity.backer_name)
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

function RestoreTrainsFuel()
    for _, data in pairs(global.trainsFuel or {}) do
                        log(data.train.has_path)
                    log(data.train.state)
        RestoreTrainFuel(data.train, data.burners)
    end
end

function SetTrainState(train, enable)
    local schedule = train.schedule
    if schedule then
        if #schedule.records > 1 then
            if enable then
                if train.state == defines.train_state.wait_station and IsDepot(schedule.records[schedule.current]) then
                    local current = NextScheduleIndex(schedule.current, schedule.records)
                    -- local c = train.carriages[1]
                    -- c.burner.inventory.clear()
                    -- c.burner.remaining_burning_fuel = 0
                    -- train.schedule = {current = 1, records = {schedule.records[current]}}

                    -- train.manual_mode = true
                    -- train.manual_mode = false --update schedule
                    -- train.recalculate_path(true)
                    -- c.burner.inventory.insert({name = "coal", count = 1})
                    local burners = ExtractTrainFuel(train)
                    table.insert(global.trainsFuel, {train=train, burners=burners})
                    UpdateTrainSchedule(train, {current = 1, records = {schedule.records[current]}}, true)
                    log("train enable")
                    log(train.has_path)
                    log(train.state)
                    if train.has_path then
                        UpdateTrainSchedule(
                            train,
                            {
                                current = current,
                                records = schedule.records
                            },
                            true
                        )
                        --RestoreTrainFuel(train, burners)
                        return true
                    else
                        UpdateTrainSchedule(train, schedule, false)
                        train.speed = 0
                        log(train.has_path)
                        log(train.state)
                        --RestoreTrainFuel(train, burners)

                        --c.burner.inventory.insert({name="coal", count=1})
                        --train.manual_mode = true
                        --train.manual_mode = false --update schedule
                        --train.recalculate_path(true)
                        return false
                    end
                --local n = c.surface.create_entity({name=c.name, position=c.position, direction=c.direction})
                --game.print(n)
                end
            else
                --train.manual_mode = true
                --train.manual_mode = false --update schedule
                local current = FindPreviousDepotOrNextStep(schedule)
                train.schedule = {current = current, records = schedule.records}
            end
        end
    end
    return false
end

function ExtractTrainFuel(train)
    local burners = {}
    for _, carriage in pairs(train.carriages) do
        if carriage.burner then
            table.insert(
                burners,
                {
                    burner = carriage.burner,
                    remaining_burning_fuel = carriage.burner.remaining_burning_fuel,
                    currently_burning = carriage.burner.currently_burning,
                    stacks = GetInventoryStacks(carriage.burner.inventory)
                }
            )
            carriage.burner.inventory.clear()
            carriage.burner.currently_burning = nil
            carriage.burner.remaining_burning_fuel = 0
        end
    end
    return burners
end

function RestoreTrainFuel(train, burners)
    for _, data in pairs(burners) do
        data.burner.currently_burning = data.currently_burning
        data.burner.remaining_burning_fuel = data.remaining_burning_fuel
        for _, stack in pairs(data.stacks) do
            data.burner.inventory.insert(stack)
        end
    end
end

function UpdateTrainSchedule(train, schedule, force)
    train.schedule = {current = schedule.current, records = schedule.records}
    train.manual_mode = true
    train.manual_mode = false --update schedule
    if force then
        train.recalculate_path(true)
    end
end

function GetInventoryStacks(inventory)
    local result = {}
    for name, count in pairs(inventory.get_contents()) do
        table.insert(result, {name = name, count = count})
    end
    return result
end

function NextScheduleIndex(current, records)
    current = current + 1
    if current > #records then
        current = 1
    end
    return current
end

function FindPreviousDepotOrNextStep(schedule)
    local current = schedule.current
    while true do
        current = current - 1
        if current == 0 then
            current = #schedule.records
        end
        if current == schedule.current then
            current = NextScheduleIndex(current, schedule.records)
            break
        end
        local step = schedule.records[current]
        if IsDepot(step) then
            break
        end
    end
    return current
end

function IsDepot(step)
    return #step.wait_conditions == 1 and step.wait_conditions[1].type == "circuit" and
        step.wait_conditions[1].condition and
        step.wait_conditions[1].condition.comparator == "=" and
        step.wait_conditions[1].condition.first_signal and
        step.wait_conditions[1].condition.first_signal.name == "train-stop" and
        step.wait_conditions[1].condition.second_signal == nil and
        step.wait_conditions[1].condition.constant == 1
end

function RecalculatePath(train, stations)
    if train.state == defines.train_state.arrive_signal then
        return
    end
    local entity = train.path_end_stop
    --log("state " .. train.state .. " " .. train.id)
    if SetTrainState(train, true) == false or train.state == defines.train_state.wait_station then
        return
    end
    train.recalculate_path(true)
    log(1)
    local newEntity = train.path_end_stop
    if newEntity ~= entity and newEntity ~= nil then
        local newStation = GetOrCreateStation(stations, newEntity)
        table.insert(newStation.trains, train)
        if CheckOverload(newStation) then
            log(2)
            RecalculatePath(train, stations)
        end
    else
        log(3)
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
    --game.print(#station.trains.." "..station.maxTrains)
    return #station.trains > station.maxTrains
end

function GetMaxTrains(entity)
    local maxTrains = nil
    local behavior = entity.get_control_behavior()
    if
        behavior and behavior.enable_disable and behavior.circuit_condition.condition.comparator == ">" and
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
