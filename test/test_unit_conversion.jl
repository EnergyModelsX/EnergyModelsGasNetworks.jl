function generate_case_pressure()
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
                FlowToEnergyData(Dict(NG => 10.3), :Sm3d, :h), # 10.3 kWh/Sm3
            ] 
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

case, model = generate_case_pressure()
m = EMB.create_model(case, model; check_timeprofiles = true)
set_optimizer(m, mip_optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

@testset "Test Unit Conversion - Flow-Pressure Results" begin
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

@testset "Test Unit Conversion - Unit Conversion Results" begin
    t = first(𝒯)
    NG = first(filter(p -> p.id == "NG", 𝒫))
    Energy = first(filter(p -> p.id == "Energy", 𝒫))
    n_conversion = first(filter(n -> n.id == "conversion", 𝒩))
    unit_data = n_conversion.data[1] # FlowToEnergyData

    Δt = EMP.get_time_factor(unit_data)
    time_factor = 1/86400 * 3600 # 1 / (number of seconds in a day (Sm3/d)) * number of seconds in an hour (hourly resolution)
    @test isapprox(Δt, time_factor; atol = 1e-6)

    volume = value(m[:flow_in][n_conversion, t, NG]) * Δt
    @test isapprox(volume, 24.5 * time_factor; atol = 1e-2)

    flow_out_energy = value(m[:flow_out][n_conversion, t, Energy])
    @test isapprox(flow_out_energy, 24.5 * time_factor * 10.3; atol = 1e-2) # volume * LHV(NG)

    n_sink = first(filter(n -> n.id == "sink_1", 𝒩))
    flow_in_sink = value(m[:flow_in][n_sink, t, Energy])
    @test isapprox(flow_in_sink, flow_out_energy; atol = 1e-2)
end