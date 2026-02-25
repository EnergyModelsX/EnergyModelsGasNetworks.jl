using Pkg
# Activate the local environment including EnergyModelsBase, EnergyModelsPooling, HiGHS, Alpine, Ipopt, JuMP
Pkg.activate(joinpath(@__DIR__))
using HiGHS, Alpine, Ipopt, Juniper, Xpress # TODO: Remove Xpress
using JuMP
using EnergyModelsBase
Pkg.develop(path=joinpath(@__DIR__, ".."));
using EnergyModelsPooling
using TimeStruct
using PrettyTables
using PiecewiseAffineApprox
Pkg.instantiate()

const EMB = EnergyModelsBase
const EMP = EnergyModelsPooling
const TS = TimeStruct

"""
    generate_haverly_case()

Generate the case and model for the Haverly case. In this network, we consider both  
"""
function generate_haverly_case()
    @info "Generate case data - Haverly Case"

    # Define the resources in the system and their emission intensity.
    # The resources `CH4` and `H2` are defined as `ResourcePressure`, the resource `Gas` as `ResourcePooling{ResourcePressure}`
    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Gas = ResourcePooling("Gas", [H2, CH4])
    Power = ResourceCarrier("Power", 0.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Gas, H2, CH4, Power]

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
            [FixPressureData(FixedProfile(130))] # Fixed outlet pressure in bars
        ),     
            
        RefSource(
            "source_ch4_1",     # Node 2 - CH4 source
            FixedProfile(200),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(10),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1),    # Output from the node, in this case, CH4
            [FixPressureData(FixedProfile(130))] # Fixed outlet pressure in bars
        ),
        RefSource(
            "source_ch4_2",     # Node 3 - CH4 source
            FixedProfile(400),  # Maximum volumetric volumetric flow rate (MSm3/d)
            FixedProfile(15),   # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),    # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1),    # Output from the node, in this case, CH4
            [FixPressureData(FixedProfile(130))] # Fixed outlet pressure in bars
        ),
        PoolingNode(
            "pooling_1",                # Node 4 - Pooling node
            FixedProfile(1e6),          # Maximum volumetric flow rate allowed through the pooling node
            FixedProfile(0),            # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),            # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1, H2 => 1),    # Allowed input resources to pool together
            Dict(Gas => 1),             # Resulting resource from the pooling node
        ),
        RefSink(
            "sink_1",                           # Node 5 - Sink node
            FixedProfile(500),                  # Required demand in MSm3/d
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(300)), # Surplus and deficit penalty for the node in €/(MSm3/d)
            Dict(Gas => 1),                     # Demanded resource and its corresponding coefficient for the node
            [
                RefBlendData(
                    Gas,                        # `ResourcePooling`
                    Dict(H2=>0.07, CH4=>1.0),   # Maximum allowed pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                    Dict(H2=>0.0, CH4=>0.0)),   # Minimum required pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                MinPressureData(FixedProfile(130))            # Minimum required pressure in bars
            ]),
        RefSink(
            "sink_2",                           # Node 6 - Sink node
            FixedProfile(300),                  # Required demand in MSm3/d
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(300)), # Surplus and deficit penalty for the node in €/(MSm3/d)
            Dict(Gas => 1),                     # Demanded resource and its corresponding coefficient for the node
            [
                RefBlendData(
                    Gas,                        # `ResourcePooling`
                    Dict(H2=>0.05, CH4=>1.0),   # Maximum allowed pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                    Dict(H2=>0.0, CH4=>0.0)),    # Minimum required pooling shares of the subresources of the `ResourcePooling` (volumetric %)
                MinPressureData(FixedProfile(130)) # Minimum required pressure in bars
            ]),
        SimpleCompressor(
            "compressor_1",         # Node 7 - Compressor node for source_h2_1
            FixedProfile(1e6),      # Maximum volumetric flow rate allowed through the compressor
            FixedProfile(0),       # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),     # Fixed €/(MSm3/d)/a
            Dict(H2 => 1, Power => 1),         # Allowed input resource to the compressor
            Dict(H2 => 1),         # Resulting resource from the compressor
            FixedProfile(50)        # Maximum incremental potential of the compressor in bars
        ),
        SimpleCompressor(
            "compressor_2",         # Node 8 - Compressor node for source_ch4_1
            FixedProfile(1e6),      # Maximum volumetric flow rate allowed through the compressor
            FixedProfile(0),        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),        # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1, Power => 1),         # Allowed input resource to the compressor
            Dict(CH4 => 1),         # Resulting resource from the compressor
            FixedProfile(50)        # Maximum incremental potential of the compressor in bars
        ),
        SimpleCompressor(
            "compressor_3",         # Node 9 - Compressor node for source_ch4_2
            FixedProfile(1e6),      # Maximum volumetric flow rate allowed through the compressor
            FixedProfile(0),        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),        # Fixed €/(MSm3/d)/a
            Dict(CH4 => 1, Power => 1),         # Allowed input resource to the compressor
            Dict(CH4 => 1),         # Resulting resource from the compressor
            FixedProfile(50)        # Maximum incremental potential of the compressor in bars
        ),
        RefSource(
            "power_compressors",
            FixedProfile(1e6),      # Maximum energy input to the compressors in MWh/d
            FixedProfile(0.3),        # Variable OPEX in €/MWh
            FixedProfile(0),        # Fixed €/(MWh)/a
            Dict(Power => 1),       # Output
        )
    ]

    # Connect all nodes
    # `Direct` and `CapDirect`. links can be used. The latter allows to set a maximum capacity for the link.
    links = [
        Direct("source_1_compressor_1", nodes[1], nodes[7], Linear()),
        Direct("source_2_compressor_2", nodes[2], nodes[8], Linear()),
        Direct("source_3_compressor_3", nodes[3], nodes[9], Linear()),
        CapDirect(
            "compressor_1_pool_1", 
            nodes[7], 
            nodes[4], 
            Linear(), 
            FixedProfile(200), 
            [PressureLinkData(0.24, 180, 130)]), # (weymouth constant, maximum pressure and minimum pressure for approximation)
        CapDirect(
            "compressor_2_pool_1", 
            nodes[8], 
            nodes[4], 
            Linear(),
            FixedProfile(200), 
            [PressureLinkData(0.24, 180, 130)]), # (weymouth constant, maximum pressure and minimum pressure for approximation)
        CapDirect(
            "compressor_3_pool_1", 
            nodes[9], 
            nodes[4], 
            Linear(),
            FixedProfile(200), 
            [PressureLinkData(0.24, 180, 130)]), # (weymouth constant, maximum pressure and minimum pressure for approximation)
        CapDirect(
            "pool_1_sink_1", 
            nodes[4], 
            nodes[5], 
            Linear(), 
            FixedProfile(200),
            [
                PressureLinkData(0.24, 180, 130), # (weymouth constant, maximum pressure and minimum pressure for approximation)
                BlendLinkData(
                    Gas,
                    Dict{ResourcePressure{Float64},Float64}(H2=>2.016), # Molar mass of tracking resource
                    0.1, # Maximum proportion of the tracking resource
                    0.0, # Minimum proportion of the tracking resource
                    Dict{ResourcePressure{Float64},Float64}(CH4=>16.04), # Other resources in the blend and their molar mass
                )
            ]),
        CapDirect(
            "pool_1_sink_2", 
            nodes[4],
            nodes[6], 
            Linear(), 
            FixedProfile(200),
            [
                PressureLinkData(0.24, 180, 130), # (weymouth constant, maximum pressure and minimum pressure for approximation)
                BlendLinkData(
                    Gas,
                    Dict{ResourcePressure{Float64},Float64}(H2 => 2.016), # Molar mass of tracking resource
                    Dict{ResourcePressure{Float64},Any}(H2 => 0.0), # Molar fraction of the tracking resource when calculating the weymouth constant
                    0.1, # Maximum proportion of the tracking resource
                    0.0, # Minimum proportion of the tracking resource
                    Dict{ResourcePressure{Float64},Float64}(CH4=>16.04)) # Other resources in the blend and their molar mass
            ]),
        Direct("power_compressor_1", nodes[10], nodes[7], Linear()),
        Direct("power_compressor_2", nodes[10], nodes[8], Linear()),
        Direct("power_compressor_3", nodes[10], nodes[9], Linear()),
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
case, model = generate_haverly_case()

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
set_optimizer_pwa!(optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true))
m = create_model(case, model; check_timeprofiles = true)
set_optimizer(m, optimizer)
optimize!(m)

"""
    process_pwa_results(m, case)
"""
function process_pwa_results(m, link, prop, T, Blend)
    pressure_data = first(filter(data -> data isa PressureLinkData, link.data))
    blend_data = first(filter(data -> data isa BlendLinkData, link.data))

    track_res, molmass_track = first(blend_data.tracking_res)
    other_res, molmass_other = first(blend_data.other_res)
    track_molar_fraction = blend_data.track_molar_fraction[track_res]

    weymouth = EMP.get_weymouth(pressure_data)
    # Normalise the weymouth constant
    weymouth_ct =
        round(EMP.normalised_weymouth(blend_data, weymouth, track_molar_fraction), digits = 4)
        
    pin = value(m[:link_potential_in][link, first(collect(T)), Blend])
    pout = value(m[:link_potential_out][link, first(collect(T)), Blend])
        
    z = EMP.calculate_flow_to_approximate.(
            weymouth_ct,
            pin,
            pout,
            prop,
            molmass_other,
            molmass_track,
        )
    return z
end

"""
    process_haverly_results(m, case)

Function for processing the results to be represented in a table.
"""
function process_haverly_results(m, case)
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

    # Get nodal inlet potentials
    nodal_inlet_potentials = JuMP.Containers.rowtable(
        value,
        m[:potential_in][:, :, :],
        header=[:node, :time, :resource, :potential_in]
    )

    # Get nodal outlet potentials
    nodal_outlet_potentials = JuMP.Containers.rowtable(
        value,
        m[:potential_out][:, :, :],
        header=[:node, :time, :resource, :potential_out]
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

    # Check the PWA results for the link pool_1_sink_1 and pool_1_sink_2
    optimizer = optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true)
    link_pool_1_sink_1 = first(filter(l -> l.id == "pool_1_sink_1", links))
    link_pool_1_sink_2 = first(filter(l -> l.id == "pool_1_sink_2", links))
    node = first(filter(n -> n.id == "pooling_1", nodes))
    prop =  value(m[:proportion_track][node, first(collect(T)), H2])[1] # Proportion of H2 in the pooling node
    pwa_result_1 = process_pwa_results(m, link_pool_1_sink_1, prop, T, Gas)
    pwa_result_2 = process_pwa_results(m, link_pool_1_sink_2, prop, T, Gas)                    

    pwa_results = [
        (link = link_pool_1_sink_1.id, flow = round(value(m[:link_in][link_pool_1_sink_1, first(collect(T)), Gas]); digits = 2), pwa_result = round(pwa_result_1; digits = 2)),
        (link = link_pool_1_sink_2.id, flow = round(value(m[:link_in][link_pool_1_sink_2, first(collect(T)), Gas]); digits = 2), pwa_result = round(pwa_result_2; digits = 2))
    ]

    return link_flows, nodal_inlet_potentials, nodal_outlet_potentials, node_h2_proportions, node_ch4_proportions, gas_delivered, pwa_results
end

link_flows, nodal_inlet_potentials, nodal_outlet_potentials, node_h2_proportions, node_ch4_proportions, gas_delivered, pwa_results = process_haverly_results(m, case)

@info ("Delivered flow of Gas to the sinks")
pretty_table(gas_delivered)
@info("Flows through the links")
pretty_table(link_flows)
@info("PWA results for links between pooling and sink nodes")
pretty_table(pwa_results)
@info ("Nodal inlet potentials")
pretty_table(nodal_inlet_potentials)
@info ("Nodal outlet potentials")
pretty_table(nodal_outlet_potentials)
@info("Proportion of H2 in the nodes")
pretty_table(node_h2_proportions)
@info("Proportion of CH4 in the nodes")
pretty_table(node_ch4_proportions)