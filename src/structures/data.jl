"""
    PressureData to apply to Nodes and Links in a gas network.
    For Source, Availability and SimpleCompressor nodes, the pressure chosen applies to the outlet potential.
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
    PressureLinkData <: AbstractLinkPressureData

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
    blend::ResourcePooling{T}
    max_proportion::Dict{T,Real}
    min_proportion::Dict{T,Real}
end
RefBlendData(
    blend::ResourcePooling{T},
    max_proportion::Dict{T,<:Real},
    min_proportion::Dict{T,<:Real}) where {T<:EMB.Resource} =
    RefBlendData{T}(blend, max_proportion, min_proportion)

"""
    BlendLinkData{T<:CompoundResource} <: BlendData

Blending data for Links.
#TODO: Create a check that guarantees that the resources in max_proportion and min_proportion are either ResourceComponent or ResourceComponentPotential.
"""
struct BlendLinkData{T<:EMB.Resource} <: BlendData
    blend::ResourcePooling{T}
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
function get_blenddata(n::EMB.Node, blend::ResourcePooling)
    blend_data = get_blenddata(n)
    data_vect = filter(b -> b.blend == blend, blend_data)
    return data_vect
end

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
        calculate_flow_to_approximate.(
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

        write_to_json(fn, pwa)
    end

    return pwa
end
function get_pwa(l::EMB.Link, optimizer; resolution_prop = 0.01)
    data_pressure = first(filter(data -> data isa PressureLinkData, l.data))
    data_blend = first(filter(data -> data isa BlendData, l.data))
    return get_pwa(data_pressure, data_blend, optimizer; resolution_prop = resolution_prop)
end
