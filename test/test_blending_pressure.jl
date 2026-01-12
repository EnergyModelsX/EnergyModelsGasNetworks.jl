function generate_case_blending_pressure(;
    max_h2 = 0.05,
    min_h2 = 0.0,
    cost_s3 = 5,
    cost_h2 = 10,
)
    # Define reasources
    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4]

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
            1,
            FixedProfile(2000),
            FixedProfile(cost_h2),
            FixedProfile(0),
            Dict(H2 => 1),
            [MaxPressureData(FixedProfile(200))],
        ),
        RefSource(
            2,
            FixedProfile(5000),
            FixedProfile(10),
            FixedProfile(0),
            Dict(CH4 => 1),
            [MaxPressureData(FixedProfile(200))],
        ),
        RefSource(
            3,
            FixedProfile(2000),
            FixedProfile(cost_s3),
            FixedProfile(0),
            Dict(CH4 => 1),
            [MaxPressureData(FixedProfile(200))],
        ),
        PoolingNode(
            4,
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1, H2 => 1),
            Dict(Blend => 1),
            [MaxPressureData(FixedProfile(180))],
        ),
        RefSink(
            5,
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
    ]

    links = [
        CapDirect(
            14,
            nodes[1],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ), # NOT SURE WHY I HAVE TO LIMIT THE outlet pressure in links to avoid weird behaviours
        CapDirect(
            24,
            nodes[2],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            34,
            nodes[3],
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
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )

    m = EMP.create_model(case, model, mip_optimizer; check_timeprofiles = true)
    set_optimizer(m, optimizer)
    optimize!(m)

    return case, model, m
end

# Run case
case, model, m = generate_case_blending_pressure(; max_h2 = 0.0, min_h2 = 0.00)

# # Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

H2 = first(filter(p -> p.id == "H2", 𝒫))
CH4 = first(filter(p -> p.id == "CH4", 𝒫))
Blend = first(filter(p -> p.id == "Blend", 𝒫))
@testset "Basic case - results" begin
    @test JuMP.termination_status(m) in [MOI.OPTIMAL, MOI.OTHER_LIMIT]

    @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 0
    @test value(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 20.108 rtol = 0.06
    @test value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) ≈ 42.71 atol = 1e-1
    @test value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 62.82 rtol = 0.02
    @test value(m[:proportion_track][𝒩[5], first(collect(𝒯)), H2]) ≈ 0.0
    @test value(m[:proportion_track][𝒩[5], first(collect(𝒯)), CH4]) ≈ 1.0
end

@testset "Basic case - approximation" begin
    pressure_data = first(filter(data -> data isa PressureLinkData, ℒ[end].data))
    blend_data = first(filter(data -> data isa BlendLinkData, ℒ[end].data))
    pwa = EMP.get_pwa(pressure_data, blend_data, mip_optimizer)

    pin = value(m[:link_potential_in][ℒ[end], first(collect(𝒯)), Blend])
    pout = value(m[:link_potential_out][ℒ[end], first(collect(𝒯)), Blend])
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

    # Test the propagation of quality constraints towards link_in of hydrogen
    n = 𝒩[5]
    blend_data = EnergyModelsPooling.get_blenddata(n)
    data = first(blend_data)
    t = first(collect(𝒯))
    source_h2 = 𝒩[1]
    @test (
              EnergyModelsPooling.get_source_prop(source_h2, H2) -
              EnergyModelsPooling.get_max_proportion(data, H2)
          ) * value.(m[:proportion_source][𝒩[4], source_h2, t]) *
          m[:link_in][ℒ[4], t, Blend] == 0 # the quality of H2 reaching node_5 should be 0
    @test value(m[:link_in][ℒ[1], t, H2]) ==
          value.(m[:proportion_source][𝒩[4], source_h2, t]) *
          value.(m[:link_in][ℒ[4], t, Blend]) # the flow of hydrogen should be equal to the proportion reaching node_4 times the total flow into/out node_4
end

case, model, m = generate_case_blending_pressure(; max_h2 = 0.1, min_h2 = 0.00, cost_s3 = 5)

# # Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

H2 = first(filter(p -> p.id == "H2", 𝒫))
CH4 = first(filter(p -> p.id == "CH4", 𝒫))
Blend = first(filter(p -> p.id == "Blend", 𝒫))
@testset "0.1% H2 case - results" begin
    @test JuMP.termination_status(m) in [MOI.OPTIMAL, MOI.OTHER_LIMIT]

    @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 6.50 atol = 1e-1
    @test value(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 15.841 rtol = 0.06
    @test value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) ≈ 42.67 atol = 1e-1
    @test value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 65.0 rtol = 0.05
    @test value(m[:proportion_track][𝒩[5], first(collect(𝒯)), H2]) ≈ 0.1
    @test value(m[:proportion_track][𝒩[5], first(collect(𝒯)), CH4]) ≈ 0.90
end

@testset "0.1% H2 case - approximation" begin
    pressure_data = first(filter(data -> data isa PressureLinkData, ℒ[end].data))
    blend_data = first(filter(data -> data isa BlendLinkData, ℒ[end].data))
    pwa = EMP.get_pwa(pressure_data, blend_data, mip_optimizer)

    pin = value(m[:link_potential_in][ℒ[end], first(collect(𝒯)), Blend])
    pout = value(m[:link_potential_out][ℒ[end], first(collect(𝒯)), Blend])
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

# @testset "Quality constraints" begin

#     CO2, Blend, H2, CH4 = 𝒫

#     nodes = [
#         RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#         RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         PoolingNode(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1)),
#         RefSink(
#             5,
#             FixedProfile(500),
#             Dict(:surplus => FixedProfile(-120), :deficit=> FixedProfile(1e6)), 
#             Dict(Gas => 1),
#             [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.1, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))])
#     ]
#     links = [
#             Direct(14, nodes[1], nodes[4], Linear()),
#             Direct(24, nodes[2], nodes[4], Linear()),
#             Direct(34, nodes[3], nodes[4], Linear()),
#             Direct(45, nodes[4], nodes[5], Linear()),
#         ]
#     case = Case(𝒯, 𝒫, [nodes, links], [[get_nodes, get_links]])

#     m = EMP.create_model(case, model; check_timeprofiles=true)
#     set_optimizer(m, Xpress.Optimizer)
#     optimize!(m)

#     @test JuMP.termination_status(m) == MOI.OPTIMAL
#     @test value(m[:proportion_source][nodes[5], nodes[1], first(collect(𝒯))]) <= 0.1

#     nodes = [
#     RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#     RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#     RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#     PoolingNode(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1),
#         [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.05, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))]),
#     RefSink(
#         5,
#         FixedProfile(500),
#         Dict(:surplus => FixedProfile(-120), :deficit=> FixedProfile(1e6)), 
#         Dict(Gas => 1),
#         [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.1, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))])
#     ]
#     links = [
#             Direct(14, nodes[1], nodes[4], Linear()),
#             Direct(24, nodes[2], nodes[4], Linear()),
#             Direct(34, nodes[3], nodes[4], Linear()),
#             Direct(45, nodes[4], nodes[5], Linear()),
#         ]
#     case = Case(𝒯, 𝒫, [nodes, links], [[get_nodes, get_links]])

#     m = EMP.create_model(case, model; check_timeprofiles=true)
#     set_optimizer(m, Xpress.Optimizer)
#     optimize!(m)

#     @test value(m[:proportion_source][nodes[4], nodes[1], first(collect(𝒯))]) <= 0.05
#     @test value(m[:proportion_source][nodes[5], nodes[1], first(collect(𝒯))]) <= 0.05

#     nodes = [
#     RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#     RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#     RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#     PoolingNode(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1),
#         [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.1, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))]),
#     RefSink(
#         5,
#         FixedProfile(500),
#         Dict(:surplus => FixedProfile(-120), :deficit=> FixedProfile(1e6)), 
#         Dict(Gas => 1),
#         [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.05, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))])
#     ]
#     links = [
#             Direct(14, nodes[1], nodes[4], Linear()),
#             Direct(24, nodes[2], nodes[4], Linear()),
#             Direct(34, nodes[3], nodes[4], Linear()),
#             Direct(45, nodes[4], nodes[5], Linear()),
#         ]
#     case = Case(𝒯, 𝒫, [nodes, links], [[get_nodes, get_links]])

#     m = EMP.create_model(case, model; check_timeprofiles=true)
#     set_optimizer(m, Xpress.Optimizer)
#     optimize!(m)

#     @test value(m[:proportion_source][nodes[4], nodes[1], first(collect(𝒯))]) <= 0.05
#     @test value(m[:proportion_source][nodes[5], nodes[1], first(collect(𝒯))]) <= 0.05

# end

# @testset "Capacity Links" begin
#     nodes = [
#         RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#         RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         PoolingNode(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1)),
#         RefSink(
#             5,
#             FixedProfile(500),
#             Dict(:surplus => FixedProfile(-120), :deficit=> FixedProfile(1e6)), 
#             Dict(Gas => 1),
#             [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.2, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))])
#     ]
#     links = [
#             CapDirect(14, nodes[1], nodes[4], Linear(), FixedProfile(100)),
#             Direct(24, nodes[2], nodes[4], Linear()),
#             Direct(34, nodes[3], nodes[4], Linear()),
#             Direct(45, nodes[4], nodes[5], Linear()),
#         ]
#     case = Case(𝒯, 𝒫, [nodes, links], [[get_nodes, get_links]])

#     m = EMP.create_model(case, model; check_timeprofiles=true)
#     set_optimizer(m, Xpress.Optimizer)
#     optimize!(m)

# end

# @testset "PoolingNode + Component" begin
#     nodes = [
#         RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#         RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefSource(4, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#         PoolingNode(5, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1)),
#         PoolingNode(6, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(Gas => 1, H2 => 1), Dict(Gas => 1)),
#         RefSink(
#             7,
#             FixedProfile(500),
#             Dict(:surplus => FixedProfile(-120), :deficit=> FixedProfile(1e6)), 
#             Dict(Gas => 1),
#             [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.2, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))])
#     ]
#     links = [
#             CapDirect(15, nodes[1], nodes[5], Linear(), FixedProfile(100)),
#             Direct(25, nodes[2], nodes[5], Linear()),
#             Direct(35, nodes[3], nodes[5], Linear()),
#             Direct(46, nodes[4], nodes[6], Linear()),
#             Direct(56, nodes[5], nodes[6], Linear()),
#             Direct(67, nodes[6], nodes[7], Linear()),
#         ]
#     case = Case(𝒯, 𝒫, [nodes, links], [[get_nodes, get_links]])

#     m = EMP.create_model(case, model; check_timeprofiles=true)
#     set_optimizer(m, Xpress.Optimizer)
#     optimize!(m)
# end
