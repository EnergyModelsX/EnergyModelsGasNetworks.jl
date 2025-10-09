using EnergyModelsBase, EnergyModelsPooling
using TimeStruct

using JuMP

using Alpine
using Ipopt
using Juniper 
using Xpress

using Test

const EMB = EnergyModelsBase
const EMP = EnergyModelsPooling

function generate_case(; max_h2 = 0.05, min_h2 = 0.0)
    # Define reasources
    H2 = ResourcePotential("H2", 1.0)
    CH4 = ResourcePotential("CH4", 1.0)
    Blend = ResourceBlend("Blend", [H2, CH4])
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
        Dict( CO2 => StrategicProfile([0])),
        Dict( CO2 => FixedProfile(0)),
        CO2)


    # Nodes
    nodes = [
        RefSource(1, FixedProfile(2000), FixedProfile(10), FixedProfile(0), Dict(H2 => 1), [MaxPressureData(FixedProfile(200))]),
        RefSource(2, FixedProfile(5000), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1), [MaxPressureData(FixedProfile(200))]),
        RefSource(3, FixedProfile(2000), FixedProfile(5), FixedProfile(0), Dict(CH4 => 1), [MaxPressureData(FixedProfile(200))]),
        RefBlend(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Blend => 1), [MaxPressureData(FixedProfile(180))]),
        RefSink(
            5,
            FixedProfile(0),
            Dict(:surplus => FixedProfile(-120), :deficit=> FixedProfile(1e6)), 
            Dict(Blend => 1),
            [RefBlendData{ResourcePotential{Float64}}(Blend, Dict(H2=>max_h2, CH4=>1.0), Dict(H2=>min_h2, CH4=>0.0)),
            MinPressureData(FixedProfile(130))])
    ]

    links = [
        CapDirect(14, nodes[1], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(130))]),
        CapDirect(24, nodes[2], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(130))]),
        CapDirect(34, nodes[3], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(130))]),
        CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(1200), 
            [PressureLinkData(0.24, 180, 130),
            MinPressureData(FixedProfile(130)),
            BlendLinkData(Blend, Dict{ResourcePotential{Float64}, Float64}(H2=>2.016), 0.1, 0.0, Dict{ResourcePotential{Float64}, Float64}(CH4=>16.04))]),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )

    
    nl_solver = optimizer_with_attributes(Ipopt.Optimizer, MOI.Silent() => true, "sb" => "yes")
    mip_optimizer = optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true)
    minlp_optimizer = optimizer_with_attributes(Juniper.Optimizer, MOI.Silent() => true, "mip_solver" => mip_optimizer, "nl_solver" => nl_solver)
    optimizer = optimizer_with_attributes(
        Alpine.Optimizer,
        "nlp_solver" => nl_solver,
        "mip_solver" => mip_optimizer,
        "minlp_solver" => minlp_optimizer,
        "rel_gap" => 1.00
        )
        
    m = EMP.create_model(case, model, Xpress.Optimizer; check_timeprofiles=true) # TODO: Change management of optimizer in the model. Discuss best approach.
    set_optimizer(m, optimizer)
    # set_optimizer(m, Xpress.Optimizer)
    optimize!(m)

    return case, model, m
end

case, model, m = generate_case(;max_h2=0.0, min_h2=0.00)



# @testset "Basic case - results" begin
#     # # Extract data from the case
#     𝒩 = get_nodes(case)
#     ℒ = get_links(case)
#     𝒫 = get_products(case)
#     𝒯 = get_time_struct(case)
#     H2 = first(filter(p -> p.id == "H2", 𝒫))
#     CH4 = first(filter(p -> p.id == "CH4", 𝒫))
#     Blend = first(filter(p -> p.id == "Blend", 𝒫))

#     @test JuMP.termination_status(m) == MOI.OPTIMAL
#     @test isapprox(objective_value(m), - 42.1 * 10 - 200 * 10 - 600 * 10 + (842.1 - 500) * 120; atol=1)
    
#     @test isapprox(value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]), 42.1; atol=1e-1)
#     @test value(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) == 200
#     @test value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) == 600
#     @test isapprox(value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]), 842.1; atol=1e-1)

#     @test value(m[:proportion_track][𝒩[5], first(collect(𝒯)), H2]) == 0.05
# end

# @testset "Weymouth equation - pwa" begin
    
# end

# @testset "Quality constraints" begin

#     CO2, Blend, H2, CH4 = 𝒫

#     nodes = [
#         RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#         RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefBlend(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1)),
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
#     RefBlend(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1),
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
#     RefBlend(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1),
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
#         RefBlend(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1)),
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

# @testset "RefBlend + Component" begin
#     nodes = [
#         RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#         RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
#         RefSource(4, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
#         RefBlend(5, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1)),
#         RefBlend(6, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(Gas => 1, H2 => 1), Dict(Gas => 1)),
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