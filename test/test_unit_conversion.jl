function generate_case_single_resource()
    # Define reasources
    NG = ResourcePressure("NG", 1.0)
    CO2 = ResourceEmit("CO2", 1.0)
    Energy = ResourceCarrier("Energy", 1.0) # kWh
    products = [CO2, NG, Energy]

    # Time
    op_duration = 1
    op_number = 1
    operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TwoLevel(1, 1, operational_periods; op_per_strat)

    # Initialise EMB model
    model = OperationalModel(
        Dict(CO2 => StrategicProfile([0])),
        Dict(CO2 => FixedProfile(0)),
        CO2)

    # Nodes
    nodes = [
        RefSource(
            "source_1",
            FixedProfile(200),
            FixedProfile(0),
            FixedProfile(0),
            Dict(NG => 1),
            [FixPressureData(FixedProfile(130))],
        ),
        RefConversion(
            "conversion",
            Dict(NG => 1),
            Dict(Energy => 1),
            [
                FlowToEnergyData(10.3) # 10.3 kWh/Sm3
            ],
        ),
        RefSink(
            "sink_1",
            FixedProfile(0),
            Dict(:surplus => FixedProfile(-1000), :deficit => FixedProfile(1e6)),
            Dict(Energy => 1),
        ),
    ]
    links = [
        CapDirect(
            "source_to_conversion",
            nodes[1],
            nodes[2],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(120))],
        ),
        Direct(
            "conversion_to_sink",
            nodes[2],
            nodes[3],
            Linear(),
        ),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )
    return case, model
end

case, model = generate_case_single_resource()
m = EMB.create_model(case, model; check_timeprofiles = true)
set_optimizer(m, mip_optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

@testset "Test Unit Conversion Single Resource - Flow-Pressure Results" begin
    t = first(𝒯)
    NG = first(filter(p -> p.id == "NG", 𝒫))

    # Check the potential values at the CapDirect link are consistent with the pressure bounds defined in the case (maximum supply possible)
    potential_in = value(m[:link_potential_in][ℒ[1], t, NG])
    potential_out = value(m[:link_potential_out][ℒ[1], t, NG])
    @test potential_in == 130
    @test potential_out == 120

    # Check the source flow is at its maximum based on the pressure bounds
    rhs = minimum(calculate_rhs_taylor(potential_in, potential_out, ℒ[1]))
    link_in = value(m[:link_in][ℒ[1], t, NG])
    @test isapprox(rhs, link_in; atol = 1e-2)
end

@testset "Test Unit Conversion Single Resource - Unit Conversion Results" begin
    t = first(𝒯)
    NG = first(filter(p -> p.id == "NG", 𝒫))
    Energy = first(filter(p -> p.id == "Energy", 𝒫))
    n_conversion = first(filter(n -> n.id == "conversion", 𝒩))
    unit_data = n_conversion.data[1] # FlowToEnergyData

    flow_in = value(m[:flow_in][n_conversion, t, NG])
    @test isapprox(flow_in, 24.5; atol = 1e-2)

    flow_out_energy = value(m[:flow_out][n_conversion, t, Energy])
    @test isapprox(flow_out_energy, 24.5 * 10.3; atol = 1e-2) # volume * LHV(NG)

    n_sink = first(filter(n -> n.id == "sink_1", 𝒩))
    flow_in_sink = value(m[:flow_in][n_sink, t, Energy])
    @test isapprox(flow_in_sink, flow_out_energy; atol = 1e-2)
end

function generate_case_pooling_resource()
    # Define reasources
    NG = ResourceCarrier("NG", 1.0)
    H2 = ResourceCarrier("H2", 1.0)
    Blend = ResourcePooling("Blend", [NG, H2])
    Energy = ResourceCarrier("Energy", 1.0) # kWh
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, NG, H2, Blend, Energy]

    # Time
    op_duration = 1
    op_number = 1
    operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TwoLevel(1, 1, operational_periods; op_per_strat)

    # Initialise EMB model
    model = OperationalModel(
        Dict(CO2 => StrategicProfile([0])),
        Dict(CO2 => FixedProfile(0)),
        CO2)

    # Nodes
    nodes = [
        RefSource(
            "source_ng",
            FixedProfile(200),
            FixedProfile(10),
            FixedProfile(0),
            Dict(NG => 1),
        ),
        RefSource(
            "source_h2",
            FixedProfile(200),
            FixedProfile(0),
            FixedProfile(0),
            Dict(H2 => 1),
        ),
        PoolingNode(
            "pooling",
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(NG => 1, H2 => 1),
            Dict(Blend => 1),
            [RefBlendData(Blend, Dict(H2 => 0.1, NG => 1.0), Dict(H2 => 0.0, NG => 0.0))], # ResourcePooling, max. proportion, min.proportion
        ),
        RefConversion(
            "conversion",
            Dict(Blend => 1),
            Dict(Energy => 1),
            [
                FlowToEnergyData(Dict(NG => 10.3, H2 => 3.5)) # LHV (kWh/Sm3)
            ],
        ),
        RefSink(
            "sink",
            FixedProfile(0),
            Dict(:surplus => FixedProfile(-100), :deficit => FixedProfile(1e6)),
            Dict(Energy => 1),
        ),
    ]
    links = [
        Direct(
            "ng_to_pooling",
            nodes[1],
            nodes[3],
            Linear(),
        ),
        Direct(
            "h2_to_pooling",
            nodes[2],
            nodes[3],
            Linear(),
        ),
        Direct(
            "pooling_to_conversion",
            nodes[3],
            nodes[4],
            Linear(),
        ),
        Direct(
            "conversion_to_sink",
            nodes[4],
            nodes[5],
            Linear(),
        ),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )
    return case, model
end

case, model = generate_case_pooling_resource()
m = EMB.create_model(case, model; check_timeprofiles = true)
set_optimizer(m, optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

@testset "Test Unit Conversion Pooling Resource - Pooling Results" begin
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    Blend = first(filter(p -> p.id == "Blend", 𝒫))

    # Check the prooportion of H2 in the pooling and conversion node is at its maximum
    n = first(filter(n -> n.id == "pooling", 𝒩))
    proportion_h2 = value(m[:proportion_track][n, first(𝒯), H2])
    @test isapprox(proportion_h2, 0.1; atol = 0.02)  # Alpine has 1% rel_gap

    n = first(filter(n -> n.id == "conversion", 𝒩))
    proportion_h2 = value(m[:proportion_track][n, first(𝒯), H2])
    flow_in = value(m[:flow_in][n, first(𝒯), Blend])
    @test isapprox(proportion_h2, 0.1; atol = 0.02)  # Alpine has 1% rel_gap
    @test isapprox(flow_in, 222.222; rtol = 0.05) # Check the flow_in to the conversion node is at the maximum capacity from the sources.
end

@testset "Test Unit Conversion Pooling Resource - Unit Conversion Results" begin
    t = first(𝒯)
    NG = first(filter(p -> p.id == "NG", 𝒫))
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    Blend = first(filter(p -> p.id == "Blend", 𝒫))
    Energy = first(filter(p -> p.id == "Energy", 𝒫))
    n_conversion = first(filter(n -> n.id == "conversion", 𝒩))
    unit_data = n_conversion.data[1] # FlowToEnergyData

    flow_in = value(m[:flow_in][n_conversion, t, Blend])
    proportion_h2 = 0.1
    proportion_ng = 0.9
    flow_out_energy = value(m[:flow_out][n_conversion, t, Energy])
    @test isapprox(
        flow_out_energy,
        flow_in * (10.3 * proportion_ng + 3.5 * proportion_h2);
        rtol = 0.02,
    ) # flow_in * low heating value

    n_sink = first(filter(n -> n.id == "sink", 𝒩))
    flow_in_sink = value(m[:flow_in][n_sink, t, Energy])
    @test isapprox(flow_in_sink, 2137.78; rtol = 0.05)  # Alpine has 1% rel_gap
end
