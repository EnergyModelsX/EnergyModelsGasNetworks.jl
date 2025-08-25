using Test

using Alpine
using Ipopt
using Juniper
using HiGHS
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

@testset "Only Blend" begin
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
            Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)),
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
                Dict(H2 => 1), # Quality
            ),
        ]
        l = [
            Direct(130, n[2], n[1], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["1"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 2
        n = [
            GeoAvailability(201, products),
            SourceComponent(
                202,
                FixedProfile(200), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(NG => 1),
            ),
        ]
        l = [
            Direct(210, n[2], n[1], Linear()),
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
                Dict(NG => 1),
            ),
        ]
        l = [
            Direct(310, n[2], n[1], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["3"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 4
        n = [
            GeoAvailability(401, products),
        ]
        l = [
        ]
        append!(nodes, n)
        append!(links, l)
        areas["4"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 5
        n = [
            GeoAvailability(501, products),
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
                Dict(:cap_price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 0.2, NG => 1), # upperbound
                Dict(H2 => 0, NG => 0), # lowerbound
            ),
        ]
        l = [
            Direct(610, n[1], n[2], Linear()),
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
                Dict(:cap_price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 0.2, NG => 1), # upperbound
                Dict(H2 => 0, NG => 0), # lowerbound
            ),
        ]
        l = [
            Direct(710, n[1], n[2], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["7"] = n[1] # link area with GeoAvailability node

        # Create individual Areas
        # define behaviour of the areas for only blending
        blending = EMP.Blending("blend")
        area = [
            SourceArea("1", "Supply 1", 10, 10, areas["1"], blending),
            SourceArea("2", "Supply 2", 10, 10, areas["2"], blending),
            SourceArea("3", "Supply 3", 10, 10, areas["3"], blending),
            PoolingArea("4", "Joint 4", 10, 10, areas["4"], blending),
            PoolingArea("5", "Joint 5", 10, 10, areas["5"], blending),
            TerminalArea("6", "Terminal 6", 10, 10, areas["6"], blending, nothing),
            TerminalArea("7", "Terminal 7", 10, 10, areas["7"], blending, nothing),
        ]

        # Create transmission modes
        # Note: The inlet and outlets do not affect as the trans_out are not associated to Resources
        # and the different flows are tracked by prop_source variable
        fixed_O = FixedProfile(0.0)
        tm_14 = PipeSimple(
            "tm_14",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_15 = PipeSimple(
            "tm_15",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_24 = PipeSimple(
            "tm_24",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_25 = PipeSimple(
            "tm_25",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_34 = PipeSimple(
            "tm_34",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_35 = PipeSimple(
            "tm_35",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_46 = PipeSimple(
            "tm_46",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_47 = PipeSimple(
            "tm_47",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_56 = PipeSimple(
            "tm_56",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )
        tm_57 = PipeSimple(
            "tm_57",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            1,
            Data[],
        )

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
            :areas        => area,
            :transmission => Array{Transmission}(transmission),
            :nodes        => Array{EMB.Node}(nodes),
            :links        => Array{Link}(links),
            :products     => products,
            :components   => components,
            :T            => T,
        )

        return case, model
    end

    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m, nlp_constraints = true)

    #______TEST: OBJECTIVE________
    @test termination_status(m) == MOI.OPTIMAL
    supply_node = filter(n -> n.id == 202, case[:nodes])
    @test first(value.(m[:cap_use][supply_node, :])) == 200
    supply_node = filter(n -> n.id == 302, case[:nodes])
    @test first(value.(m[:cap_use][supply_node, :])) == 50

    ℒ = case[:transmission]
    𝒯 = case[:T]
    T = collect(𝒯)
    𝒜 = case[:areas]

    a1 = 𝒜[1]
    a2 = 𝒜[2]
    a3 = 𝒜[3]
    a4 = 𝒜[4]
    a6 = 𝒜[6]

    TM_to = [tm for l ∈ ℒ for tm ∈ modes(l) if l.to == a4]
    TM_from = [tm for l ∈ ℒ for tm ∈ modes(l) if l.from == a4]

    #_______TEST: FLOW QUANTIIES________
    # Test the inflows equals the outflows through areas
    @test isapprox(sum(value.(m[:trans_out])[tm, t] for tm ∈ TM_to for t ∈ 𝒯),
        sum(value.(m[:trans_in])[tm, t] for tm ∈ TM_from for t ∈ 𝒯), atol = TEST_ATOL)

    #_______TEST: FLOW PROPORTIONS________
    source = case[:nodes][2]
    pipeline =
        first([tm for l ∈ filter(x -> x.from == a1 && x.to == a4, ℒ) for tm ∈ modes(l)])
    # Test if the proportions of flows in blending areas is correct
    @test isapprox(
        value.(m[:trans_out])[
            pipeline,
            T[1],
        ]/sum(value.(m[:trans_out])[p, T[1]] for p ∈ TM_to),
        value.(m[:prop_source][a4, source, T[1]]), atol = TEST_ATOL)

    #_______TEST: PROP H2 AT TERMINALS________
    source = case[:nodes][2]
    pipelines = [tm for l ∈ filter(x -> x.to == a6, ℒ) for tm ∈ modes(l)]
    areas = [𝒜[4], 𝒜[5]]
    sink = case[:nodes][10]

    @test sum(
        value.(m[:trans_out])[p, T[1]] * value.(m[:prop_source][areas[i], source, T[1]]) for
        (i, p) ∈ enumerate(pipelines)
    )/sum(value.(m[:trans_out])[p, T[1]] for p ∈ pipelines) <=
          EMP.get_upper(sink, case[:components][2]) + TEST_ATOL
end

@testset "Pressure + 1 Resource" begin
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
            Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)),
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
            Direct(130, n[2], n[1], Linear()),
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
            ),
        ]
        l = [
            Direct(210, n[2], n[1], Linear()),
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
            ),
        ]
        l = [
            Direct(310, n[2], n[1], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["3"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 4
        n = [
            GeoAvailability(401, products),
        ]
        l = [
        ]
        append!(nodes, n)
        append!(links, l)
        areas["4"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 5
        n = [
            GeoAvailability(501, products),
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
            ),
        ]
        l = [
            Direct(610, n[1], n[2], Linear()),
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
            ),
        ]
        l = [
            Direct(710, n[1], n[2], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["7"] = n[1] # link area with GeoAvailability node

        # Create individual Areas
        behaviour_max = EMP.Pressure("MaxPressure", EMP.PressureMaxArea(FixedProfile(200)))
        behaviour_min = EMP.Pressure("MinPressure", EMP.PressureMinArea(FixedProfile(30)))

        area = [
            SourceArea("1", "Supply 1", 10, 10, areas["1"], behaviour_max),
            SourceArea("2", "Supply 2", 10, 10, areas["2"], behaviour_max),
            SourceArea("3", "Supply 3", 10, 10, areas["3"], behaviour_max),
            PoolingArea("4", "Blend 4", 10, 10, areas["4"], behaviour_max),
            PoolingArea("5", "Blend 5", 10, 10, areas["5"], behaviour_max),
            TerminalArea("6", "Terminal 6", 10, 10, areas["6"], behaviour_min),
            TerminalArea("7", "Terminal 7", 10, 10, areas["7"], behaviour_min),
        ]

        # Create transmission modes
        # Note: The inlet and outlets do not affect as the trans_out are not associated to Resources
        # and the different flows are tracked by prop_source variable
        fixed_O = FixedProfile(0.0)
        pressure_data = PressurePipe(
            "Taylor",
            1e6; # max_pressure
            FLOW = 67.5, #MSm3/d
            PIN = 189.3, #barg
            POUT = 147.5, #barg
        )
        tm_14 = PipeSimple(
            "tm_14",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_15 = PipeSimple(
            "tm_15",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_24 = PipeSimple(
            "tm_24",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_25 = PipeSimple(
            "tm_25",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_34 = PipeSimple(
            "tm_34",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_35 = PipeSimple(
            "tm_35",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_46 = PipeSimple(
            "tm_46",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_47 = PipeSimple(
            "tm_47",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_56 = PipeSimple(
            "tm_56",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_57 = PipeSimple(
            "tm_57",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )

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
            :areas        => area,
            :transmission => Array{Transmission}(transmission),
            :nodes        => Array{EMB.Node}(nodes),
            :links        => Array{Link}(links),
            :products     => products,
            :components   => components,
            :T            => T,
            :pwa          => nothing,
        )

        return case, model
    end

    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m, nlp_constraints = false)

    #_______TEST: Optimal solution_______#
    println(termination_status(m))
    @test termination_status(m) == OPTIMAL
end

@testset "Pressure + Blend + 2 Resource" begin
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
            Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)),
            CO2)

        areas = Dict()
        nodes = []
        links = []

        # Nodes in Area 1
        n = [
            GeoAvailability(101, products),
            SourceComponent(
                102,
                FixedProfile(300), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(H2 => 1), # Quality
            ),
        ]
        l = [
            Direct(130, n[2], n[1], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["1"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 2
        n = [
            GeoAvailability(201, products),
            SourceComponent(
                202,
                FixedProfile(300), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(NG => 1),
            ),
        ]
        l = [
            Direct(210, n[2], n[1], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["2"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 3
        n = [
            GeoAvailability(301, products),
            SourceComponent(
                302,
                FixedProfile(300), # Capacity
                FixedProfile(0), # Var. OPEX
                FixedProfile(0), # Fix. OPEX
                Dict(Gas => 1), # Output
                Dict(NG => 1),
            ),
        ]
        l = [
            Direct(310, n[2], n[1], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["3"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 4
        n = [
            GeoAvailability(401, products),
        ]
        l = [
        ]
        append!(nodes, n)
        append!(links, l)
        areas["4"] = n[1] # link area with GeoAvailability node

        # Nodes in Area 5
        n = [
            GeoAvailability(501, products),
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
                Dict(:cap_price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 1, NG => 1), # upperbound
                Dict(H2 => 0), # lowerbound
            ),
        ]
        l = [
            Direct(610, n[1], n[2], Linear()),
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
                Dict(:cap_price => FixedProfile(-190)), # Penalty
                Dict(Gas => 1), # Input
                Dict(H2 => 1, NG => 1), # upperbound
                Dict(H2 => 0), # lowerbound
            ),
        ]
        l = [
            Direct(710, n[1], n[2], Linear()),
        ]
        append!(nodes, n)
        append!(links, l)
        areas["7"] = n[1] # link area with GeoAvailability node

        # Create individual Areas
        behaviour_max =
            EMP.PressBlend("MaxPressure", EMP.PressureMaxArea(FixedProfile(200)))
        behaviour_min = EMP.PressBlend("MinPressure", EMP.PressureMinArea(FixedProfile(0)))

        area = [
            SourceArea("1", "Supply 1", 10, 10, areas["1"], behaviour_max), # outlet pressure
            SourceArea("2", "Supply 2", 10, 10, areas["2"], behaviour_max),
            SourceArea("3", "Supply 3", 10, 10, areas["3"], behaviour_max),
            PoolingArea("4", "Blend 4", 10, 10, areas["4"], behaviour_max),
            PoolingArea("5", "Blend 5", 10, 10, areas["5"], behaviour_max),
            TerminalArea("6", "Terminal 6", 10, 10, areas["6"], behaviour_min),
            TerminalArea("7", "Terminal 7", 10, 10, areas["7"], behaviour_min), #inlet pressure
        ]

        # Create transmission modes
        # Note: The inlet and outlets do not affect as the trans_out are not associated to Resources
        # and the different flows are tracked by prop_source variable
        fixed_O = FixedProfile(0.0)

        # Dispatch with PWA
        @info "Calculating the PWA for pipes with 2 resources"
        presblend_data = PressBlendPipe(
            "Weymouth",
            80, # max_pressure
            HiGHS.Optimizer,
            0.2484, # weymouth
        )

        # Dispatch with Taylor approximation
        pressure_data = PressurePipe(
            "Taylor",
            1e6,
            0.2484; # weymouth
            PIN = 200.0,
            POUT = 130.0,
        )

        tm_14 = PipeSimple(
            "tm_14",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_15 = PipeSimple(
            "tm_15",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_24 = PipeSimple(
            "tm_24",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_25 = PipeSimple(
            "tm_25",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_34 = PipeSimple(
            "tm_34",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_35 = PipeSimple(
            "tm_35",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [pressure_data],
        )
        tm_46 = PipeSimple(
            "tm_46",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [presblend_data],
        )
        tm_47 = PipeSimple(
            "tm_47",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [presblend_data],
        )
        tm_56 = PipeSimple(
            "tm_56",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [presblend_data],
        )
        tm_57 = PipeSimple(
            "tm_57",
            Gas,
            Gas,
            Gas,
            fixed_O,
            FixedProfile(1e6),
            fixed_O,
            fixed_O,
            fixed_O,
            [presblend_data],
        )

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
            :areas        => area,
            :transmission => Array{Transmission}(transmission),
            :nodes        => Array{EMB.Node}(nodes),
            :links        => Array{Link}(links),
            :products     => products,
            :components   => components,
            :T            => T,
        )

        return case, model
    end

    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m, nlp_constraints = true)

    #_______TEST: Optimal solution_______#
    println(termination_status(m))
    @test termination_status(m) == MOI.OPTIMAL
end

@testset "Testing Get and Read" begin
    FLOW = 67.5 #MSm3/d
    PIN = 189.3 #barg
    POUT = 147.5 #barg    
    pin = [50, 58, 58, 63, 65, 67, 70]
    pout = [30, 35, 37, 43, 45, 40, 50]
    h2_fraction = [0.0, 0.1, 0.0, 0.05, 0.0, 0.05, 0.1]

    X = EMP.calculate_X(pin, pout, h2_fraction)
    weymouth = round(EMP.weymouth_constant(FLOW, PIN, POUT), digits = 4)
    z = EMP.calculate_flow.(weymouth, X[:, 1], X[:, 2], X[:, 3])

    fn = EMP.get_input_fn([weymouth, pin, pout, h2_fraction], z)

    pwa1 = approx(
        FunctionEvaluations(collect(zip(X[:, 1], X[:, 2], X[:, 3])), z),
        Concave(),
        Cluster(
            ; optimizer = HiGHS.Optimizer,
            planes = 10,
            strict = :outer,
            metric = :l1,
        ))

    EMP.write_to_json(fn, pwa1)

    fn1 = EMP.get_input_fn([weymouth, pin, pout, h2_fraction], z)
    @test isfile(fn1)
    @test EMP.read_from_json(fn1) !== nothing
end
