# function generate_case_direct(;
#     max_h2 = 0.05,
#     min_h2 = 0.0,
#     cost_s3 = 5,
#     cost_h2 = 10,
# )
#     # Define reasources
#     H2 = ResourcePressure("H2", 1.0)
#     CH4 = ResourcePressure("CH4", 1.0)
#     Blend = ResourcePooling("Blend", [H2, CH4])
#     CO2 = ResourceEmit("CO2", 1.0)
#     products = [CO2, Blend, H2, CH4]

#     # Time
#     op_duration = 1
#     op_number = 1
#     operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
#     op_per_strat = op_duration * op_number

#     T = TwoLevel(1, 1, operational_periods; op_per_strat)

#     # Initialise EMB model
#     model = OperationalModel(
#         Dict(CO2 => StrategicProfile([0])),
#         Dict(CO2 => FixedProfile(0)),
#         CO2)

#     # Nodes
#     nodes = [
#         RefSource(
#             1,
#             FixedProfile(5000),
#             FixedProfile(10),
#             FixedProfile(0),
#             Dict(H2 => 1),
#             [MaxPressureData(FixedProfile(200))],
#         ),
#         RefSource(
#             2,
#             FixedProfile(5000),
#             FixedProfile(10),
#             FixedProfile(0),
#             Dict(CH4 => 1),
#             [MaxPressureData(FixedProfile(200))],
#         ),
#         RefSource(
#             3,
#             FixedProfile(2000),
#             FixedProfile(20),
#             FixedProfile(0),
#             Dict(CH4 => 1),
#             [MaxPressureData(FixedProfile(200))],
#         ),
#         PoolingNode(
#             4,
#             FixedProfile(1e6),
#             FixedProfile(0),
#             FixedProfile(0),
#             Dict(CH4 => 1, H2 => 1),
#             Dict(Blend => 1),
#             [MaxPressureData(FixedProfile(180))],
#         ),
#         RefSink(
#             5,
#             FixedProfile(0),
#             Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(1e6)),
#             Dict(Blend => 1),
#             [
#                 RefBlendData{ResourcePressure{Float64}}(
#                     Blend,
#                     Dict(H2=>max_h2, CH4=>1.0),
#                     Dict(H2=>min_h2, CH4=>0.0),
#                 ),
#                 MinPressureData(FixedProfile(130))]),
#     ]

#     links = [
#         CapDirect(
#             14,
#             nodes[1],
#             nodes[4],
#             Linear(),
#             FixedProfile(200),
#             [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
#         ), # NOT SURE WHY I HAVE TO LIMIT THE outlet pressure in links to avoid weird behaviours
#         CapDirect(
#             24,
#             nodes[2],
#             nodes[4],
#             Linear(),
#             FixedProfile(200),
#             [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
#         ),
#         CapDirect(
#             34,
#             nodes[3],
#             nodes[4],
#             Linear(),
#             FixedProfile(200),
#             [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
#         ),
#         Direct(45, nodes[4], nodes[5], Linear()),
#     ]

#     case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
#     model = OperationalModel(
#         Dict(CO2 => FixedProfile(0)),
#         Dict(CO2 => FixedProfile(0)),
#         CO2,
#     )

#     m = EMP.create_model(case, model, mip_optimizer; check_timeprofiles = true)
#     set_optimizer(m, optimizer)
#     optimize!(m)

#     return case, model, m
# end

# # Run case
# case, model, m = generate_case_direct(; max_h2 = 1.0, min_h2 = 0.00)

# # # Extract data from the case
# 𝒩 = get_nodes(case)
# ℒ = get_links(case)
# 𝒫 = get_products(case)
# 𝒯 = get_time_struct(case)

# H2 = first(filter(p -> p.id == "H2", 𝒫))
# CH4 = first(filter(p -> p.id == "CH4", 𝒫))
# Blend = first(filter(p -> p.id == "Blend", 𝒫))

# @testset "Basic case - results" begin
#     @test JuMP.termination_status(m) in [MOI.OPTIMAL, MOI.OTHER_LIMIT]

#     @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 74.46 rtol = TEST_RTOL # same flow as CH4 due to weymouth value
#     @test value(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 74.46 rtol = TEST_RTOL
#     @test value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) ≈ 74.46 rtol = TEST_RTOL

#     @test value(m[:proportion_track][𝒩[5], first(collect(𝒯)), H2]) ≈ 0.33 rtol = TEST_RTOL
#     @test value(m[:proportion_track][𝒩[5], first(collect(𝒯)), CH4]) ≈ 0.66 rtol = TEST_RTOL
# end

function generate_case_direct(;
    max_h2 = 0.05,
    min_h2 = 0.0,
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
            FixedProfile(500),
            FixedProfile(10),
            FixedProfile(0),
            Dict(H2 => 1),
            [MaxPressureData(FixedProfile(180))],
        ),
        RefSource(
            2,
            FixedProfile(500),
            FixedProfile(10),
            FixedProfile(0),
            Dict(CH4 => 1),
            [MaxPressureData(FixedProfile(180))], # Limit as potential pressures in Direct links are not penalised
        ),
        PoolingNode(
            3,
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1, H2 => 1),
            Dict(Blend => 1),
            [MaxPressureData(FixedProfile(180))],
        ),
        RefSink(
            4,
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
                MinPressureData(FixedProfile(100))]),
    ]

    EMP.set_step_pressure!(5) # Pressure step for PWA approximation

    links = [
        Direct(
            14,
            nodes[1],
            nodes[3],
            Linear(),
        ),
        Direct(
            24,
            nodes[2],
            nodes[3],
            Linear(),
        ),
        CapDirect(
            34,
            nodes[3],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [
                PressureLinkData(0.24, 200, 130),
                MinPressureData(FixedProfile(1e-6)),
                BlendLinkData{ResourcePressure{Float64}}(
                    Blend,
                    Dict(H2=>2.02), #molar mass
                    Dict(H2=>0.0), #molar fraction of tracking resource
                    0.2,
                    0.0,
                    Dict(CH4=>16.04)),
            ]),
        CapDirect(
            35,
            nodes[3],
            nodes[5],
            Linear(),
            FixedProfile(200),
            [
                PressureLinkData(0.24, 200, 130),
                MinPressureData(FixedProfile(1e-6)),
                BlendLinkData{ResourcePressure{Float64}}(
                    Blend,
                    Dict(H2=>2.02), #molar mass
                    Dict(H2=>0.0), #molar fraction of tracking resource
                    0.2,
                    0.0,
                    Dict(CH4=>16.04)),
            ]),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )

    set_optimizer_pwa!(mip_optimizer)
    m = EMP.create_model(case, model; check_timeprofiles = true)
    set_optimizer(m, optimizer)
    optimize!(m)

    return case, model, m
end

# Run case
case, model, m = generate_case_direct(; max_h2 = 1.0, min_h2 = 0.00)

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

    @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 201.6 atol = 20 # same flow as CH4 due to weymouth value
    # @test value(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 0.0 rtol = 0.02 # same flow as CH4 due to weymouth value
    @test value(m[:link_in][ℒ[3], first(collect(𝒯)), Blend]) ≈ 90.6 atol = 20 # same flow as CH4 due to weymouth value
    @test value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 111.011 atol = 20 # same flow as CH4 due to weymouth value

    @test value(m[:link_potential_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 180.0 rtol = 0.02
    @test value(m[:link_potential_out][ℒ[1], first(collect(𝒯)), H2]) ≈ 180.0 rtol =
        0.02 # same as link_pot_in as flow is not impacted by drop pressure
    # @test value(m[:link_potential_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 180.0 rtol =
    #     0.02
    @test value(m[:link_potential_in][ℒ[3], first(collect(𝒯)), Blend]) ≈ 180.0 rtol =
        0.02
    @test value(m[:link_potential_out][ℒ[3], first(collect(𝒯)), Blend]) ≈ 130.0 rtol =
        0.02
    @test value(m[:link_potential_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 180.0 rtol =
        0.02
    @test value(m[:link_potential_out][ℒ[4], first(collect(𝒯)), Blend]) ≈ 100.0 rtol =
        0.02
end
