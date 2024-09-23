using Pkg
Pkg.instantiate()

using Revise
using EnergyModelsPooling

# Import required packages
using EnergyModelsBase
using EnergyModelsGeography
using JuMP
using Xpress
using QuadraticToBinary
using TimeStruct
const EMB = EnergyModelsBase
const EMG = EnergyModelsGeography
const EMP = EnergyModelsPooling

function generate_example_data()
    @info "Generate case data - Simple network with 6 regions with different technologies"

    # 1. Define the different products and components
    Sulfur     = ResourceComponent("Sulfur")
    components = [Sulfur]

    NG         = ResourceCarrier("NG", 0.2)
    H2         = ResourceCarrier("H2", 0)
    CO2        = ResourceEmit("CO2", 1)
    NG_H2      = ResourceBlend("NG_H2", [NG, H2])
    products   = [NG, H2, CO2, NG_H2]

    # 1.2. Define the energy EnergyContent
    e = RefEnergyContent(Dict(NG => 10, H2 => 50)) # energy content transformation

    # 2. Time structure
    op_duration = 1
    op_number = 24
    operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TwoLevel(4, 1, operational_periods; op_per_strat)

    # 3. Creation of the model
    model = OperationalModel(
        Dict(
            CO2 => StrategicProfile([160, 140, 120, 100]), # t/strategic_periods
        ),
        Dict(
            CO2 => FixedProfile(0), # EUR/t
        ),
        CO2,
    )

    # 4. Create input data for the individual areas/subsystems
    areas_id    = [1, 2, 3, 4]
    mc_scale    = Dict(1=>2.0, 2=>2.0, 3=>1.5, 4=>0.5)

    node3_demand = [OperationalProfile(vec([10 10 10 10 35 40 45 45 50 50 60 60 50 45 45 40 35 40 45 40 35 30 30 30]));
                    OperationalProfile(vec([20 20 20 20 25 30 35 35 40 40 40 40 40 35 35 30 25 30 35 30 25 20 20 20]));
                    OperationalProfile(vec([20 20 20 20 25 30 35 35 40 40 40 40 40 35 35 30 25 30 35 30 25 20 20 20]));
                    OperationalProfile(vec([20 20 20 20 25 30 35 35 40 40 40 40 40 35 35 30 25 30 35 30 25 20 20 20]));
    ]
    d_standard = OperationalProfile(vec([20 20 20 20 25 30 35 35 40 40 40 40 40 35 35 30 25 30 35 30 25 20 20 20]))
    node4_demand = [d_standard; d_standard; d_standard; d_standard]

    demand = Dict(1=>false, 2=>false, 3=>node3_demand, 4=>node4_demand)
    d_standard = OperationalProfile(vec([20 20 20 20 25 30 35 35 40 40 40 40 40 35 35 30 25 30 35 30 25 20 20 20]))

    # Create  areas with index according to the input array
    an      = Dict()
    nodes   = []
    links   = []
    
    for a_id in areas_id[1]
        j = a_id * 100
        area_nodes = [
            GeoAvailability(j+1, products),
            RefSourceComponent(
                j+2,
                FixedProfile(1e12),             # Capacity in MW
                FixedProfile(30*mc_scale[1]),   # Variable OPEX in EUR/MW
                FixedProfile(0),                # Fixed OPEX in EUR/24h 
                Dict(NG => 1),                  # Output from the Node
                Dict(Sulfur => 0.02)            # Quality of the component in the product
            ),
            RefSource(                          # For sources without needing to check components
                j+3,
                FixedProfile(1e12),             # Capacity in MW
                FixedProfile(10*mc_scale[1]),   # Variable OPEX in EUR/MW
                FixedProfile(0),                # Fixed OPEX in EUR/24h 
                Dict(H2 => 1),                  # Output from the Node
            ),
            RefBlending(
                j+4,
                FixedProfile(600),              # Blending capacity in MWh
                FixedProfile(9.1),              # Blending variable OPEX for the rate in EUR/t
                FixedProfile(0),                # Bleding fixed OPEX for the rate in EUR/(t/h 24h)
                Dict(NG => 1, H2 => 1),         # Input resource with input ratio
                Dict(NG_H2 => 1),               # Output from the node with output ratio
            )
        ]
        append!(nodes, area_nodes)

        area_links = [
            Direct(j+10, area_nodes[4], area_nodes[1], Linear()),
            Direct(j+11, area_nodes[2], area_nodes[4], Linear()),
            Direct(j+13, area_nodes[3], area_nodes[4], Linear())
        ]
        append!(links, area_links)

        # Add area node (GeoAvailability) for each subsystem
        an[a_id] = area_nodes[1]
    end

    for a_id in areas_id[2]
        j = a_id * 100
        area_nodes = [
            GeoAvailability(j+1, products),
            RefSourceComponent(
                j+2,
                FixedProfile(1e12),             # Capacity in MW
                FixedProfile(30*mc_scale[1]),   # Variable OPEX in EUR/MW
                FixedProfile(0),                # Fixed OPEX in EUR/24h 
                Dict(NG => 1),                  # Output from the Node
                Dict(Sulfur => 0.01)            # Quality of the component in the product
            ),
            RefBlending(
                j+3,
                FixedProfile(600),              # Blending capacity in MWh
                FixedProfile(9.1),              # Blending variable OPEX for the rate in EUR/t
                FixedProfile(0),                # Bleding fixed OPEX for the rate in EUR/(t/h 24h)
                Dict(NG => 1, NG_H2 => 1),      # Input resource with input ratio
                Dict(NG_H2 => 1),               # Output from the node with output ratio
            ),
        ]
        append!(nodes, area_nodes)

        area_links = [
            Direct(j+10, area_nodes[1], area_nodes[3], Linear()),
            Direct(j+11, area_nodes[3], area_nodes[1], Linear()),
            Direct(j+12, area_nodes[2], area_nodes[3], Linear()),
        ]
        append!(links, area_links)

        # Add area node (GeoAvailability) for each subsystem
        an[a_id] = area_nodes[1]
    end
    # Create terminal nodes
    for a_id in areas_id[3:4]
        j = a_id * 100
        area_nodes = [
            GeoAvailability(j+1, products),
            RefBlendingSink(
                j+2,
                StrategicProfile(demand[a_id]),                                     # Demand in MW
                Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e6)),   # Penalty
                Dict(NG_H2 => 1),                                                   # Input to the Node
                Dict(NG => 1, H2 => 0.02),                                          # Proportion product bounds
                Dict(Sulfur => 0.02)                                                # Quality component bounds
                ),
        ]
        append!(nodes, area_nodes)

        area_links = [
            Direct(j+10, area_nodes[1], area_nodes[2], Linear()),
        ]
        append!(links, area_links)

        # Add area node (GeoAvailability) for each subsystem
        an[a_id] = area_nodes[1]
    end

    # 5. Create the individual areas
    areas = [
        RefArea(1, "Supply 1", 10.751, 59.921, an[1]),
        RefArea(2, "Pool 1",   10.398, 63.436, an[2]),
        RefArea(3, "Demand 1", 7.984,  58.146, an[3]),
        RefArea(4, "Demand 2", 8.614,  56.359, an[4]),
    ]

    # 6. Create the individual transmission modes to transport the energy between the areas
    cap_ng = FixedProfile(100.0)    # Capacity of NG transport in MW
    loss = FixedProfile(0.05)       # Relative loss of transport mode
    opex_var = FixedProfile(0.05)   # Variable OPEX in EUR/MWh
    opex_fix = FixedProfile(0.05)   # Fixed OPEX in EUR/24h

    ## ONLY ALLOWED TO CONNECT AREAS WITH BLENDS WITH PIPELINESIMPLE
    NG_Pipe_12 = PipeSimple("PipeLine_12", NG_H2, NG_H2, NG_H2, FixedProfile(0), cap_ng, loss, opex_var, opex_fix, 1, Data[])
    NG_Pipe_23 = PipeSimple("PipeLine_23", NG_H2, NG_H2, NG_H2, FixedProfile(0), cap_ng, loss, opex_var, opex_fix, 1, Data[])
    NG_Pipe_24 = PipeSimple("PipeLine_24", NG_H2, NG_H2, NG_H2, FixedProfile(0), cap_ng, loss, opex_var, opex_fix, 1, Data[])
    # NG_PipeLinepack_35 = PipeLinepackSimple("PipeLinepack_35", NG, NG, NG, FixedProfile(0), cap_ng, loss, opex_var, opex_fix, 0.2, 1, Data[])
    # NG_PipeLinepack_36 = PipeLinepackSimple("PipeLinepack_36", NG, NG, NG, FixedProfile(0), cap_ng, loss, opex_var, opex_fix, 0.2, 1, Data[])
    # NG_PipeLinepack_45 = PipeLinepackSimple("PipeLinepack_45", NG, NG, NG, FixedProfile(0), cap_ng, loss, opex_var, opex_fix, 0.2, 1, Data[])
    # NG_PipeLinepack_46 = PipeLinepackSimple("PipeLinepack_46", NG, NG, NG, FixedProfile(0), cap_ng, loss, opex_var, opex_fix, 0.2, 1, Data[])


    # 7. Create the different transmission corridors between the individual areas
    transmission = [
        Transmission(areas[1], areas[2], [NG_Pipe_12]),
        Transmission(areas[2], areas[3], [NG_Pipe_23]),
        Transmission(areas[2], areas[4], [NG_Pipe_24]),
    ]

    # 8. Generate data structure/dictionary
    case = Dict(
        :areas          => Array{Area}(areas),
        :transmission   => Array{Transmission}(transmission),
        :nodes          => Array{EMB.Node}(nodes),
        :links          => Array{Link}(links),
        :products       => products,
        :components     => components,
        :T              => T,
        :e              => e,
    )
    return case, model
end
case, model = generate_example_data()
m = Model(()->QuadraticToBinary.Optimizer{Float64}(
    MOI.instantiate(Xpress.Optimizer, with_bridge_type = Float64)))
m = EMP.create_model(case, model, m; check_timeprofiles=true)
optimize!(m)
solution_summary(m)


# auxiliary code
# blend_node = case[:nodes][4]
# m[:flow_in][blend_node, :, :]
# m[:flow_out][blend_node, :, :]

𝒜 = case[:areas]
links = case[:links]
ℒᵗʳᵃⁿˢ = case[:transmission]
𝒫 = case[:products]
𝒯 = case[:T]

area = case[:areas][1]
nodesinarea = EMG.getnodesinarea(area, links)
blendnodes = EMB.nodes_sub(convert(Vector{EMB.Node}, nodesinarea), EnergyModelsPooling.Blending)
b_n = blendnodes[1]


# Function to write all constraints to a file
function write_constraints_to_file(model::Model, filename::String)
    open(filename, "w") do file
        for T in JuMP.list_of_constraint_types(model)
            cs = all_constraints(model, T...)
            println(file, T)
            println(file, "\n", cs)
        end
    end
end

# Write the constraints to a text file
write_constraints_to_file(m, "/Users/raquelalonso/Documents/code/dev_EnergyModelsPooling.jl/constraints.txt") 

function check_variable_bounds(model, filename)
    open(filename, "w") do file
        for var in all_variables(model)
            lb = has_lower_bound(var) ? has_lower_bound(var) : "No lower bound"
            ub = has_upper_bound(var) ? has_upper_bound(var) : "No upper bound"
            println(file, "Variable $var: Lower bound = $lb, Upper bound = $ub")
        end
    end
end

# Check variable bounds before optimization
check_variable_bounds(m, "/Users/raquelalonso/Documents/code/dev_EnergyModelsPooling.jl/checkbounds.txt")