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

"""
    DiscretizationData <: Data

Configuration data for `DiscretizedPoolingNode` controlling how the bilinear mixing
constraint is approximated.

# Fields
- **`n_points::Int`** is the number of discretization levels for `proportion_out`.
  Higher values give a tighter approximation at the cost of more binary variables.
  Default: 5.
- **`method::Symbol`** selects the formulation used to enforce the bilinear constraint
  `flow_component = proportion_out × link_in`. Must be one of:
  - `:pwl` (default) — 2D piecewise-linear approximation via `PiecewiseLinearOpt`.
    Uses ⌈log₂(K−1)⌉ binary variables per bilinear term (`:Logarithmic` method).
  - `:bigm` — standard BigM MILP formulation. ONE set of K binary variables per time
    step (shared across all outgoing links). `proportion_out` becomes a linear expression,
    making downstream pressure constraints fully MILP-compatible.
  - `:bigm_log` — logarithmic BigM MILP formulation. Uses ⌈log₂(n_points)⌉ binary
    variables per time step (rounded up to the next power of 2). Fewer binary variables
    than `:bigm` at the cost of a potentially finer grid.
- **`max_proportion::Float64`** is the upper bound for the discretization range, i.e.
  levels span `[0, max_proportion]` instead of `[0, 1]`. Default: 1.0 (full range).

  Setting `max_proportion` to match the node's `max_h2` limit ensures all K levels fall
  within the feasible H₂ fraction range, maximising the granularity without adding more
  binary variables. With `max_proportion = 1.0` and `max_h2 = 0.10`, K=10 levels span
  [0%, 11.1%, ...] — only level 1 (0%) is feasible, wasting 9 of 10 levels. With
  `max_proportion = 0.20`, K=10 levels span [0%, 2.2%, ..., 20%] — all 10 are usable.

# Variable counts (per time step) for K = n_points:
| Method    | Binary vars | Continuous w-vars (per outgoing link) |
|-----------|-------------|---------------------------------------|
| `:pwl`    | ⌈log₂(K-1)⌉ per (link,subres) | K² λ per (link,subres) |
| `:bigm`   | K           | K                                     |
| `:bigm_log` | ⌈log₂(K)⌉ | ⌈log₂(K)⌉                           |

# Notes
For `:bigm` and `:bigm_log`, only 2-component blends (M = 2) are currently supported.
For `:bigm_log`, the actual number of levels used is `2^⌈log₂(n_points)⌉`, which may
exceed `n_points` (rounded up to the nearest power of 2).
"""
struct DiscretizationData <: EMB.ExtensionData
    n_points::Int
    method::Symbol
    max_proportion::Float64
    tracked_resource::Union{Nothing,EMB.Resource}
    function DiscretizationData(
        n_points::Int,
        method::Symbol = :pwl,
        max_proportion::Float64 = 1.0,
    )
        return DiscretizationData(nothing, n_points, method, max_proportion)
    end
    function DiscretizationData(
        tracked_resource::Union{Nothing,EMB.Resource},
        n_points::Int,
        method::Symbol = :pwl,
        max_proportion::Float64 = 1.0,
    )
        method ∈ (:pwl, :bigm, :bigm_log) ||
            throw(
                ArgumentError(
                    "DiscretizationData: method must be :pwl, :bigm, or :bigm_log, got :$method",
                ),
            )
        n_points ≥ 2 ||
            throw(ArgumentError("DiscretizationData: n_points must be ≥ 2, got $n_points"))
        0.0 < max_proportion ≤ 1.0 ||
            throw(
                ArgumentError(
                    "DiscretizationData: max_proportion must be in (0, 1], got $max_proportion",
                ),
            )
        return new(n_points, method, max_proportion, tracked_resource)
    end
end

"""
    get_n_points(d::DiscretizationData) -> Int

Return the number of discretization levels.
"""
get_n_points(d::DiscretizationData) = d.n_points

"""
    get_method(d::DiscretizationData) -> Symbol

Return the discretization method (`:pwl`, `:bigm`, or `:bigm_log`).
"""
get_method(d::DiscretizationData) = d.method

"""
    get_max_proportion(d::DiscretizationData) -> Float64

Return the upper bound of the discretization range for `proportion_out` (default: 1.0).
Levels span `[0, max_proportion]`; setting this to the node's `max_h2` limit ensures all
K levels fall within the feasible H₂ fraction range.
"""
get_max_proportion(d::DiscretizationData) = d.max_proportion

"""
    get_tracked_resource(d::DiscretizationData)

Return the resource whose proportion is discretized, or `nothing` for a legacy
`DiscretizationData(n_points, method, max_proportion)` value. Legacy values are resolved
from adjacent `RefBlendData` or `BlendLinkData` when constraints are created.
"""
get_tracked_resource(d::DiscretizationData) = d.tracked_resource

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

const _BLEND_STORAGE_MODES = (:relaxed, :prescribed, :fully_mixed)

"""
    BlendStorageData{T<:EMB.Resource} <: EMB.ExtensionData

Component inventories for a `Storage` node that stores the `ResourcePooling` blend `blend`.
The storage keeps one level per sub-resource of the blend, and `mode` decides the
composition of the discharged gas:

- `:relaxed`: the discharged amount of each component can not exceed what was charged
  and stored. The composition is otherwise free, so this is a bound. The problem stays
  linear.
- `:prescribed`: the discharge has the composition given by `discharge_composition`, an
  extraction quality profile. The problem stays linear. As the storage is cyclic, the
  stored components must be charged as well, so a profile can make the model infeasible.
- `:fully_mixed`: the discharge has the average composition of the stored gas (perfect
  mixing). The constraints are bilinear and require a nonlinear solver.

Full mixing is a reasonable approximation for small, well-mixed storages, such as steel
tanks, line pack or salt caverns. It is a poor one for a depleted natural gas reservoir,
where the gas withdrawn first is closest to the gas injected last. Use `:prescribed` with
an extraction quality profile or `:relaxed` for such storages.

There is no default mode. `mode` must be given, except when a composition profile is
passed, which implies `:prescribed`.

The storage must have a [`Cyclic`](@extref EnergyModelsBase.Cyclic) behaviour, and its
inputs and outputs must not include the sub-resources of `blend`.

# Fields
- **`blend::ResourcePooling{T}`** is the stored blend.
- **`mode::Symbol`** is `:relaxed`, `:prescribed` or `:fully_mixed`.
- **`discharge_composition::Union{Nothing,Dict{T,TimeProfile}}`** is the share of each
  sub-resource in the discharged gas for `:prescribed`, and `nothing` otherwise.
"""
struct BlendStorageData{T<:EMB.Resource} <: EMB.ExtensionData
    blend::ResourcePooling{T}
    mode::Symbol
    discharge_composition::Union{Nothing,Dict{T,TimeProfile}}
    function BlendStorageData{T}(blend, mode, discharge_composition) where {T}
        mode ∈ _BLEND_STORAGE_MODES || throw(
            ArgumentError(
                "BlendStorageData: mode must be one of $(_BLEND_STORAGE_MODES), got :$mode.",
            ),
        )
        (mode == :prescribed) == !isnothing(discharge_composition) || throw(
            ArgumentError(
                "BlendStorageData: a discharge composition is required for, and only " *
                "allowed with, mode :prescribed."),
        )
        return new{T}(blend, mode, discharge_composition)
    end
end
function BlendStorageData(
    blend::ResourcePooling{T};
    mode::Symbol,
    discharge_composition = nothing,
) where {T<:EMB.Resource}
    comp =
        isnothing(discharge_composition) ? nothing :
        Dict{T,TimeProfile}(p => _as_profile(v) for (p, v) ∈ discharge_composition)
    return BlendStorageData{T}(blend, mode, comp)
end
BlendStorageData(blend::ResourcePooling, discharge_composition::Dict) =
    BlendStorageData(blend; mode = :prescribed, discharge_composition)

_as_profile(v::TimeProfile) = v
_as_profile(v::Real) = FixedProfile(v)

"""
    get_storage_mode(data::BlendStorageData) -> Symbol

Return the discharge composition mode of `data`.
"""
get_storage_mode(data::BlendStorageData) = data.mode

"""
    discharge_composition(data::BlendStorageData, p, t)
    discharge_composition(data::BlendStorageData, p)

Return the prescribed share of sub-resource `p` in the discharged gas in period `t`, or as a
`TimeProfile` if `t` is omitted. Only defined for mode `:prescribed`.
"""
discharge_composition(data::BlendStorageData, p::EMB.Resource) =
    data.discharge_composition[p]
discharge_composition(data::BlendStorageData, p::EMB.Resource, t) =
    data.discharge_composition[p][t]

"""
    get_blendstoragedata(n::EMB.Node)

Return the [`BlendStorageData`](@ref) of node `n`, or `nothing` if it has none.
"""
function get_blendstoragedata(n::EMB.Node)
    data = filter(d -> d isa BlendStorageData, EMB.node_data(n))
    return isempty(data) ? nothing : first(data)
end

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
function _clamp_pwa_intercepts(pwa::PWAFunc{Concave,D}) where {D}
    planes = [Plane(p.α, min(p.β, zero(p.β))) for p ∈ pwa.planes]
    return PWAFunc{Concave,D}(planes)
end

const _PWA_FIT_ATTEMPTS = 5

"""
    _pwa_underestimate(pwa::PWAFunc, points, z)

Return the largest underestimate `z_k - pwa(x_k)` over the fitting points, relative to
`maximum(z)`. A concave PWA gives `pwa(x) = min_k (-α_k⋅x - β_k)`.
"""
function _pwa_underestimate(pwa::PWAFunc, points, z)
    under = maximum(
        z[k] - minimum(-sum(plane.α .* points[k]) - plane.β for plane ∈ pwa.planes) for
        k ∈ eachindex(points)
    )
    return under / maximum(z)
end

"""
    _pwa_fit_ok(pwa::PWAFunc, points, z; rtol = 0.1)

Return `true` if the PWA underestimates the flow `z` at the fitting `points` by at most
`rtol × maximum(z)`.
"""
_pwa_fit_ok(pwa::PWAFunc, points, z; rtol = 0.1) = _pwa_underestimate(pwa, points, z) ≤ rtol

"""
    _with_seed(f, seed)

Call `f()` with the global RNG seeded with `seed`, and restore the caller's RNG state
afterwards. Tasks spawned inside `f` (e.g. parallel `Cluster` trials) derive their RNG from
the seeded state, so the result is reproducible.
"""
function _with_seed(f, seed)
    state = copy(Random.default_rng())
    Random.seed!(seed)
    try
        return f()
    finally
        copy!(Random.default_rng(), state)
    end
end

"""
    get_pwa(data_pressure::PressureLinkData, data_blend::BlendData, optimizer; resolution_prop=0.01)
    get_pwa(l::EMB.Link, optimizer; resolution_prop=0.01)

Generate or retrieve the cached PWA (piecewise-affine approximation) of the Weymouth flow
equation for a link with pressure and blending data.

The approximation is a `Concave` piecewise-affine function of three inputs:
`(p_in, p_out, proportion_tracked)`. It is generated by fitting planes to exact Weymouth
evaluations on a pressure grid, with zero-flow anchor points at `(0, 0, α)` added to
suppress infeasible positive intercepts.

Results are cached to a JSON file via the `Scratch.jl` scratch space (keyed on the fit
parameters). See [`get_input_fn`](@ref), [`read_from_json`](@ref), and
[`write_to_json`](@ref).

The fit is seeded from the cache key, so the same data gives the same PWA in every
process. Fitted and cached PWAs are checked with [`_pwa_fit_ok`](@ref). A fit that
underestimates the exact flow by more than 10 % of the maximum flow is refitted (up to
`_PWA_FIT_ATTEMPTS` times, with a different seed each time) and never cached; if no attempt
passes, an error is thrown. An `ArgumentError` is thrown if the pressure step (see
[`set_step_pressure!`](@ref)) leaves fewer than three pressure levels in the range of the link.

If [`get_clamp_pwa_intercepts`](@ref) returns `true` (the default), plane intercepts are
clamped via [`_clamp_pwa_intercepts`](@ref) after fitting to ensure feasibility on inactive
reverse links.
"""
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

    x1 = [i for i ∈ POut:_STEP_PRESSURE[]:PIn]
    x2 = [i for i ∈ POut:_STEP_PRESSURE[]:PIn]
    # With fewer than three pressure levels, almost every (p_in, p_out) pair has zero flow
    # and the fit degenerates.
    length(x1) ≥ 3 || throw(
        ArgumentError(
            "The pressure step $(_STEP_PRESSURE[]) gives only $(length(x1)) grid point(s) " *
            "in the pressure range [$POut, $PIn] of the PWA for $(data_blend.blend.id). " *
            "Use `set_step_pressure!` with a step of at most $((PIn - POut) / 2).",
        ),
    )
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
    x_anchors  = [(0.0, 0.0, Float64(a)) for a ∈ x3]
    z_anchors  = zeros(Float64, length(x3))
    points_all = vcat(collect(zip(X[:, 1], X[:, 2], X[:, 3])), x_anchors)
    z_all      = vcat(z, z_anchors)

    # Generate/read the pwa
    fn = get_input_fn(
        [weymouth_ct, first.(points_all), map(p -> p[2], points_all), last.(points_all)],
        z_all,
    )

    # The Cluster fit starts from random partitions and can degenerate, e.g. when the
    # anchor points form a cluster of their own and give the plane z ≤ 0. Such a fit blocks
    # all flow through the link, so it is rejected (also when read from the cache) and refitted.
    points_data = collect(zip(X[:, 1], X[:, 2], X[:, 3]))
    pwa = isfile(fn) ? read_from_json(fn) : nothing
    if isnothing(pwa) || !_pwa_fit_ok(pwa, points_data, z)
        for attempt ∈ 1:_PWA_FIT_ATTEMPTS
            # Seeded from the cache key, so all processes fit the same PWA for the same data
            pwa = _with_seed(hash((basename(fn), attempt))) do
                approx(
                    FunctionEvaluations(points_all, z_all),
                    Concave(),
                    Cluster(; optimizer, planes = 10, strict = :outer, metric = :l1))
            end
            _pwa_fit_ok(pwa, points_data, z) && break
        end
        _pwa_fit_ok(pwa, points_data, z) || error(
            "PWA fit of the Weymouth equation for $(data_blend.blend.id) with pressures " *
            "[$POut, $PIn] underestimates the flow by up to " *
            "$(round(100 * _pwa_underestimate(pwa, points_data, z), digits = 1)) % after " *
            "$(_PWA_FIT_ATTEMPTS) attempts.",
        )
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
