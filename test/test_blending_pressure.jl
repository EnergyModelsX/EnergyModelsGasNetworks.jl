function generate_case_blending_pressure(;
    max_h2 = 0.05,
    min_h2 = 0.0,
    cost_s3 = 5,
    cost_h2 = 10)

    # Define reasources
    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    Power = ResourceCarrier("Power", 1.0)
    products = [CO2, Blend, H2, CH4, Power]

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
            "supply_h2", #1
            FixedProfile(2000),
            FixedProfile(cost_h2),
            FixedProfile(0),
            Dict(H2 => 1),
            [MaxPressureData(FixedProfile(0))],
        ),
        RefSource(
            "supply_ch4_1", #2
            FixedProfile(5000),
            FixedProfile(10),
            FixedProfile(0),
            Dict(CH4 => 1),
            [MaxPressureData(FixedProfile(0))],
        ),
        RefSource(
            "supply_ch4_2", #3
            FixedProfile(2000),
            FixedProfile(cost_s3),
            FixedProfile(0),
            Dict(CH4 => 1),
            [MaxPressureData(FixedProfile(0))],
        ),
        PoolingNode(
            "pooling_node", #4
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1, H2 => 1),
            Dict(Blend => 1),
            [MaxPressureData(FixedProfile(180))],
        ),
        RefSink(
            "sink", #5
            FixedProfile(0),
            Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(1e6)),
            Dict(Blend => 1),
            [
                RefBlendData{ResourcePressure{Float64}}(
                    Blend,
                    Dict(H2=>max_h2, CH4=>1.0),
                    Dict(H2=>min_h2, CH4=>0.0),
                ),
                MinPressureData(FixedProfile(130))]),
        RefSource(
            "supply_power", #6
            FixedProfile(1000),
            FixedProfile(0.5),
            FixedProfile(0),
            Dict(Power => 1),
        ),
        SimpleCompressor(
            "compressor_1", # 7  mn
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(H2 => 1, Power => 1.2), # linear relationship between potential increase and power consumption
            Dict(H2 => 1), # The compressor increases the potential of H2
            FixedProfile(180),
            [MaxPressureData(FixedProfile(180))],
        ),
        SimpleCompressor(
            "compressor_2", # 8
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1, Power => 1.2), # linear relationship between potential increase and power consumption
            Dict(CH4 => 1), # The compressor increases the potential of CH4
            FixedProfile(180),
            [MaxPressureData(FixedProfile(180))],
        ),
        SimpleCompressor(
            "compressor_3", # 9
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1, Power => 1.2), # linear relationship between potential increase and power consumption
            Dict(CH4 => 1), # The compressor increases the potential of CH4
            FixedProfile(180),
            [MaxPressureData(FixedProfile(180))],
        ),
    ]

    links = [
        CapDirect(
            "",
            nodes[7],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ), # NOT SURE WHY I HAVE TO LIMIT THE outlet pressure in links to avoid weird behaviours
        CapDirect(
            24,
            nodes[8],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            34,
            nodes[9],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(1200),
            [PressureLinkData(0.24, 180, 130),
                MinPressureData(FixedProfile(130)),
                BlendLinkData(
                    Blend,
                    Dict{ResourcePressure{Float64},Float64}(H2=>2.016),
                    0.1,
                    0.0,
                    Dict{ResourcePressure{Float64},Float64}(CH4=>16.04),
                )]),
        Direct("source_compressor_1", nodes[1], nodes[7], Linear()),
        Direct("source_compressor_2", nodes[2], nodes[8], Linear()),
        Direct("source_compressor_3", nodes[3], nodes[9], Linear()),
        Direct("power_compressor_1", nodes[6], nodes[7], Linear()),
        Direct("power_compressor_2", nodes[6], nodes[8], Linear()),
        Direct("power_compressor_3", nodes[6], nodes[9], Linear()),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )

    set_optimizer_pwa!(mip_optimizer)
    m = create_model(case, model; check_timeprofiles = true)
    set_optimizer(m, optimizer)
    optimize!(m)

    return case, model, m
end

# Run case
case, model, m = generate_case_blending_pressure(; max_h2 = 0.0, min_h2 = 0.00)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

H2 = first(filter(p -> p.id == "H2", 𝒫))
CH4 = first(filter(p -> p.id == "CH4", 𝒫))
Blend = first(filter(p -> p.id == "Blend", 𝒫))
@testset "Basic case - results" begin
    # @test JuMP.termination_status(m) in [MOI.OPTIMAL, MOI.OTHER_LIMIT]

    @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 0
    @test value(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 27.74 rtol = 5e-1
    @test value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) ≈ 29.98 atol = 1.0
    @test value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 55.5 rtol = 5e-1
    @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), H2]) ≈ 0.0 atol=1e-3
    @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), CH4]) ≈ 1.0 atol=1e-3
end

@testset "Basic case - approximation" begin
    pressure_data = first(filter(data -> data isa PressureLinkData, ℒ[4].data))
    blend_data = first(filter(data -> data isa BlendLinkData, ℒ[4].data))
    pwa = EMGN.get_pwa(pressure_data, blend_data, mip_optimizer)

    pin = value(m[:link_potential_in][ℒ[4], first(collect(𝒯)), Blend])
    pout = value(m[:link_potential_out][ℒ[4], first(collect(𝒯)), Blend])
    prop = 0

    # Test that the PWA bounds the flow in link_n_4-n_5
    @test isapprox(PiecewiseAffineApprox.evaluate(pwa, (pin, pout, prop)),
        value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]); atol = 1e-1)

    # Test that Taylor approximation bounds flow in link_n_3-n_4
    rhs = test_approx(0.24,
        [(200, pout) for pout ∈ range(200, 130, length = 150)[2:end]],
        value(m[:link_potential_in][ℒ[3], first(collect(𝒯)), CH4]),
        value(m[:link_potential_out][ℒ[3], first(collect(𝒯)), CH4]))
    @test isapprox(rhs, value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]); atol = 1e-1)

    #  Test that Taylor approximation bounds flow in link_n_1-n_4
    rhs =
        test_approx(0.24, [(200, pout) for pout ∈ range(200, 0, length = 150)[2:end]],
            value(m[:link_potential_in][ℒ[1], first(collect(𝒯)), H2]),
            value(m[:link_potential_out][ℒ[1], first(collect(𝒯)), H2]))
    @test_skip isapprox(rhs, value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]); atol = 1e-1)

    # Test the propagation of quality constraints: H2 proportion at PoolingNode ≈ 0
    t = first(collect(𝒯))
    @test value(m[:proportion_out][𝒩[4], t, H2]) ≈ 0.0 atol=1e-3
    @test value(m[:flow_component][ℒ[4], t, H2]) ≈
          value(m[:proportion_out][𝒩[4], t, H2]) * value(m[:link_in][ℒ[4], t, Blend]) atol=1e-2
end

case, model, m = generate_case_blending_pressure(; max_h2 = 0.1, min_h2 = 0.00, cost_s3 = 5)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

H2 = first(filter(p -> p.id == "H2", 𝒫))
CH4 = first(filter(p -> p.id == "CH4", 𝒫))
Blend = first(filter(p -> p.id == "Blend", 𝒫))
@testset "0.1% H2 case - results" begin
    # @test JuMP.termination_status(m) in [MOI.OPTIMAL, MOI.OTHER_LIMIT]

    @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 5.852 atol = 5e-1
    @test value(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 26.33 rtol = 5e-1
    @test value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) ≈ 28.43 atol = 1.0
    @test value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 58.53 rtol = 5e-1
    @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), H2]) ≈ 0.1 atol=1e-2
    @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), CH4]) ≈ 0.90 atol=1e-2
end

@testset "0.1% H2 case - approximation" begin
    pressure_data = first(filter(data -> data isa PressureLinkData, ℒ[4].data))
    blend_data = first(filter(data -> data isa BlendLinkData, ℒ[4].data))
    pwa = EMGN.get_pwa(pressure_data, blend_data, mip_optimizer)

    pin = value(m[:link_potential_in][ℒ[4], first(collect(𝒯)), Blend])
    pout = value(m[:link_potential_out][ℒ[4], first(collect(𝒯)), Blend])
    prop = 0.1

    # Test that the PWA bounds the flow in link_n_4-n_5
    @test isapprox(PiecewiseAffineApprox.evaluate(pwa, (pin, pout, prop)),
        value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]); atol = 1e-1)

    # Test that Taylor approximation bounds flow in link_n_3-n_4
    rhs = test_approx(0.24,
        [(200, pout) for pout ∈ range(200, 130, length = 150)[2:end]],
        value(m[:link_potential_in][ℒ[3], first(collect(𝒯)), CH4]),
        value(m[:link_potential_out][ℒ[3], first(collect(𝒯)), CH4]))
    @test isapprox(rhs, value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]); atol = 1e-1)

    #  Test that Taylor approximation bounds flow in link_n_1-n_4
    rhs = test_approx(0.24,
        [(200, pout) for pout ∈ range(200, 130, length = 150)[2:end]],
        value(m[:link_potential_in][ℒ[1], first(collect(𝒯)), H2]),
        value(m[:link_potential_out][ℒ[1], first(collect(𝒯)), H2]))
    @test isapprox(rhs, value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]); atol = 1e-1)
end
