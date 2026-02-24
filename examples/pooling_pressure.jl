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
    generate_pooling_pressure_case()

"""
function generate_pooling_pressure_case()
    @info "Generate case data - Pooling and Pressure Case"

    # Define the resources in the system and their emission intensity.
    # The resources `CH4` and `H2` are defined as `ResourcePressure`, the resource `Gas` as `ResourcePooling{ResourcePressure}`
    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Gas = ResourcePooling("Gas", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Gas, H2, CH4]

    # Creation of the time structure using TimeStruct
    op_duration = 1
    op_number = 1
    operational_periods = TS.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TS.TwoLevel(1, 1, operational_periods; op_per_strat)

    # Create the individual nodes
    nodes = [
        RefSource(
            "source_h2_1",      # Node 1 - H2 source
            FixedProfile(200),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(10),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(H2 => 1),      # Output from the node, in this case, H2
            [FixedPressureData(FixedProfile(130))] # Fixed outlet pressure in bars
        ),     
            
        RefSource(
            "source_ch4_1",     # Node 2 - CH4 source
            FixedProfile(200),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(10),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1),    # Output from the node, in this case, CH4
            [FixedPressureData(FixedProfile(130))] # Fixed outlet pressure in bars
        ),
        RefSource(
            "source_ch4_2",     # Node 3 - CH4 source
            FixedProfile(400),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(15),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1),    # Output from the node, in this case, CH4
            [FixedPressureData(FixedProfile(130))] # Fixed outlet pressure in bars
        ),
        RefSource(
            "source_h2_2",      # Node 4 - H2 source
            FixedProfile(400),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(10),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(H2 => 1),      # Output from the node, in this case, H2
            [FixedPressureData(FixedProfile(130))] # Fixed outlet pressure in bars
        ),
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
                    Dict(H2=>0.0, CH4=>0.0)),   # Minimum required pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                MinPressureData(130)            # Minimum required pressure in bars
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
                    Dict(H2=>0.0, CH4=>0.0)),    # Minimum required pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                MinPressureData(130) # Minimum required pressure in bars
            ]),
        SimpleCompressor(
            "compressor_1",         # Node 9 - Compressor node for source_h2_1
            FixedProfile(1e6),      # Maximum volumetric flow rate allowed through the compressor
            FixedProfile(0),       # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),     # Fixed €/(MSm3/d)/a
            Dict(H2 => 1),         # Allowed input resource to the compressor
            Dict(H2 => 1),         # Resulting resource from the compressor
            FixedProfile(50)        # Maximum incremental potential of the compressor in bars
        ),
        SimpleCompressor(
            "compressor_2",         # Node 10 - Compressor node for source_ch4_1
            FixedProfile(1e6),      # Maximum volumetric flow rate allowed through the compressor
            FixedProfile(0),        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),        # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1),         # Allowed input resource to the compressor
            Dict(CH4 => 1),         # Resulting resource from the compressor
            FixedProfile(50)        # Maximum incremental potential of the compressor in bars
        ),
        SimpleCompressor(
            "compressor_3",         # Node 11 - Compressor node for source_ch4_2
            FixedProfile(1e6),      # Maximum volumetric flow rate allowed through the compressor
            FixedProfile(0),        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),        # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1),         # Allowed input resource to the compressor
            Dict(CH4 => 1),         # Resulting resource from the compressor
            FixedProfile(50)        # Maximum incremental potential of the compressor in bars
        ),
        SimpleCompressor(
            "compressor_4",         # Node 12 - Compressor node for source_h2_2
            FixedProfile(1e6),      # Maximum volumetric flow rate allowed through the compressor
            FixedProfile(0),       # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),     # Fixed €/(MSm3/d)/a
            Dict(H2 => 1),         # Allowed input resource to the compressor
            Dict(H2 => 1),         # Resulting resource from the compressor
            FixedProfile(50)        # Maximum incremental potential of the compressor in bars
        ),        
    ]

    # Connect all nodes
    # `Direct` and `CapDirect`. links can be used. The latter allows to set a maximum capacity for the link.
    links = [
        Direct("source_1_compressor_1", nodes[1], nodes[9], Linear()),
        Direct("source_2_compressor_2", nodes[2], nodes[10], Linear()),
        Direct("source_3_compressor_3", nodes[3], nodes[11], Linear()),
        Direct("source_4_compressor_4", nodes[4], nodes[12], Linear()),
        CapDirect(
            "compressor_1_pool_1", 
            nodes[9], 
            nodes[5], 
            Linear(), 
            FixedProfile(200), 
            [PressureLinkData(0.24, 180, 130)]),
        CapDirect(
            "compressor_2_pool_1", 
            nodes[10], 
            nodes[5], 
            Linear(),
            [PressureLinkData(0.24, 180, 130)]),
        CapDirect(
            "compressor_3_pool_1", 
            nodes[11], 
            nodes[5], 
            Linear(),
            [PressureLinkData(0.24, 180, 130)]),
        CapDirect(
            "compressor_4_pool_2", 
            nodes[12], 
            nodes[6], 
            Linear(),
            [PressureLinkData(0.24, 180, 130)]),
        CapDirect(
            "pool_1_pool_2", 
            nodes[5], 
            nodes[6], 
            Linear(),
            [PressureLinkData(0.24, 180, 130)]),
        CapDirect(
            "pool_1_sink_2", 
            nodes[5],
            nodes[8], 
            Linear(), 
            [PressureLinkData(0.24, 180, 130)]),
        CapDirect(
            "pool_2_sink_1", 
            nodes[6], 
            nodes[7], 
            Linear(), 
            [PressureLinkData(0.24, 180, 130)]),
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

# Generate the case and model data and run the model
case, model = generate_single_pressure_case()

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
    process_pooling_pressure_results(m, case)

Function for processing the results to be represented in a table.
"""
function process_pooling_pressure_results(m, case)
    # Extract data from the case
    nodes = get_nodes(case)
    links = get_links(case)
    resources = get_products(case)
    Gas = first(filter(p -> p.id == "Gas", resources))
    H2 = first(filter(p -> p.id == "H2", resources))
    CH4 = first(filter(p -> p.id == "CH4", resources))
    T = get_time_structure(case)

    # Get the flow through the links
    link_flows = JuMP.Containers.rowtable(
        value,
        m[:link_in][:, :, :],
        header=[:link, :time, :product, :flow]
    )

    # Get nodal inlet potentials
    nodal_inlet_potentials = JuMP.Containers.rowtable(
        value,
        m[:potential_in][:, :, :],
        header=[:node, :time, :potential_in]
    )

    # Get nodal outlet potentials
    nodal_outlet_potentials = JuMP.Containers.rowtable(
        value,
        m[:potential_out][:, :, :],
        header=[:node, :time, :potential_out]
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

    return link_flows, nodal_inlet_potentials, nodal_outlet_potentials, node_h2_proportions, node_ch4_proportions, gas_delivered
end

link_flows, nodal_inlet_potentials, nodal_outlet_potentials, node_h2_proportions, node_ch4_proportions, gas_delivered = process_pooling_pressure_results(m, case)

@info ("Delivered flow of Gas to the sinks")
pretty_table(gas_delivered)
@info("Flows through the links")
pretty_table(link_flows)
@info ("Nodal inlet potentials")
pretty_table(nodal_inlet_potentials)
@info ("Nodal outlet potentials")
pretty_table(nodal_outlet_potentials)
@info("Proportion of H2 in the nodes")
pretty_table(node_h2_proportions)
@info("Proportion of CH4 in the nodes")
pretty_table(node_ch4_proportions)