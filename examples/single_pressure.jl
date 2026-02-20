using Pkg
# Activate the local environment including EnergyModelsBase, EnergyModelsPooling, HiGHS, Alpine, Ipopt, JuMP
Pkg.activate(joinpath(@__DIR__))
using HiGHS
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
    generate_single_pressure_case()

Generate the case and model for the single pressure test.
The system only has one gas resource of type `ResourcePressure` to activate pressure-flow constraints.
The pressure-flow relationship for all pipelines are, therefore, defined by the Taylor approximation.
"""
function generate_single_pressure_case()
    @info "Generate case data - Single Gas Pressure Test"

    # Define the resources in the system and their emission intensity.
    # The resource `CH4` is defined as a `ResourcePressure` to activate the pressure-flow constraints in the model.
    CH4 = ResourcePressure("CH4", 1.0)
    CO2 = ResourceEmit("CO2", 1.0)
    Power = ResourceCarrier("Power", 1.0)
    products = [CO2, CH4, Power]

    # Creation of the time structure using TimeStruct
    op_duration = 1
    op_number = 1
    operational_periods = TS.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TS.TwoLevel(1, 1, operational_periods; op_per_strat)

    # Create the individual test nodes, corresponding to a system with three CH4 sources, three compressors, one power source (for the compressors)
    # and one sink.
    nodes = [
        RefSource(
            "source_1",                             # Node 1                    
            FixedProfile(200),                      # Maximum volumetric flow rate (MSm3/d)
            FixedProfile(15),                       # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),                        # Fixed OPEX in €/(MSm3/d)/a
            Dict(CH4 => 1),                         # Output from the node, in this case, CH4
            [FixPressureData(FixedProfile(130))],   # Fixed outlet pressure from the node. 
        ),
        RefSource(
            "source_2",                             # Node 2
            FixedProfile(200),                      # Maximum volumetric flow rate (MSm3/d)
            FixedProfile(10),                       # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),                        # Fixed OPEX in €/(MSm3/d)/a
            Dict(CH4 => 1),                         # Output from the node, in this case, CH4
            [FixPressureData(FixedProfile(130))],   # Fixed outlet pressure from the node.
        ),
        RefSource(
            "source_3",                             # Node 3
            FixedProfile(200),                      # Maximum volumetric flow rate (MSm3/d)
            FixedProfile(5),                        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),                        # Fixed OPEX in €/(MSm3/d)/a
            Dict(CH4 => 1),                         # Output from the node, in this case, CH4
            [FixPressureData(FixedProfile(130))],   # Fixed outlet pressure from the node.
        ),
        SimpleCompressor(
            "compressor_1",                         # Node 4
            FixedProfile(1e6),                      # Maximum volumetric flow rate allowed through the compressor (MSm3/d)
            FixedProfile(0),                        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),                        # Fixed OPEX in €/(MSm3/d)/a
            Dict(CH4 => 1, Power => 0.1),           # Input resources, in this case, CH4 and Power. Note that Power is the energy-related resource for the compressor
            Dict(CH4 => 1),                         # Output resources, in this case, CH4
            FixedProfile(60),                       # Maximum pressure difference allowed in the compressor, in this case, 60 bars
            [MaxPressureData(FixedProfile(190))],   # Maximum outlet pressure that the compressor can reach
        ),
        SimpleCompressor(
            "compressor_2",                        # Node 5
            FixedProfile(1e6),                      # Maximum volumetric flow rate allowed through the compressor (MSm3/d)
            FixedProfile(0),                        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),                        # Fixed OPEX in €/(MSm3/d)/a
            Dict(CH4 => 1, Power => 0.1),           # Input resources, in this case, CH4 and Power. Note that Power is the energy-related resource for the compressor
            Dict(CH4 => 1),                         # Output resources, in this case, CH4
            FixedProfile(60),                       # Maximum pressure difference allowed in the compressor, in this case, 60 bars
            [MaxPressureData(FixedProfile(190))],   # Maximum outlet pressure that the compressor can reach
        ),
        SimpleCompressor(
            "compressor_3",                         # Node 6
            FixedProfile(1e6),                      # Maximum volumetric flow rate allowed through the compressor (MSm3/d)
            FixedProfile(0),                        # Variable OPEX in €/(MSm3/d)
            FixedProfile(0),                        # Fixed OPEX in €/(MSm3/d)/a
            Dict(CH4 => 1, Power => 0.1),           # Input resources, in this case, CH4 and Power. Note that Power is the energy-related resource for the compressor
            Dict(CH4 => 1),                         # Output resources, in this case, CH4
            FixedProfile(60),                       # Maximum pressure difference allowed in the compressor, in this case, 60 bars
            [MaxPressureData(FixedProfile(190))],   # Maximum outlet pressure that the compressor can reach
        ),
        RefSource(
            "power_source",                         # Node 7
            FixedProfile(200),                      # Installed capacity in MW
            FixedProfile(2),                        # Variable OPEX in €/MWh
            FixedProfile(0),                        # Fixed OPEX in €/MWh/a
            Dict(Power => 1),                       # Output resource from the node, in this case, Power
            [FixPressureData(FixedProfile(0))],     # Fixed outlet pressure, zero is defined as we use `Direct` links which do not define flow-pressure relationships
        ),
        RefSink(
            "sink_1",                                   # Node 8                    
            FixedProfile(0),                           # Required demand in MSm3/d
            Dict(                                       # Surplus and deficit penalty for the node in €/(MSm3/d)
                :surplus => FixedProfile(-11), 
                :deficit => FixedProfile(1e6)),
            Dict(CH4 => 1),                             # Demanded resource and corresponding ratio to demand
            [                                           # Maximum and minimum inlet pressure to the sink
                MaxPressureData(FixedProfile(180)), 
                MinPressureData(FixedProfile(160))],
        ),
    ]

    # Connect all nodes
    # `Direct` links will not impose pressure-flow relationships, and will transmit presssures (i.e., link_potential_in = link_potential_out)
    # `CapDirect` links impose pressure-flow relationships and allow capacity restrictions.
    links = [                   
        Direct(
            "source_comp_1",    
            nodes[1],           
            nodes[4],
            Linear(),
        ),
        Direct(
            "source_comp_2",
            nodes[2],
            nodes[5],
            Linear(),
        ),
        Direct(
            "source_comp_2",
            nodes[3],
            nodes[6],
            Linear(),
        ),
        CapDirect(
            "comp_1_sink",
            nodes[4],
            nodes[8],
            Linear(),
            FixedProfile(50),  # Maximum volumetric capacity (MSm3/d)
            [
                PressureLinkData(0.24, 200, 0),         # (weymouth constant, maximum pressure and minimum pressure for approximation)
                MinPressureData(FixedProfile(1e-6))],   # Minimum link_potential_out
        ),
        CapDirect(
            "comp_2_sink",
            nodes[5],
            nodes[8],
            Linear(),
            FixedProfile(50),  # Maximum volumetric capacity (MSm3/d)
            [
                PressureLinkData(0.24, 200, 0),         # (weymouth constant, maximum pressure and minimum pressure for approximation)
                MinPressureData(FixedProfile(1e-6))],   # Minimum link_potential_out
        ),
        CapDirect(
            "comp_3_sink",
            nodes[6],
            nodes[8],
            Linear(),
            FixedProfile(50),  # Maximum volumetric capacity (MSm3/d)
            [
                PressureLinkData(0.24, 200, 0),         # (weymouth constant, maximum pressure and minimum pressure for approximation)
                MinPressureData(FixedProfile(1e-6))],   # Minimum link_potential_out
        ),
        Direct(
            "power_comp_1",
            nodes[7],
            nodes[4],
            Linear(),
        ),
        Direct(
            "power_comp_2",
            nodes[7],
            nodes[5],
            Linear(),
        ),
        Direct(
            "power_comp_3",
            nodes[7],
            nodes[6],
            Linear(),
        ),
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

# Set the optimizer, in this example with single gas HiGHS is enough
optimizer = optimizer_with_attributes(
    HiGHS.Optimizer,
    MOI.Silent() => true,
)
m = EMB.create_model(case, model; check_timeprofiles = true)
set_optimizer(m, optimizer)
optimize!(m)

"""
    calculate_rhs_taylor(link_p_in, link_p_out, l)

Function for calculate the right-hand side of the Taylor approximation for a given link `l` and pressures `link_p_in` and `link_p_out`.
This allows for testing the tightness of the approximation.
"""
function calculate_rhs_taylor(link_p_in, link_p_out, l)
    pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
    weymouth_ct = EMP.get_weymouth(pressure_data)
    POut, PIn = EMP.potential_data(pressure_data)

    # Determine the (p_in, p_out) points for the Taylor approximation
    pressures_points = [(PIn, p) for p ∈ range(PIn, POut, length = 150)[2:end]]

    # Create Taylor constraint for each point
    RHS_values = []
    for (p_in, p_out) ∈ pressures_points
        val_rhs =
            sqrt(weymouth_ct) * (
                (p_in/(sqrt(p_in^2 - p_out^2))) * link_p_in -
                (p_out/(sqrt(p_in^2 - p_out^2))) * link_p_out
            )
        push!(RHS_values, val_rhs)
    end
    return RHS_values
end

"""
    process_single_pressure_results(m, case)

Function for processing the results to be represented in the table afterwards.
"""
function process_single_pressure_results(m, case)
    # Extract the nodes and the TimeStruct from the case
    nodes = get_nodes(case)
    links = get_links(case)
    resources = get_products(case)
    CH4 = first(filter(r -> r.id == "CH4", resources))
    T = get_time_struct(case)

    # Extract the first operational period of the strategic period
    first_op = [first(t_inv) for t_inv ∈ strategic_periods(T)]

    # Get nodal inlet potentials
    nodal_inlet_potentials = JuMP.Containers.rowtable(
        value,
        m[:potential_in][:, :, CH4],
        header=[:node, :time, :potential_in]
    )
    # Get nodal outlet potentials
    nodal_outlet_potentials = JuMP.Containers.rowtable(
        value,
        m[:potential_out][:, :, CH4],
        header=[:node, :time, :potential_out]
    )

    # Get flows through the links
    link_flows = JuMP.Containers.rowtable(
        value,
        m[:link_in][:, :, CH4],
        header=[:link, :time, :flow]
    )

    # Dictionaries for quick lookup
    node_out = Dict((r.node, r.time) => r.potential_out for r in nodal_outlet_potentials)
    node_in  = Dict((r.node, r.time) => r.potential_in  for r in nodal_inlet_potentials)
    links_by_id = Dict(l.id => l for l in links)

    link_rhs = [begin
        l = links_by_id[getfield(row.link, :id)]  # row.link is usually the CapDirect; fallback to id if needed
        pin = node_out[(l.from, row.time)]   # outlet potential of the from-node
        pout = node_in[(l.to, row.time)]     # inlet potential of the to-node
        (
            link = l.id,
            time = row.time,
            flow = round(row.flow; digits = 2),
            rhs  = round(minimum(calculate_rhs_taylor(pin, pout, l)); digits = 2),
        )
    end for row in link_flows if row.link isa CapDirect]

    return nodal_inlet_potentials, nodal_outlet_potentials, link_flows, link_rhs
end

nodal_inlet_potentials, nodal_outlet_potentials, link_flows, link_rhs = process_single_pressure_results(m, case)


@info(
    "Results for the single pressure test case:\n" *
    "Compressors 2 and 3 are active increasing pressures from 130 to 189.78 bars" *
    "This outlet pressure is not at its maximum due to the capacity constraint of 50 MSm3/d in the links between the compressors and the sink" *
    "Only sources 2 and 3 deliver gas, as source 1 is more expensive than the reward in the sink for delivering gas."
    )
pretty_table(nodal_inlet_potentials)
pretty_table(nodal_outlet_potentials)
pretty_table(link_flows)
pretty_table(link_rhs)