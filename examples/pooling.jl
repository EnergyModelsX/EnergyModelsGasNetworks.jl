using Pkg
# Activate the local environment including EnergyModelsBase, EnergyModelsPooling, HiGHS, Alpine, Ipopt, JuMP
Pkg.activate(joinpath(@__DIR__))
using HiGHS, Alpine, Ipopt, Juniper, Xpress # TODO: Remove Xpress
using JuMP
using EnergyModelsBase
Pkg.develop(path=joinpath(@__DIR__,".."));
using EnergyModelsPooling
using TimeStruct
using PrettyTables
Pkg.instantiate()

const EMB = EnergyModelsBase
const EMP = EnergyModelsPooling
const TS = TimeStruct

"""
    generate_pooling_case()

Generate the case and model for the pooling case.
The system has two gas resources of type `ResourceCarrier` and one `ResourcePooling{ResourceCarrier}` to activate pooling constraints.
The network consists of four sources, two pooling nodes and two sinks.
"""
function generate_pooling_case()
    @info "Generate case data - Pooling Case"

    # Define the resources in the system and their emission intensity.
    # The resources `CH4` and `H2` are defined as `ResourceCarrier`, the resource `Gas` as `ResourcePooling{ResourceCarrier}`
    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Gas = ResourcePooling("Gas", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Gas, H2, CH4]

    # Creation of the time structure using TimeStruct
    op_duration = 1
    op_number = 1
    operational_periods = TS.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TS.TwoLevel(1, 1, operational_periods; op_per_strat)

    # Create the individual nodes, corresponding to a system of three sources (two `CH4`, one `H3`), one pooling node and two sinks.
    nodes = [
        RefSource(
            "source_h2_1",      # Node 1 - H2 source
            FixedProfile(200),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(10),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(H2 => 1)),     # Output from the node, in this case, H2
        RefSource(
            "source_ch4_1",     # Node 2 - CH4 source
            FixedProfile(200),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(10),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1)),    # Output from the node, in this case, CH4
        RefSource(
            "source_ch4_2",     # Node 3 - CH4 source
            FixedProfile(400),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(15),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1)),    # Output from the node, in this case, CH4
        RefSource(
            "source_h2_2",      # Node 4 - H2 source
            FixedProfile(400),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(10),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(H2 => 1)),     # Output from the node, in this case, H2
        PoolingNode(
            "pooling_1",                # Node 5 - Pooling node
            FixedProfile(1e6),          # Maximum volumetric flow rate allowed through the pooling node
            FixedProfile(0),            # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),            # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1, H2 => 1),    # Allowed input resources to pool together
            Dict(Gas => 1),             # Resulting resource from the pooling node
        ),
        PoolingNode(
            "pooling_2",                # Node 6 - Pooling node
            FixedProfile(1e6),          # Maximum volumetric flow rate allowed through the pooling node
            FixedProfile(0),            # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),            # Fixed €/(MSm3/d)/a
            Dict(Gas => 1, H2 => 1),  # Allowed input resources to pool together
            Dict(Gas => 1),             # Resulting resource from the pooling node
        ),
        RefSink(
            "sink_1",                           # Node 7 - Sink node
            FixedProfile(500),                  # Required demand in MSm3/d
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(300)), # Surplus and deficit penalty for the node in €/(MSm3/d)
            Dict(Gas => 1),                     # Demanded resource and its corresponding coefficient for the node
            [
                RefBlendData(
                    Gas,                        # `ResourcePooling`
                    Dict(H2=>0.07, CH4=>1.0),   # Maximum allowed pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                    Dict(H2=>0.0, CH4=>0.0))    # Minimum required pooling shares of the subresources of the `ResourcePooling` (volumetric %)
            ]),
        RefSink(
            "sink_2",                           # Node 8 - Sink node
            FixedProfile(300),                  # Required demand in MSm3/d
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(300)), # Surplus and deficit penalty for the node in €/(MSm3/d)
            Dict(Gas => 1),                     # Demanded resource and its corresponding coefficient for the node
            [
                RefBlendData(
                    Gas,                        # `ResourcePooling`
                    Dict(H2=>0.05, CH4=>1.0),   # Maximum allowed pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                    Dict(H2=>0.0, CH4=>0.0))    # Minimum required pooling shares of the subresources of the `ResourcePooling` (volumetric %)
            ]),
    ]

    # Connect all nodes
    # `Direct` and `CapDirect`. links can be used. The latter allows to set a maximum capacity for the link.
    links = [
        Direct("source_1_pool_1", nodes[1], nodes[5], Linear()),
        Direct("source_2_pool_1", nodes[2], nodes[5], Linear()),
        Direct("source_3_pool_1", nodes[3], nodes[5], Linear()),
        Direct("source_4_pool_2", nodes[4], nodes[6], Linear()),
        Direct("pool_1_pool_2", nodes[5], nodes[6], Linear()),
        Direct("pool_1_sink_2", nodes[5], nodes[8], Linear()),
        Direct("pool_2_sink_1", nodes[6], nodes[7], Linear()),
    ]

    # Input data structure
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )
    return case, model
end

# Generate the case and model
case, model = generate_pooling_case()

# Set the optimizer, in this example,  we use Alpine to deal with the binary products of the blending constraints
"""
    define_optimizer(mip_solver)

Define the optimizer with Alpine, Juniper and Ipopt to solve the pooling example.
The `mip_solver` can be HiGHS or the desired MIP solver.
"""
function define_optimizer(mip_solver)
    nl_solver = optimizer_with_attributes(Ipopt.Optimizer, MOI.Silent() => true, "sb" => "yes")
    minlp_optimizer = optimizer_with_attributes(
        Juniper.Optimizer,
        MOI.Silent() => true,
        "mip_solver" => mip_solver,
        "nl_solver" => nl_solver,
    )
    optimizer = optimizer_with_attributes(
        Alpine.Optimizer,
        "nlp_solver" => nl_solver,
        "mip_solver" => mip_solver,
        "minlp_solver" => minlp_optimizer,
        "rel_gap" => 0.01,
        "presolve_bt" => false,
        "time_limit" => 300,
    )
    return optimizer
end

optimizer = define_optimizer(optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true))
m = create_model(case, model; check_timeprofiles = true)
set_optimizer(m, optimizer)
optimize!(m)

"""
    process_pooling_results(m, case)

Function for processing the results to be represented in a table.
"""
function process_pooling_results(m, case)
    # Extract data from the case
    nodes = get_nodes(case)
    links = get_links(case)
    resources = get_products(case)
    Gas = first(filter(p -> p.id == "Gas", resources))
    H2 = first(filter(p -> p.id == "H2", resources))
    CH4 = first(filter(p -> p.id == "CH4", resources))
    T = get_time_struct(case)

    # Get the flow through the links
    link_flows = JuMP.Containers.rowtable(
        value,
        m[:link_in][:, :, :],
        header=[:link, :time, :product, :flow]
    )

    # Get the proportions of H2 and CH4 in the nodes
    node_h2_proportions = JuMP.Containers.rowtable(
        value,
        m[:proportion_track][:, :, H2],
        header=[:node, :time, :proportion]
    )
    node_ch4_proportions = JuMP.Containers.rowtable(
        value,
        m[:proportion_track][:, :, CH4],
        header=[:node, :time, :proportion]
    )

    # Get the delivered flows of Gas to the sinks
    sink_1 = first(filter(n -> n.id == "sink_1", nodes))
    sink_2 = first(filter(n -> n.id == "sink_2", nodes))
    gas_delivered_sink_1 = JuMP.Containers.rowtable(
        value,
        m[:flow_in][sink_1, :, :],
        header=[:node, :time, :flow]
    )
    gas_delivered_sink_2 = JuMP.Containers.rowtable(
        value,
        m[:flow_in][sink_2, :, :],
        header=[:node, :time, :flow]
    )
    gas_delivered = [(
        t = repr(con_1.time),
        gas_delivered_sink_1 = round(con_1.flow; digits=1),
        gas_delivered_sink_2 = round(con_2.flow; digits=1),
    ) for (con_1, con_2) in zip(gas_delivered_sink_1, gas_delivered_sink_2)
    ]

    return link_flows, node_h2_proportions, node_ch4_proportions, gas_delivered
end

link_flows, node_h2_proportions, node_ch4_proportions, gas_delivered = process_pooling_results(m, case)

# @info(
#     ""
# )
@info ("Delivered flow of Gas to the sinks")
pretty_table(gas_delivered)
@info("Flows through the links")
pretty_table(link_flows)
@info("Proportion of H2 in the nodes")
pretty_table(node_h2_proportions)
@info("Proportion of CH4 in the nodes")
pretty_table(node_ch4_proportions)