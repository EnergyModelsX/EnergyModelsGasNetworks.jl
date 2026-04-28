"""
Pressure-related extension data applied to nodes and links.
For sources, availability nodes, and compressors the pressure applies to the outlet potential; for sinks it applies to the inlet.
"""
abstract type PressureData <: EMB.ExtensionData end

"""
Abstract data attached to nodes or links to describe blend quality requirements or tracking parameters.
"""
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

Set a fixed pressure in nodes or links.
"""
struct FixPressureData <: AbstractPressureData
    pressure::TimeProfile
end

"""
    MaxPressureData

Set a maximum pressure in nodes or links.
"""
struct MaxPressureData <: AbstractPressureData
    pressure::TimeProfile
end

"""
    MinPressureData

Set a minimum pressure in nodes or links.
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
    track_molar_fraction::Dict{T,Any} # molar fraction (!not mass) of tracking resource consider to calculate the weymouth constants and normalised, standard = 0.0
    max_proportion::Real # max.proportion of tracking resource
    min_proportion::Real # min.proportion of tracking resource
    other_res::Dict{T,<:Real} # Other resources in the blend + molar mass
end
BlendLinkData(
    blend::ResourcePooling{T},
    tracking_res::Dict{T,<:Real}, # Tracking resource for the PWA + molar mass
    max_proportion::Real, # max.proportion of tracking resource
    min_proportion::Real, # min.proportion of tracking resource
    other_res::Dict{T,<:Real}, # Other resources in the blend + molar mass
) where {T<:EMB.Resource} =
    BlendLinkData{T}(
        blend,
        tracking_res,
        Dict(first(collect(keys(tracking_res))) => 0.0),
        max_proportion,
        min_proportion,
        other_res,
    )

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
    function get_pwa(data_pressure::PressureLinkData, data_blend::BlendData, optimizer; resolution_prop=0.01)
    function get_pwa(l::EMB.Link, optimizer; resolution_prop=0.01)

Generates/retrieves the PWA functions for a link with blending and pressure data to calculate the Weymouth equation with blending.
"""

"""
    _clamp_pwa_intercepts(pwa::PWAFunc{Concave, D}) where {D}

Return a copy of `pwa` with all plane intercepts clamped to `β ≤ 0`.

For a concave PWA, the per-plane constraint added by `PiecewiseAffineApprox.constr` is:

    z ≤ -dot(plane.α, x) - plane.β

At `x = (0, 0, 0)` (link potentials forced to zero by `constraints_balance_pressure`
when a reverse link is inactive): `z ≤ -plane.β`. With `z = 0` (no flow on the
inactive link), this becomes `0 ≤ -plane.β`. If any plane has `plane.β > 0` due to
extrapolation outside the fitting domain, this constraint is infeasible.

Clamping sets `β_k ← min(0, β_k)` for each plane. This:
- Makes `0 ≤ -β_k` always satisfiable (since `-β_k ≥ 0` after clamping).
- Preserves the outer approximation: decreasing `β_k` increases `-β_k`, loosening the
  upper bound and keeping `approx(x) ≥ f(x)` on the fitting domain.

Called by `get_pwa` when `get_clamp_pwa_intercepts()` returns `true` (the default).
Use [`set_clamp_pwa_intercepts!`](@ref) to control this behaviour.
"""
function _clamp_pwa_intercepts(pwa::PWAFunc{Concave, D}) where {D}
    planes = [Plane(p.α, min(p.β, zero(p.β))) for p ∈ pwa.planes]
    return PWAFunc{Concave, D}(planes)
end

function get_pwa(
    data_pressure::PressureLinkData,
    data_blend::BlendData,
    optimizer;
    resolution_prop = 0.01,
)
    POut, PIn = potential_data(data_pressure)
    PropMax, PropMin = res_blendata(data_blend)
    track_res, molmass_track = first(data_blend.tracking_res)
    other_res, molmass_other = first(data_blend.other_res)
    track_molar_fraction = data_blend.track_molar_fraction[track_res]

    x1 = [i for i ∈ POut:_STEP_PRESSURE[]:PIn] # TODO: See how to handle the resolutions of the pressure
    x2 = [i for i ∈ POut:_STEP_PRESSURE[]:PIn]
    x3 = [i for i ∈ PropMin:resolution_prop:PropMax]

    # Define points of the curve
    X = define_points_curve(x1, x2, x3)

    weymouth = get_weymouth(data_pressure)

    # Normalise the weymouth constant
    weymouth_ct =
        round(normalised_weymouth(data_blend, weymouth, track_molar_fraction), digits = 4)

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

    # Append zero-flow anchor points (p_in=0, p_out=0, alpha) for all alpha values.
    # At these points f(0, 0, alpha) = sqrt(W * (0² - 0²) * g(alpha)) = 0 exactly.
    # Including them in the fitting domain encourages each plane assigned one of these
    # points (via the strict=:outer constraint in Cluster) to satisfy
    # P_k(0, 0, alpha) = α_k[3]*alpha + β_k ≤ 0, reducing the risk of positive
    # intercepts that cause infeasibility when inactive reverse links zero out
    # potentials in bidirectional networks. The cache key incorporates the full
    # augmented data, so old cached files (without anchors) are automatically
    # bypassed by a different hash.
    x_anchors = [(0.0, 0.0, Float64(a)) for a ∈ x3]
    z_anchors  = zeros(Float64, length(x3))
    points_all = vcat(collect(zip(X[:, 1], X[:, 2], X[:, 3])), x_anchors)
    z_all      = vcat(z, z_anchors)

    # Generate/read the pwa
    fn = get_input_fn([weymouth_ct, first.(points_all), map(p -> p[2], points_all), last.(points_all)], z_all)

    if isfile(fn)
        pwa = read_from_json(fn)
    else
        pwa = approx(
            FunctionEvaluations(points_all, z_all),
            Concave(),
            Cluster(; optimizer, planes = 10, strict = :outer, metric = :l1))

        write_to_json(fn, pwa)
    end

    # Optionally clamp plane intercepts to β ≤ 0. Default: enabled.
    # This is a safety guarantee for the case where some planes did not receive any
    # anchor point in their Cluster partition during random fitting. See
    # set_clamp_pwa_intercepts! and _clamp_pwa_intercepts for full documentation.
    if get_clamp_pwa_intercepts()
        pwa = _clamp_pwa_intercepts(pwa)
    end

    return pwa
end
function get_pwa(l::EMB.Link, optimizer; resolution_prop = 0.01)
    data_pressure = first(filter(data -> data isa PressureLinkData, l.data))
    data_blend = first(filter(data -> data isa BlendData, l.data))
    return get_pwa(data_pressure, data_blend, optimizer; resolution_prop = resolution_prop)
end
