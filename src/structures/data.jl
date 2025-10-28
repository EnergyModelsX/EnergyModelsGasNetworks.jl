"""
    PressureData to apply to Nodes and Links in a gas network.
    For Source, Availability and Compressor nodes, the pressure chosen applies to the outlet potential.
    For Sink nodes, the pressure chosen applies to the inlet potential.
"""
abstract type PressureData <: EMB.ExtensionData end

abstract type BlendData <: EMB.ExtensionData end

"""
    Reference PressureData that can be applied to Nodes and Links
"""
abstract type AbstractPressureData <: PressureData end

"""
    PressureData specific for Links
"""
abstract type AbstractLinkPressureData <: PressureData end

"""
    FixPressureData

    Used to define a fixed pressure in Nodes or Links
"""
struct FixPressureData <: AbstractPressureData
    pressure::TimeProfile
end

"""
    MaxPressureData

    Used to define a fixed maximum pressure in Nodes or Links
"""
struct MaxPressureData <: AbstractPressureData
    pressure::TimeProfile
end

"""
    MinPressureData

    Used to define a fixed minimum pressure in Nodes or Links
"""
struct MinPressureData <: AbstractPressureData
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
struct PressureLinkData <: AbstractLinkPressureData
    weymouth::Real
    max_potential::Real
    min_potential::Real
end

"""
    RefBlendData{T<:CompoundResource} <: BlendData

Blending data for controlling the quality of Nodes.
#TODO: Create a check that guarantees that the resources in max_proportion and min_proportion are either ResourceComponent or ResourceComponentPotential.
"""
struct RefBlendData{T<:EMB.Resource} <: BlendData
    blend::ResourceBlend{T}
    max_proportion::Dict{T,Real}
    min_proportion::Dict{T,Real}
end
RefBlendData(
    blend::ResourceBlend{T},
    max_proportion::Dict{T,<:Real},
    min_proportion::Dict{T,<:Real}) where {T<:EMB.Resource} =
    RefBlendData{T}(blend, max_proportion, min_proportion)

"""
    BlendLinkData{T<:CompoundResource} <: BlendData

Blending data for Links.
#TODO: Create a check that guarantees that the resources in max_proportion and min_proportion are either ResourceComponent or ResourceComponentPotential.
"""
struct BlendLinkData{T<:EMB.Resource} <: BlendData
    blend::ResourceBlend{T}
    tracking_res::Dict{T,<:Real} # Tracking resource for the PWA + molar mass
    max_proportion::Real # max.proportion of tracking resource
    min_proportion::Real # min.proportion of tracking resource
    other_res::Dict{T,<:Real} # Other resources in the blend + molar mass
end

function pressure(n::EMB.Node)
    data = first(filter(data -> data isa AbstractPressureData, n.data))
    return data.pressure
end
pressure(n::EMB.Node, t) = pressure(n)[t]
pressure(data::PressureData, t) = data.pressure[t]

get_weymouth(data::PressureLinkData) = data.weymouth
potential_data(data::PressureLinkData) = (data.min_potential, data.max_potential)

get_pressuredata(n::EMB.Node) = filter(data -> data isa PressureData, n.data)
get_pressuredata(n::EMB.Availability) = ExtensionData[]
get_pressuredata(l::EMB.Link) = ExtensionData[]
get_pressuredata(l::CapDirect) = filter(data -> data isa PressureData, l.data)

get_blenddata(n::EMB.Node) = filter(data -> data isa BlendData, n.data)
get_blenddata(n::EMB.Availability) = ExtensionData[]

get_trackres(data::BlendLinkData) = first(keys(data.tracking_res))
get_blendres(data::BlendLinkData) = data.blend

get_max_proportion(blend_data::BlendData, p::EMB.Resource) = blend_data.max_proportion[p]
get_min_proportion(blend_data::BlendData, p::EMB.Resource) = blend_data.min_proportion[p]

function res_blendata(blend_data::BlendData)
    max_res = blend_data.max_proportion
    min_res = blend_data.min_proportion
    return (max_res, min_res)
end

"""
    function get_pwa(data_pressure::PressureLinkData, data_blend::BlendData; resolution_prop=0.01)
    function get_pwa(l::EMB.Link; resolution_prop=0.01)

Generates/retrieves the PWA functions for a link with blending and pressure data to calculate the Weymouth equation with blending.
# TODO: Improve calling the optimizer. For the moment, it is a parameter included when 
"""
function get_pwa(
    data_pressure::PressureLinkData,
    data_blend::BlendData,
    optimizer;
    resolution_prop = 0.01,
)
    POut, PIn = potential_data(data_pressure)
    PropMax, PropMin = res_blendata(data_blend)
    track_res = first(collect(keys(data_blend.tracking_res)))
    other_res = first(collect(keys(data_blend.other_res)))
    molmass_other = data_blend.other_res[other_res]
    molmass_track = data_blend.tracking_res[track_res]

    x1 = [i for i ∈ POut:10:PIn] # TODO: See how to handle the resolutions of the pressure
    x2 = [i for i ∈ POut:10:PIn]
    x3 = [i for i ∈ PropMin:resolution_prop:PropMax]

    # Define points of the curve
    X = define_points_curve(x1, x2, x3)

    weymouth = get_weymouth(data_pressure)

    # Normalise the weymouth constant
    weymouth_ct = round(normalised_weymouth(weymouth, molmass_other), digits = 4)

    # Calculate exact flow values for approximation
    z =
        calculate_flow.(
            weymouth_ct,
            X[:, 1],
            X[:, 2],
            X[:, 3],
            molmass_other,
            molmass_track,
        )

    # Generate/read the pwa
    fn = get_input_fn([weymouth_ct, X[:, 1], X[:, 2], X[:, 3]], z)

    if isfile(fn)
        pwa = read_from_json(fn)
    else
        pwa = approx(
            FunctionEvaluations(collect(zip(X[:, 1], X[:, 2], X[:, 3])), z),
            Concave(),
            Cluster(; optimizer, planes = 10, strict = :outer, metric = :l1))
        test_approx(pwa, weymouth_ct, PIn, POut, PropMax, molmass_other, molmass_track)

        write_to_json(fn, pwa)
    end

    return pwa
end
function get_pwa(l::EMB.Link, optimizer; resolution_prop = 0.01)
    data_pressure = first(filter(data -> data isa PressureLinkData, l.data))
    data_blend = first(filter(data -> data isa BlendData, l.data))
    return get_pwa(data_pressure, data_blend, optimizer; resolution_prop = resolution_prop)
end

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
