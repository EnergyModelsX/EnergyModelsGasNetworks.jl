using Pkg
Pkg.instantiate()

using Revise
using EnergyModelsPooling

# Import required packages
using EnergyModelsBase
using EnergyModelsGeography
using JuMP
using Xpress
using Alpine
using DataFrames
using TimeStruct
const EMB = EnergyModelsBase
const EMG = EnergyModelsGeography
const EMP = EnergyModelsPooling

function generate_example_data()
    @info "Generate case data - Simple network with 6 regions with different technologies"

    # 1. Define the different products and components
    den         = ResourceComponent("den")
    bnz         = ResourceComponent("bnz")
    roz         = ResourceComponent("roz")
    moz         = ResourceComponent("moz")

    NG         = ResourceCarrier("NG", 0.0)
    CO2        = ResourceEmit("CO2", 1.0)
    products   = [NG, CO2]

    # 1.2. Define the energy EnergyContent. Set to nothing when the demand is not in energy units but in flow of ResourceBlend.
    e = RefEnergyContent(Dict(NG => 10)) # energy content transformation
    e = nothing

    # 2. Time structure
    op_duration = 1
    op_number = 1
    operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TwoLevel(1, 1, operational_periods; op_per_strat)

    # 3. Creation of the model
    model = OperationalModel(
        Dict(
            CO2 => StrategicProfile([160.0]), # t/strategic_periods
        ),
        Dict(
            CO2 => FixedProfile(0), # EUR/t
        ),
        CO2,
    )

    # 4. Create input data for the individual areas/subsystems
    areas_id    = [1, 2, 3, 4, 5, 6, 7, 8]

    # Create  areas with index according to the input array
    an      = Dict()
    nodes   = []
    links   = []
    
    # Source 1
    n_node = 1
    j = areas_id[n_node] * 100
    area_nodes = [
        GeoAvailability(j+1, products),
        RefSourceComponent(
            j+2,
            FixedProfile(6097.56),              # Capacity in flow
            FixedProfile(49.2),                # Variable OPEX in EUR/flowunit
            FixedProfile(0.0),                # Fixed OPEX in EUR/24h
            Dict(NG=>1.0),                    # Output flow
            Dict(den => 0.82, bnz => 3, roz => 99.2, moz => 90.5),      # Quality
        ),
    ]
    append!(nodes, area_nodes)

    area_links = [
        Direct(j+10, area_nodes[2], area_nodes[1], Linear()),
    ]
    append!(links, area_links)

    # Add area node (GeoAvailability) for each subsystem
    an[areas_id[n_node]] = area_nodes[1]

    # Source 2
    n_node = 2
    j = areas_id[n_node] * 100
    area_nodes = [
        GeoAvailability(j+1, products),
        RefSourceComponent(
            j+2,
            FixedProfile(16129),               # Capacity in flow
            FixedProfile(62.0),                # Variable OPEX in EUR/flowunit
            FixedProfile(0.0),                # Fixed OPEX in EUR/24h 
            Dict(NG=>1.0),                    # Output flow
            Dict(den => 0.62, bnz => 0, roz => 87.9, moz => 83.5),      # Quality
        ),
    ]
    append!(nodes, area_nodes)

    area_links = [
        Direct(j+10, area_nodes[2], area_nodes[1], Linear()),
    ]
    append!(links, area_links)

    # Add area node (GeoAvailability) for each subsystem
    an[areas_id[n_node]] = area_nodes[1]
    
    # Source 3
    n_node = 3
    j = areas_id[3] * 100
    area_nodes = [
        GeoAvailability(j+1, products),
        RefSourceComponent(
            j+2,
            FixedProfile(500),               # Capacity in flow
            FixedProfile(300.0),                # Variable OPEX in EUR/flowunit
            FixedProfile(0.0),                # Fixed OPEX in EUR/24h 
            Dict(NG=>1.0),                    # Output flow
            Dict(den => 0.75, bnz => 0, roz => 114, moz => 98.7),                 # Quality
        ),                                                                          
    ]
    append!(nodes, area_nodes)

    area_links = [
        Direct(j+10, area_nodes[2], area_nodes[1], Linear()),
    ]
    append!(links, area_links)

    # Add area node (GeoAvailability) for each subsystem
    an[areas_id[n_node]] = area_nodes[1]

    # Pooling 4
    n_node = 4
    j = areas_id[4] * 100
    area_nodes = [
        BlendAvailability(j+1, [NG], [NG]),
        RefBlending(
            j+2,
            FixedProfile(1250.0),
            FixedProfile(0.0),
            FixedProfile(0.0),                                                          
            Dict(NG => 1.0),                                                             
            Dict(NG => 1.0),                                                                 
            ),
    ]
    append!(nodes, area_nodes)

    area_links = [
        Direct(j+10, area_nodes[1], area_nodes[2], Linear()),
        Direct(j+20, area_nodes[2], area_nodes[1], Linear()),

    ]
    append!(links, area_links)

    # Add area node (GeoAvailability) for each subsystem
    an[areas_id[n_node]] = area_nodes[1]

    # Pooling 5
    n_node = 5
    j = areas_id[4] * 100
    area_nodes = [
        BlendAvailability(j+1, [NG], [NG]),
        RefBlending(
            j+2,
            FixedProfile(1750.0),
            FixedProfile(0.0),
            FixedProfile(0.0),                                                          
            Dict(NG => 1.0),                                                             
            Dict(NG => 1.0),                                                                 
            ),
    ]
    append!(nodes, area_nodes)

    area_links = [
        Direct(j+10, area_nodes[1], area_nodes[2], Linear()),
        Direct(j+20, area_nodes[2], area_nodes[1], Linear()),

    ]
    append!(links, area_links)

    # Add area node (GeoAvailability) for each subsystem
    an[areas_id[n_node]] = area_nodes[1]

    # Demand 6
    n_node = 6
    j = areas_id[n_node] * 100
    area_nodes = [
        GeoAvailability(j+1, products),
        RefBlendingSink(
            j+2,
            FixedProfile(500),                                                               # Demand in flow
            Dict(:surplus => FixedProfile(1e6), :deficit => FixedProfile(1e6)),
            Dict(NG=>1.0),                                                                      # Output flow                                                           
            Dict(den => 0.79),                                                                           # Quality component upper bounds
            Dict(den => 0.74, roz => 95, moz =>85)                                           # Quality component lower bounds
            ),
    ]
    append!(nodes, area_nodes)

    area_links = [
        Direct(j+10, area_nodes[1], area_nodes[2], Linear()),
    ]
    append!(links, area_links)

    # Add area node (GeoAvailability) for each subsystem
    an[areas_id[n_node]] = area_nodes[1]

     # Demand 7
     n_node = 7
     j = areas_id[n_node] * 100
     area_nodes = [
         GeoAvailability(j+1, products),
         RefBlendingSink(
            j+2,
            FixedProfile(500),                                                               # Demand in flow
            Dict(:surplus => FixedProfile(-230), :deficit => FixedProfile(1.0e6)),              # Penalty                                                            
            Dict(NG => 1.0),                                                                   # inputs
            Dict(den => 0.79, bnz => 0.9),                                                               # Quality component upper bounds
            Dict(den => 0.74, roz => 96, moz =>88)                                           # Quality component lower bounds                                                                     # Quality
            ),
     ]
     append!(nodes, area_nodes)
 
     area_links = [
         Direct(j+10, area_nodes[1], area_nodes[2], Linear()),
     ]
     append!(links, area_links)
 
     # Add area node (GeoAvailability) for each subsystem
     an[areas_id[n_node]] = area_nodes[1]

    # Demand 8
    n_node = 8
    j = areas_id[n_node] * 100
    area_nodes = [
        GeoAvailability(j+1, products),
        RefBlendingSink(
           j+2,
           FixedProfile(500),                                                               # Demand in flow
           Dict(:surplus => FixedProfile(-230), :deficit => FixedProfile(1.0e6)),              # Penalty                                                            
           Dict(NG => 1.0),                                                                   # inputs
           Dict(den => 0.79),                                                                           # Quality component upper bounds
           Dict(den => 0.74, roz => 95,)                                           # Quality component lower bounds
           ),
    ]
    append!(nodes, area_nodes)

    area_links = [
        Direct(j+10, area_nodes[1], area_nodes[2], Linear()),
    ]
    append!(links, area_links)

    # Add area node (GeoAvailability) for each subsystem
    an[areas_id[n_node]] = area_nodes[1]
    
    # 5. Create the individual areas
    areas = [
        RefArea(1, "Supply 1",          10.751, 59.921, an[1]),
        RefArea(2, "Supply 2",          10.398, 63.436, an[2]),
        RefArea(3, "Supply 3",          10.751, 59.921, an[3]),
        BlendArea(4, "Pooling 1",       10.751, 59.921, an[4]),
        BlendArea(5, "Pooling 2",       10.751, 59.921, an[5]),
        TerminalArea(6, "Terminal 1",      10.751, 59.921, an[6]),
        TerminalArea(7, "Terminal 2",      10.751, 59.921, an[7]),
        TerminalArea(8, "Terminal 3",      10.751, 59.921, an[8]),

    ]

    # 6. Create the individual transmission modes to transport the gas between the areas
    cap_ng = FixedProfile(1e6)    # Capacity of NG transport in MW
    loss = FixedProfile(0.00)       # Relative loss of transport mode
    opex_var = FixedProfile(0.0)   # Variable OPEX in EUR/MWh
    opex_fix = FixedProfile(0.0)   # Fixed OPEX in EUR/24h

    ## ONLY ALLOWED TO CONNECT AREAS WITH BLENDS WITH PIPELINESIMPLE
    NG_Pipe_14 = PipeSimple("PipeLine_14", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(0.0), opex_fix, 1, Data[])
    NG_Pipe_15 = PipeSimple("PipeLine_15", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(0.0), opex_fix, 1, Data[])
    NG_Pipe_17 = PipeSimple("PipeLine_17", NG, NG, NG, FixedProfile(0.0), FixedProfile(750), loss, FixedProfile(-230.0), opex_fix, 1, Data[])
    
    NG_Pipe_26 = PipeSimple("PipeLine_26", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-190.0), opex_fix, 1, Data[])
    NG_Pipe_24 = PipeSimple("PipeLine_24", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(0.0), opex_fix, 1, Data[])
    NG_Pipe_25 = PipeSimple("PipeLine_25", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(0.0), opex_fix, 1, Data[])
    NG_Pipe_28 = PipeSimple("PipeLine_28", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-150.0), opex_fix, 1, Data[])
    
    NG_Pipe_34 = PipeSimple("PipeLine_34", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(0.0), opex_fix, 1, Data[])
    NG_Pipe_35 = PipeSimple("PipeLine_35", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(0.0), opex_fix, 1, Data[])
    NG_Pipe_36 = PipeSimple("PipeLine_36", NG, NG, NG, FixedProfile(0.0), FixedProfile(750), loss, FixedProfile(-190.0), opex_fix, 1, Data[])


    NG_Pipe_46 = PipeSimple("PipeLine_46", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-190.0), opex_fix, 1, Data[])
    NG_Pipe_47 = PipeSimple("PipeLine_47", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-230.0), opex_fix, 1, Data[])
    NG_Pipe_48 = PipeSimple("PipeLine_48", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-150.0), opex_fix, 1, Data[])
    
    NG_Pipe_56 = PipeSimple("PipeLine_56", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-190.0), opex_fix, 1, Data[])
    NG_Pipe_57 = PipeSimple("PipeLine_57", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-230.0), opex_fix, 1, Data[])
    NG_Pipe_58 = PipeSimple("PipeLine_58", NG, NG, NG, FixedProfile(0.0), cap_ng, loss, FixedProfile(-150.0), opex_fix, 1, Data[])


    # 7. Create the different transmission corridors between the individual areas
    transmission = [
        Transmission(areas[1], areas[4], [NG_Pipe_14]),
        Transmission(areas[1], areas[5], [NG_Pipe_15]),
        Transmission(areas[1], areas[7], [NG_Pipe_17]),
        Transmission(areas[2], areas[4], [NG_Pipe_24]),
        Transmission(areas[2], areas[5], [NG_Pipe_25]),
        Transmission(areas[2], areas[6], [NG_Pipe_26]),
        Transmission(areas[2], areas[8], [NG_Pipe_28]),
        Transmission(areas[3], areas[4], [NG_Pipe_34]),
        Transmission(areas[3], areas[5], [NG_Pipe_35]),
        Transmission(areas[3], areas[6], [NG_Pipe_36]),
        Transmission(areas[4], areas[6], [NG_Pipe_46]),
        Transmission(areas[4], areas[7], [NG_Pipe_47]),
        Transmission(areas[4], areas[8], [NG_Pipe_48]),
        Transmission(areas[5], areas[6], [NG_Pipe_56]),
        Transmission(areas[5], areas[7], [NG_Pipe_57]),
        Transmission(areas[5], areas[8], [NG_Pipe_58]),
    ]

    # 8. Generate data structure/dictionary
    case = Dict(
        :areas          => Array{Area}(areas),
        :transmission   => Array{Transmission}(transmission),
        :nodes          => Array{EMB.Node}(nodes),
        :links          => Array{Link}(links),
        :products       => products,
        :T              => T,
        :e              => e,
    )
    return case, model
end

case, model = generate_example_data()

nl_solver = optimizer_with_attributes(
        Xpress.Optimizer, MOI.Silent() => true
    )
mip_solver = optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true)
m = JuMP.Model(
    optimizer_with_attributes(
        Alpine.Optimizer,
        "nlp_solver" => nl_solver,
        "mip_solver" => mip_solver,
))

m = EMP.create_model(case, model, m; check_timeprofiles=true)
optimize!(m)
solution_summary(m)

# Write the constraints to a text file
write_constraints_to_file(m, "/Users/raquelalonso/Documents/Development/dev_EnergyModelsPooling.jl/constraints.txt") 

# Results
variables = [:opex_var, :stor_charge_invest_b, :stor_charge_add, :moving, :location, :stor_level, :stor_charge_use, :stor_discharge_use]

var = :flow_out
show_variable(m, var)

for var in variables
    println(var)
    df = df_variable(m, var)
    df = df_structs_to_strings!(df)
    save_df_to_excel(file_path, df, string(var))
end
