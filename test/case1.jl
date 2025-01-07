
function generate_case()

    # Define resources
    NG = RefComponent("NG", 0.0)
    H2 = ComponentTrack("H2", 0.0)
    
    Gas = EMP.ResourceCarrierBlend("Gas", [NG, H2])
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
        RefSourceComponent(
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
        RefSourceComponent(
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
        RefSourceComponent(
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
        RefBlendingSink(
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
        RefBlendingSink(
            702,
            FixedProfile(50), # Capacity
            Dict(:price => FixedProfile(-190)), # Penalty
            Dict(Gas => 1), # Input
            Dict(H2 => 0.7, NG => 1), # upperbound
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
        :pwa            => nothing
    )    

    return case, model
end

@testset "Only Blend" begin
    
    case, model = generate_case()
    m = EMP.create_model(case, model)
    m = optimize(m)

    @testset "Optimal solution" begin
        println(termination_status(m))
        @test termination_status(m) == MOI.LOCALLY_SOLVED
    end

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

    @testset "Flow Quantities" begin
        # Test the inflows equals the outflows through areas
        @test isapprox(sum(value.(m[:trans_out])[tm, t] for tm ∈ TM_to for t ∈ 𝒯), 
              sum(value.(m[:trans_in])[tm, t] for tm ∈ TM_from for t ∈ 𝒯), atol=TEST_ATOL)
    end
    @testset "Flow Proportions" begin
        source = case[:nodes][2]
        pipeline = first([tm for l in filter(x -> x.from == a1 && x.to == a4, ℒ) for tm in modes(l)])
        # Test if the proportions of flows in blending areas is correct
        @test isapprox(value.(m[:trans_out])[pipeline, T[1]]/sum(value.(m[:trans_out])[p, T[1]] for p ∈ TM_to),
                  value.(m[:prop_source][a4, source, T[1]]), atol=TEST_ATOL)
    end
    @testset "Proportion H2 at Terminals" begin
        source = case[:nodes][2]
        pipelines = [tm for l in filter(x -> x.to == a6, ℒ) for tm in modes(l)]
        areas = [𝒜[4], 𝒜[5]]
        sink = case[:nodes][10]

        @test sum(value.(m[:trans_out])[p, T[1]] * value.(m[:prop_source][areas[i], source, T[1]]) for (i, p) in enumerate(pipelines))/sum(value.(m[:trans_out])[p, T[1]] for p in pipelines) <=
            EMP.get_upper(sink, case[:components][2])
    end

    @info "FLOW:"
    @info filter(:y => x -> x > 0, df_variable(m, :trans_in))
    @info "Proportion flow:"
    @info filter(:y => x -> x > 0, df_variable(m, :prop_source))
    @info "Proportion H2:"
    @info filter(:y => x -> x > 0, df_variable(m, :prop_track))

end


