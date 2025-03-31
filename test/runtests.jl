using TestItemRunner

@run_package_tests verbose = true

@testsnippet MyTests begin
    using Pkg
    Pkg.activate(@__DIR__)
    
    using TestItems

    using Alpine
    using Ipopt
    using HiGHS
    using Juniper 
    using PiecewiseAffineApprox

    using JuMP
    using TimeStruct
    using EnergyModelsBase
    using EnergyModelsGeography
    using EnergyModelsPooling

    const EMB = EnergyModelsBase
    const EMG = EnergyModelsGeography
    const EMP = EnergyModelsPooling

    include("test_utils.jl")
end

@testitem "Only Blend" setup=[MyTests] begin
    
    function generate_case()

        # Define resources
        NG = AbstractComponent("NG", 0.0)
        H2 = ComponentTrack("H2", 0.0, 1)
        
        Gas = EMP.ComponentBlend("Gas", [NG, H2])
        CO2 = ResourceEmit("CO2", 1.0)
        products = [CO2, Gas]
        components = [NG, H2]

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
            SourceComponent(
                102,
                FixedProfile(150), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(H2 => 1) # Quality
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
            SourceComponent(
                202,
                FixedProfile(100), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(NG => 1)
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
            SourceComponent(
                302,
                FixedProfile(50), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(NG => 1)
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
            BlendingSink(
                602,
                FixedProfile(100), # Capacity
                Dict(:price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 0.2, NG => 1), # upperbound
                Dict(H2 => 0) # lowerbound
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
            BlendingSink(
                702,
                FixedProfile(50), # Capacity
                Dict(:price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 0.2, NG => 1), # upperbound
                Dict(H2 => 0) # lowerbound
            )
        ]
        l = [
            Direct(710, n[1], n[2], Linear())
        ]
        append!(nodes, n)
        append!(links, l)
        areas["7"] = n[1] # link area with GeoAvailability node

        # Create individual Areas
        blending = EMP.Blending("blend")
        area = [
            SourceArea("1", "Supply 1", 10, 10, areas["1"], blending),
            SourceArea("2", "Supply 2", 10, 10, areas["2"], blending),
            SourceArea("3", "Supply 3", 10, 10, areas["3"], blending),
            PoolingArea("4", "Blend 4", 10, 10, areas["4"], blending, Dict(NG => FixedProfile(0))),
            PoolingArea("5", "Blend 5", 10, 10, areas["5"], blending, Dict(NG => FixedProfile(0))),
            TerminalArea("6", "Terminal 6", 10, 10, areas["6"], blending),
            TerminalArea("7", "Terminal 7", 10, 10, areas["7"], blending),
        ]

        # Create transmission modes
        # Note: The inlet and outlets do not affect as the trans_out are not associated to Resources
        # and the different flows are tracked by prop_source variable
        fixed_O = FixedProfile(0.0)
        tm_14 = PipeSimple("tm_14", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_15 = PipeSimple("tm_15", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_24 = PipeSimple("tm_24", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_25 = PipeSimple("tm_25", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_34 = PipeSimple("tm_34", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_35 = PipeSimple("tm_35", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_46 = PipeSimple("tm_46", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_47 = PipeSimple("tm_47", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_56 = PipeSimple("tm_56", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])
        tm_57 = PipeSimple("tm_57", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, 1, Data[])

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
        )    

        return case, model
    end

    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m, nlp_constraints=true)

    println(termination_status(m))
    @test termination_status(m) == MOI.OPTIMAL
    

    ℒ = case[:transmission]
    𝒯 = case[:T]
    T = collect(𝒯)
    𝒜 = case[:areas]
    
    a1 = 𝒜[1]
    a2 = 𝒜[2]
    a3 = 𝒜[3]
    a4 = 𝒜[4]
    a6 = 𝒜[6]

    TM_to = [tm for l in ℒ for tm in modes(l) if l.to == a4]
    TM_from = [tm for l in ℒ for tm in modes(l) if l.from == a4]

    #_______TEST: FLOW QUANTIIES________
    # Test the inflows equals the outflows through areas
    @test isapprox(sum(value.(m[:trans_out])[tm, t] for tm ∈ TM_to for t ∈ 𝒯), 
            sum(value.(m[:trans_in])[tm, t] for tm ∈ TM_from for t ∈ 𝒯), atol=TEST_ATOL)
    
    #_______TEST: FLOW PROPORTIONS________
    source = case[:nodes][2]
    pipeline = first([tm for l in filter(x -> x.from == a1 && x.to == a4, ℒ) for tm in modes(l)])
    # Test if the proportions of flows in blending areas is correct
    @test isapprox(value.(m[:trans_out])[pipeline, T[1]]/sum(value.(m[:trans_out])[p, T[1]] for p ∈ TM_to),
                value.(m[:prop_source][a4, source, T[1]]), atol=TEST_ATOL)
    
    #_______TEST: PROP H2 AT TERMINALS________
    source = case[:nodes][2]
    pipelines = [tm for l in filter(x -> x.to == a6, ℒ) for tm in modes(l)]
    areas = [𝒜[4], 𝒜[5]]
    sink = case[:nodes][10]

    @test sum(value.(m[:trans_out])[p, T[1]] * value.(m[:prop_source][areas[i], source, T[1]]) for (i, p) in enumerate(pipelines))/sum(value.(m[:trans_out])[p, T[1]] for p in pipelines) <=
        EMP.get_upper(sink, case[:components][2])
    
    #_______PRINT RESULTS________
    @info "FLOW:"
    @info filter(:y => x -> x > 0, df_variable(m, :trans_in))
    @info "Proportion flow:"
    @info filter(:y => x -> x > 0, df_variable(m, :prop_source))
    @info "Proportion H2:"
    @info filter(:y => x -> x > 0, df_variable(m, :prop_track))

end

@testitem "Pressure + 1 Resource" setup=[MyTests] begin
    
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
            SourceArea("1", "Supply 1", 10, 10, areas["1"], Pressure(70)), # outlet pressure
            SourceArea("2", "Supply 2", 10, 10, areas["2"], Pressure(70)),
            SourceArea("3", "Supply 3", 10, 10, areas["3"], Pressure(70)),
            PoolingArea("4", "Blend 4", 10, 10, areas["4"], Pressure(0), Dict(Gas => FixedProfile(0))),
            PoolingArea("5", "Blend 5", 10, 10, areas["5"], Pressure(0), Dict(Gas => FixedProfile(0))),
            TerminalArea("6", "Terminal 6", 10, 10, areas["6"], Pressure(30)),
            TerminalArea("7", "Terminal 7", 10, 10, areas["7"], Pressure(30)), #inlet pressure
        ]

        # Create transmission modes
        # Note: The inlet and outlets do not affect as the trans_out are not associated to Resources
        # and the different flows are tracked by prop_source variable
        fixed_O = FixedProfile(0.0)
        pressure_data = PressurePipe(
            "Weymouth",
            1e6; # max_pressure
            FLOW = 67.5, #MSm3/d
            PIN = 189.3, #barg
            POUT = 147.5, #barg
        )
        tm_14 = PipeSimple("tm_14", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_15 = PipeSimple("tm_15", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_24 = PipeSimple("tm_24", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_25 = PipeSimple("tm_25", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_34 = PipeSimple("tm_34", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_35 = PipeSimple("tm_35", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_46 = PipeSimple("tm_46", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_47 = PipeSimple("tm_47", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_56 = PipeSimple("tm_56", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_57 = PipeSimple("tm_57", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])

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

    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m, nlp_constraints = false)
    
    #_______TEST: Optimal solution_______#
    println(termination_status(m))
    @test termination_status(m) == OPTIMAL

    #_______PRINT: Results_______#
    @info "FLOW:"
    @info filter(:y => x -> x > 0, df_variable(m, :trans_in))
    @info "Inlet pressures"
    @info filter(:y => x -> x > 0, df_variable(m, :p_in))
    @info "Outlet pressures"
    @info df_variable(m, :p_out)
    @info "Has Flow"
    @info df_variable(m, :has_flow)
    @info "Lower_pressure_into_node"
    @info df_variable(m, :lower_pressure_into_node)
end


@testitem "Pressure + Blend + 2 Resource" setup=[MyTests] begin
   
    function generate_case()
        # Define resources
        NG = AbstractComponent("NG", 0.0)
        H2 = ComponentTrack("H2", 0.0, 0.2)
        
        Gas = EMP.ComponentBlend("Gas", [NG, H2])
        CO2 = ResourceEmit("CO2", 1.0)
        products = [CO2, Gas]
        components = [NG, H2]

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
            SourceComponent(
                102,
                FixedProfile(150), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(H2 => 1) # Quality
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
            SourceComponent(
                202,
                FixedProfile(100), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(NG => 1)
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
            SourceComponent(
                302,
                FixedProfile(50), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(NG => 1)
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
            BlendingSink(
                602,
                FixedProfile(100), # Capacity
                Dict(:price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 1, NG => 1), # upperbound
                Dict(H2 => 0) # lowerbound
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
            BlendingSink(
                702,
                FixedProfile(50), # Capacity
                Dict(:price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 1, NG => 1), # upperbound
                Dict(H2 => 0) # lowerbound
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
            SourceArea("1", "Supply 1", 10, 10, areas["1"], PressBlend(70)), # outlet pressure
            SourceArea("2", "Supply 2", 10, 10, areas["2"], PressBlend(70)),
            SourceArea("3", "Supply 3", 10, 10, areas["3"], PressBlend(70)),
            PoolingArea("4", "Blend 4", 10, 10, areas["4"], PressBlend(0), Dict(Gas => FixedProfile(0))),
            PoolingArea("5", "Blend 5", 10, 10, areas["5"], PressBlend(0), Dict(Gas => FixedProfile(0))),
            TerminalArea("6", "Terminal 6", 10, 10, areas["6"], PressBlend(30)),
            TerminalArea("7", "Terminal 7", 10, 10, areas["7"], PressBlend(30)), #inlet pressure
        ]

        # Create transmission modes
        # Note: The inlet and outlets do not affect as the trans_out are not associated to Resources
        # and the different flows are tracked by prop_source variable
        fixed_O = FixedProfile(0.0)
        
        # Dispatch with PWA
        presblend_data = PressBlendPipe(
            "Weymouth",
            80, # max_pressure
            HiGHS.Optimizer;
            FLOW = 67.5, #MSm3/d
            PIN = 189.3, #barg
            POUT = 147.5, #barg
        )

        # Dispatch with Taylor approximation
        pressure_data = PressurePipe(
            "Taylor",
            1e6;
            FLOW = 67.5, #MSm3/d
            PIN = 189.3, #barg
            POUT = 147.5, #barg
        )

        tm_14 = PipeSimple("tm_14", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_15 = PipeSimple("tm_15", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_24 = PipeSimple("tm_24", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_25 = PipeSimple("tm_25", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_34 = PipeSimple("tm_34", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_35 = PipeSimple("tm_35", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [pressure_data])
        tm_46 = PipeSimple("tm_46", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [presblend_data])
        tm_47 = PipeSimple("tm_47", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [presblend_data])
        tm_56 = PipeSimple("tm_56", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [presblend_data])
        tm_57 = PipeSimple("tm_57", Gas, Gas, Gas, fixed_O, FixedProfile(1e6), fixed_O, fixed_O, fixed_O, [presblend_data])

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

        # Generate the pwa


        case = Dict(
            :areas          => area,
            :transmission   => Array{Transmission}(transmission),
            :nodes          => Array{EMB.Node}(nodes),
            :links          => Array{Link}(links),
            :products       => products,
            :components     => components,
            :T              => T,
        )    

        return case, model
    end

    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m, nlp_constraints = true)

    #_______TEST: Optimal solution_______#
    println(termination_status(m))
    @test termination_status(m) == MOI.OPTIMAL
    
    #_______PRINT: Results_______#
    @info "FLOW:"
    @info filter(:y => x -> x > 0, df_variable(m, :trans_in))
    @info "Inlet pressures"
    @info filter(:y => x -> x > 0, df_variable(m, :p_in))
    @info "Outlet pressures"
    @info df_variable(m, :p_out)
    @info "Proportion H2"
    @info df_variable(m, :prop_track)
    @info "Has Flow"
    @info df_variable(m, :has_flow)
    @info "Lower_pressure_into_node"
    @info df_variable(m, :lower_pressure_into_node)
end

@testitem "Generation of PressBlendPipe" setup=[MyTests] begin
	
	# 3 points is not enough to generate a PWA
	@test_throws Exception PressBlendPipe(
		"Weymouth",
		80, # max_pressure
		HiGHS.Optimizer,
        FLOW = 67.5, #MSm3/d
        PIN = 189.3, #barg
        POUT = 147.5, #barg
		pin = [50, 63, 70], 
   		pout = [30, 43, 50],
    	h2_fraction = [0.0, 0.05, 0.1],
		M1 = 16.042,
		M2 = 2.016
	)

	presblend_data = PressBlendPipe(
		"Weymouth",
		80, # max_pressure
		HiGHS.Optimizer,
        FLOW = 67.5, #MSm3/d
        PIN = 189.3, #barg
        POUT = 147.5, #barg
		M1 = 16.042,
		M2 = 2.016
	)

	pwa = EMP.get_pwa(presblend_data)
	@test isa(pwa, PiecewiseAffineApprox.PWAFunc)

	EMP.delete_cache()
end

@testitem "Testing Get and Read" setup=[MyTests] begin

    FLOW = 67.5 #MSm3/d
    PIN = 189.3 #barg
    POUT = 147.5 #barg    
    pin = [50,  58, 58, 63, 65, 67, 70] 
    pout = [30, 35, 37, 43, 45, 40, 50]
    h2_fraction = [0.0,  0.1, 0.0, 0.05, 0.0, 0.05, 0.1]
	M_ch4 = 16.042 # molecular weight
	M_h2 = 2.016

    weymouth = EMP.weymouth_constant(FLOW, PIN, POUT)
    z = EMP.weymouth_specgrav.(weymouth, pin, pout, h2_fraction, M_ch4, M_h2)
    
	pwa1 = approx(
		FunctionEvaluations(collect(zip(pin, pout, h2_fraction)), z),
		Concave(),
		Cluster(
			; optimizer = HiGHS.Optimizer,
			planes = 10,
			strict = :none,
			metric = :l1,
		))

	fn = EMP.get_input_fn([weymouth, pin, pout, h2_fraction], z)
	EMP.write_to_json(fn, pwa1)

	fn1 = EMP.get_input_fn([weymouth, pin, pout, h2_fraction], z)
	@test isfile(fn1)
	@test EMP.read_from_json(fn1) !== nothing
end

@testitem "Testing No Saving and Get" setup=[MyTests] begin
	M_ch4 = 16.042 # molecular weight
	M_h2 = 2.016

	FLOW = 67.5 #MSm3/d
    PIN = 189.3 #barg
    POUT = 147.5 #barg
    pin = [50,  58, 58, 63, 65, 67, 70] 
    pout = [30, 36, 37, 43, 45, 41, 50]
    h2_fraction = [0.0,  0.1, 0.0, 0.05, 0.0, 0.05, 0.1]
    
    weymouth = EMP.weymouth_constant(FLOW, PIN, POUT)

    z = EMP.weymouth_specgrav.(weymouth, pin, pout, h2_fraction, M_ch4, M_h2)

	pwa = approx(
		FunctionEvaluations(collect(zip(pin, pout, h2_fraction)), z),
		Concave(),
		Cluster(
			; optimizer = HiGHS.Optimizer,
			planes = 10,
			strict = :none,
			metric = :l1,
		))

	fn = EMP.get_input_fn([weymouth, pin, pout, h2_fraction], z)
	@test isfile(fn) == false # despite generating pwa, it is not saved so no file is found

	EMP.delete_cache()
end





# include("case1.jl")
# include("case2.jl")
# include("case3.jl")
# include("test_scratch.jl")

# @run_all_tests