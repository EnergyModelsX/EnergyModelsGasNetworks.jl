function calculate_linearise_pressures()
    P_min = 30.0  # example minimum pressure
    P_max = 70.0  # example maximum pressure
    n = 5         # number of points

    pressures = range(P_min, P_max, length=n)
    pairs = [(p1, p2) for p1 in pressures, p2 in pressures if p1 > p2]

    return pairs
end

function generate_case()

    # Define resources    
    Gas = EMB.ResourceCarrier("Gas", 0.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Gas]
    components = []

    # Time
    op_duration = 1
    op_number = 1
    operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TwoLevel(1, 1, operational_periods; op_per_strat)

    # Initialise EMB model
    model = OperationalModel(
        Dict( CO2 => StrategicProfile([160.0])),
        Dict( CO2 => FixedProfile(0)),
        CO2)

    areas = Dict()
    nodes = []
    links = []

    # Nodes in Area 1
    n = [
        GeoAvailability(101, products),
        RefSource(
            102,
            FixedProfile(150), # Capacity
            FixedProfile(0), # Var. OPEX
            FixedProfile(0), # Fix. OPEX
            Dict(Gas => 1), # Output
        ),
    ]
    l = [
        Direct(130, n[2], n[1], Linear())
    ]
    append!(nodes, n)
    append!(links, l)
    areas["1"] = n[1] # link area with GeoAvailability node

    # Nodes in Area 2
    n = [
        GeoAvailability(201, products),
        RefSource(
            202,
            FixedProfile(100), # Capacity
            FixedProfile(0), # Var. OPEX
            FixedProfile(0), # Fix. OPEX
            Dict(Gas => 1), # Output
        )
    ]
    l = [
        Direct(210, n[2], n[1], Linear())
    ]
    append!(nodes, n)
    append!(links, l)
    areas["2"] = n[1] # link area with GeoAvailability node
    
    # Nodes in Area 3
    n = [
        GeoAvailability(301, products),
        RefSource(
            302,
            FixedProfile(50), # Capacity
            FixedProfile(0), # Var. OPEX
            FixedProfile(0), # Fix. OPEX
            Dict(Gas => 1), # Output
         )
    ]
    l = [
        Direct(310, n[2], n[1], Linear())
    ]
    append!(nodes, n)
    append!(links, l)
    areas["3"] = n[1] # link area with GeoAvailability node

    # Nodes in Area 4
    n = [
        GeoAvailability(401, products)
    ]
    l = [
    ]
    append!(nodes, n)
    append!(links, l)
    areas["4"] = n[1] # link area with GeoAvailability node

    # Nodes in Area 5
    n = [
        GeoAvailability(501, products)
    ]
    l = [
    ]
    append!(nodes, n)
    append!(links, l)
    areas["5"] = n[1] # link area with GeoAvailability node

    # Nodes in Area 6
    n = [
        GeoAvailability(601, products),
        RefSink(
            602,
            FixedProfile(100), # Capacity
            Dict(:surplus => FixedProfile(-190), :deficit => FixedProfile(190)), # Penalty
            Dict(Gas => 1), # Input
        )
    ]
    l = [
        Direct(610, n[1], n[2], Linear())
    ]
    append!(nodes, n)
    append!(links, l)
    areas["6"] = n[1] # link area with GeoAvailability node

    # Nodes in Area 7
    n = [
        GeoAvailability(701, products),
        RefSink(
            702,
            FixedProfile(50), # Capacity
            Dict(:surplus => FixedProfile(-190), :deficit => FixedProfile(190)), # Penalty
            Dict(Gas => 1), # Input
        )
    ]
    l = [
        Direct(710, n[1], n[2], Linear())
    ]
    append!(nodes, n)
    append!(links, l)
    areas["7"] = n[1] # link area with GeoAvailability node

    # Create individual Areas
    area = [
        SourcePressure("1", "Supply 1", 10, 10, areas["1"], 70),
        SourcePressure("2", "Supply 2", 10, 10, areas["2"], 70),
        SourcePressure("3", "Supply 3", 10, 10, areas["3"], 70),
        BlendPressureArea("4", "Blend 4", 10, 10, areas["4"], Dict(Gas => FixedProfile(0))),
        BlendPressureArea("5", "Blend 5", 10, 10, areas["5"], Dict(Gas => FixedProfile(0))),
        TerminalPressureArea("6", "Terminal 6", 10, 10, areas["6"], 30),
        TerminalPressureArea("7", "Terminal 7", 10, 10, areas["7"], 30),
    ]

    # Create transmission modes
    # Note: The inlet and outlets do not affect as the trans_out are not associated to Resources
    # and the different flows are tracked by prop_source variable

    fixed_O = FixedProfile(0.0)
    max_pressure = 70
    weymouth = 5.37178761089193
    lin_pressures = calculate_linearise_pressures()
    tm_14 = PipePressureSimple("tm_14", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_15 = PipePressureSimple("tm_15", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_24 = PipePressureSimple("tm_24", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_25 = PipePressureSimple("tm_25", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_34 = PipePressureSimple("tm_34", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_35 = PipePressureSimple("tm_35", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_46 = PipePressureSimple("tm_46", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_47 = PipePressureSimple("tm_47", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_56 = PipePressureSimple("tm_56", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])
    tm_57 = PipePressureSimple("tm_57", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, max_pressure, weymouth, lin_pressures, Data[])

    # Create transmission corriders between areas
    transmission = [
        Transmission(area[1], area[4], [tm_14]),
        Transmission(area[1], area[5], [tm_15]),
        Transmission(area[2], area[4], [tm_24]),
        Transmission(area[2], area[5], [tm_25]),
        Transmission(area[3], area[4], [tm_34]),
        Transmission(area[3], area[5], [tm_35]),
        Transmission(area[4], area[6], [tm_46]),
        Transmission(area[4], area[7], [tm_47]),
        Transmission(area[5], area[6], [tm_56]),
        Transmission(area[5], area[7], [tm_57]),
    ]

    case = Dict(
        :areas          => area,
        :transmission   => Array{Transmission}(transmission),
        :nodes          => Array{EMB.Node}(nodes),
        :links          => Array{Link}(links),
        :products       => products,
        :components     => components,
        :T              => T,
        :pwa            => nothing
    )    

    return case, model
end

@testset "Pressure + 1 Resource" begin
    
    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m)

    @testset "Optimal solution" begin
        println(termination_status(m))
        @test termination_status(m) == MOI.LOCALLY_SOLVED
    end

    @info "FLOW:"
    @info filter(:y => x -> x > 0, df_variable(m, :trans_in))
    @info "Proportion flow:"
    @info filter(:y => x -> x > 0, df_variable(m, :prop_source))
    @info "Inlet pressures"
    @info filter(:y => x -> x > 0, df_variable(m, :p_in))
    @info "Outlet pressures"
    @info df_variable(m, :p_out)

end


