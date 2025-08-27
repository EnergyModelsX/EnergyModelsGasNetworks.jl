"""
    PressureData to apply to Nodes and Links in a gas network.
    For Source, Availability and Compressor nodes, the pressure chosen applies to the outlet potential.
    For Sink nodes, the pressure chosen applies to the inlet potential.
"""
abstract type PressureData <: EMB.ExtensionData end

"""
    Reference PressureData that can be applied to Nodes and Links
"""
abstract type RefPressureData <: PressureData end

"""
    PressureData specific for Links
"""
abstract type LinkPressureData <: PressureData end

"""
    FixPressureData

    Used to define a fixed pressure in Nodes or Links
"""
struct FixPressureData <: RefPressureData
    pressure::TimeProfile
end

"""
    MaxPressureData

    Used to define a fixed maximum pressure in Nodes or Links
"""
struct MaxPressureData <: RefPressureData
    pressure::TimeProfile
end

"""
    MinPressureData

    Used to define a fixed minimum pressure in Nodes or Links
"""
struct MinPressureData <: RefPressureData
    pressure::TimeProfile
end

"""
    PressureLinkData <: LinkPressureData

Data for Links necessary to model the flow-pressure behaviour.

# Fields
- **`weymouth::Real`** actual weymouth constant value of the line (pipe)
- **`max_potential::Real`** is the maximum inlet pressure of the link, used to calculate the approximations.
- **`min_potential::Real`** is the minimum inlet pressure of the link, used to calculate the approximations.
"""
struct PressureLinkData <: LinkPressureData
    weymouth::Real
    max_potential::Real
    min_potential::Real
end

function pressure(n::EMB.Node)
    data = first(filter(data -> data isa RefPressureData, n.data))
    return data.pressure
end
pressure(n::EMB.Node, t) = pressure(n)[t]
pressure(data::PressureData, t) = data.pressure[t]

weymouth_constant(data::PressureLinkData) = data.weymouth
potential_data(data::PressureLinkData) = (data.min_potential, data.max_potential)

get_pressuredata(n::EMB.Node) = filter(data -> data isa PressureData, n.data)
get_pressuredata(n::EMB.Availability) = ExtensionData[]
get_pressuredata(l::Link) = filter(data -> data isa PressureData, l.data)

# struct PressurePipe <: PressureData
#     id::Any
#     max_pressure::Int
#     weymouth::Float64  # Weymouth constant
#     lin_pressures::Vector{Tuple{<:Real, <:Real}}
# end
# function PressurePipe(
#     id, maxpressure;
#     FLOW::Any,
#     PIN::Any,
#     POUT::Any,
# )
#     # Calculate weymouth constant
#     weymouth = FLOW^2/(PIN^2 - POUT^2)

#     # Calculate linearised pressures
#     pressures = range(PIN, POUT, length=150)
#     lin_pressures = [(PIN, p) for p in pressures[2:end]]
    
#     return PressurePipe(
#         id,
#         maxpressure,
#         weymouth,
#         lin_pressures
#     )
# end
# function PressurePipe(
#     id, max_pressure, weymouth::Float64;
#     PIN::Float64,
#     POUT::Float64
# )
#      # Calculate linearised pressures
#      pressures = range(PIN, POUT, length=150)
#      lin_pressures = [(float(PIN), p) for p in pressures[2:end]]
    
#      return PressurePipe(
#         id,
#         max_pressure,
#         weymouth,
#         lin_pressures
#     )
# end

# struct PressBlendPipe <: PressureData
#     id::Any
#     max_pressure::Int
#     weymouth::Float64   # Weymouth constant normalised with respect to specific gravity
#     pwa::Any
# end
# function PressBlendPipe(
#         id, max_pressure, optimizer; 
#         FLOW::Any, # CH4 flow in accordance with Weymouth equation for a given pressure drop
#         PIN::Any, # Inlet pressure corresponding to FLOW
#         POUT::Any, # Outlet pressure corresponding to FLOW
#         pin = 70, 
#         pout = 50,
#         prop = 0.2)
    
#     x1 = [i for i ∈ pout:1:pin]
#     x2 = [i for i ∈ pout:1:pin]
#     x3 = [j for j ∈ 0:0.01:prop]
    
#     X = calculate_X(x1, x2, x3)
#     weymouth_ct = round(weymouth_constant(FLOW, PIN, POUT), digits=4) # normalised the weymouth constant
#     z = calculate_flow.(weymouth_ct, X[:,1], X[:,2], X[:,3])

#     fn = get_input_fn([weymouth_ct, X[:,1], X[:,2], X[:,3]], z)

#     if isfile(fn)
#         pwa = read_from_json(fn)
#     else
#         pwa = approx(   
#             FunctionEvaluations(collect(zip(X[:,1], X[:,2], X[:,3])), z),
#             Concave(),
#             Cluster(
#                 ;optimizer,
#                 planes = 10,
#                 strict = :outer,
#                 metric = :l1,
#         ))
#         test_approx(pwa, constant, pin, pout, prop)
#         write_to_json(fn, pwa)
#     end
#     return PressBlendPipe(
#         id,
#         max_pressure,
#         weymouth_ct,
#         pwa
#     )
# end
# function PressBlendPipe(
#     id, max_pressure, optimizer, weymouth::Float64; pin=175, pout=145, prop=0.2)

#     x1 = [i for i ∈ pout:1:pin]
#     x2 = [i for i ∈ pout:1:pin]
#     x3 = [i for i ∈ 0.00:0.01:prop]

#     # Define points of the curve
#     X = calculate_X(x1, x2, x3)    
#     weymouth_ct = round(weymouth_constant(weymouth), digits=4) # normalise the weymouth constant
#     z = calculate_flow.(weymouth_ct, X[:,1], X[:,2], X[:,3])

#     # Generate/read the pwa
#     fn = get_input_fn([weymouth_ct,  X[:,1], X[:,2], X[:,3]], z)

#     if isfile(fn)
#         pwa = read_from_json(fn)
#     else
#         pwa = approx(
#             FunctionEvaluations(collect(zip(X[:, 1], X[:, 2], X[:, 3])), z),
#             Concave(),
#             Cluster(; optimizer, planes = 10, strict = :outer, metric = :l1))
#         test_approx(pwa, constant, pin, pout, prop)
        
#         write_to_json(fn, pwa)
#     end

#     return PressBlendPipe(
#         id,
#         max_pressure,
#         weymouth_ct,
#         pwa
#     )
# end

function get_pwa(data::PressureLinkData)
    POut, PIn = potential_data(data)
    #TODO: Finish when defining BlendData (we need the proportion)
end

# function has_pressuredata(tm::PipeMode) 
#     return any(typeof(data) <: PressureData for data ∈ tm.data)
# end 

# is_pressurepipe(data::PressureData) = false
# is_pressurepipe(data::PressurePipe) = true
# function is_pressurepipe(tm::PipeMode)
#     data = first(filter(data -> data isa PressureData, tm.data))
#     return is_pressurepipe(data)
# end

# max_pressure(data::PressureData) = data.max_pressure
# function max_pressure(tm::PipeMode)
#     if has_pressuredata(tm)
#         data = first(filter(data -> data isa PressureData, tm.data))
#         return max_pressure(data)
#     else
#         throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
#     end
# end

# weymouth_ct(data::PressureData) = data.weymouth
# function weymouth_ct(tm::PipeMode)
#     if has_pressuredata(tm)
#         data = first(filter(data -> data isa PressureData, tm.data))
#         return weymouth_ct(data)
#     else
#         throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
#     end
# end
# linearised_pressures(data::PressureData) = data.lin_pressures
# function linearised_pressures(tm::PipeMode)
#     if has_pressuredata(tm)
#         data = first(filter(data -> data isa PressureData, tm.data))
#         return linearised_pressures(data)
#     else
#         throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
#     end
# end

# get_pwa(data::PressureData) = data.pwa
# function get_pwa(tm::PipeMode)
#     if has_pressuredata(tm)
#         data = first(filter(data -> data isa PressureData, tm.data))
#         return get_pwa(data)
#     else
#         throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
#     end
# end

