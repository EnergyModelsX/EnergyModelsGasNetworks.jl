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

function generate_case()
    # Define reasources
    H2 = ResourceComponent("H2", 1.0)
    CH4 = ResourceComponent("CH4", 1.0)
    Gas = ResourceBlend("Gas", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Gas, H2, CH4]

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
        RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
        RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
        RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
        RefBlend(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(CH4 => 1, H2 => 1), Dict(Gas => 1)),
        RefSink(
            5,
            FixedProfile(500),
            Dict(:surplus => FixedProfile(-120), :deficit=> FixedProfile(1e6)), 
            Dict(Gas => 1),
            [RefBlendData{ResourceComponent{Float64}}(Gas, Dict(H2=>0.1, CH4=>1.0), Dict(H2=>0.0, CH4=>0.0))])
    ]
    # links = [
    #     CapDirect(14, nodes[1], nodes[4], Linear(), FixedProfile(200)),
    #     CapDirect(24, nodes[2], nodes[4], Linear(), FixedProfile(200)),
    #     CapDirect(34, nodes[3], nodes[4], Linear(), FixedProfile(200)),
    #     CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(700)),
    # ]
    links = [
        Direct(14, nodes[1], nodes[4], Linear()),
        Direct(24, nodes[2], nodes[4], Linear()),
        Direct(34, nodes[3], nodes[4], Linear()),
        Direct(45, nodes[4], nodes[5], Linear()),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )
    return case, model
end

case, model = generate_case()
m = EMP.create_model(case, model; check_timeprofiles=true)

nl_solver = optimizer_with_attributes(Ipopt.Optimizer, MOI.Silent() => true, "sb" => "yes")
mip_optimizer = optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true)
minlp_optimizer = optimizer_with_attributes(Juniper.Optimizer, MOI.Silent() => true, "mip_solver" => mip_optimizer, "nl_solver" => nl_solver)
optimizer = optimizer_with_attributes(
    Alpine.Optimizer,
    "nlp_solver" => nl_solver,
    "mip_solver" => mip_optimizer,
    "minlp_solver" => minlp_optimizer,
    "rel_gap" => 20.00
)

set_optimizer(m, optimizer)
set_optimizer(m, Xpress.Optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)
