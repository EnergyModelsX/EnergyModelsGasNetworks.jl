module EnergyModelsGasNetworks

using EnergyModelsBase
const EMB = EnergyModelsBase
using TimeStruct
using JuMP

using PiecewiseAffineApprox
using LinearAlgebra

using Scratch
using JSON

### PARAMETERS
const _STEP_PRESSURE = Ref(10) # Pressure step for PWA approximation

"""
    get_step_pressure()

Return the current pressure step (in the same units as the inputs, e.g. bars) used when building piecewise-affine approximations of the Weymouth relation.
"""
get_step_pressure() = _STEP_PRESSURE[]

"""
    set_step_pressure!(step_pressure)

Set the spacing of the pressures used to generate piecewise-affine Weymouth cuts for blended gases.
Default is 10 (e.g., bars).
"""
set_step_pressure!(step_pressure) = (_STEP_PRESSURE[] = step_pressure)

const _OPT = Ref{Any}(nothing)
"""
    set_optimizer_pwa!(opt)

Set the optimizer used by EnergyModelsGasNetworks for PWA approximations.
"""
set_optimizer_pwa!(opt) = (_OPT[] = opt)
"Get optimizer; error if not set."
function _get_optimizer()
    opt = _OPT[]
    opt === nothing && error(
        "EnergyModelsGasNetworks: optimizer not set. Call EMGN.set_optimizer_pwa!(opt) before declaring the model.",
    )
    return opt
end

const _CLAMP_PWA_INTERCEPTS = Ref(true)

"""
    get_clamp_pwa_intercepts() -> Bool

Return whether PWA plane intercepts are clamped to `β ≤ 0` after fitting or loading
from cache. The default is `true`.

See [`set_clamp_pwa_intercepts!`](@ref) for a full explanation.
"""
get_clamp_pwa_intercepts() = _CLAMP_PWA_INTERCEPTS[]

"""
    set_clamp_pwa_intercepts!(clamp::Bool)

Control whether the intercept `β` of each PWA plane is clamped to `min(0, β)` after
the piecewise-affine approximation is obtained (either freshly fitted or loaded from
the on-disk cache).

# Background

The Weymouth PWA is fitted over the physical pressure domain `[POut, PIn]` barg. In
bidirectional networks, reverse links are represented as `CapDirect` links. When a
reverse link is inactive (`has_flow[l, t] = 0`), the constraints in
`constraints_balance_pressure` force both `link_potential_in` and `link_potential_out`
to zero via big-M bounds. The PWA constraint (one inequality per plane `k`) then
evaluates at the origin:

    link_in ≤ -dot(plane.α, (0, 0, proportion_track)) - plane.β

With `link_in = 0` (inactive link) and `proportion_track = 0` (CH4-only network,
no H2 injection), this simplifies to:

    0 ≤ -plane.β

If any plane has `plane.β > 0` — which can occur due to linear extrapolation outside
the `[POut, PIn]` fitting domain — this constraint is infeasible.

# What clamping does

Clamping sets `β_k ← min(0, β_k)` for every plane in the fitted PWA. This is
mathematically safe:

- The outer (concave) approximation property is *preserved*. Making `β_k` smaller
  (more negative or zero) increases `-β_k`, which loosens the upper bound on
  `link_in`. Since the original PWA already satisfies `approx(x) ≥ f(x)` on the
  fitting domain, a looser upper bound still satisfies this property.
- The accuracy loss in the physical operating range `[POut, PIn]` is negligible:
  the linear terms `dot(α_k, (p_in, p_out, alpha))` dominate at typical pressures
  of 30–72 barg, so a small upward shift of `-β_k` has minimal effect on solution
  quality.
- Clamping eliminates the infeasibility entirely: after clamping, `0 ≤ -β_k` holds
  for all planes by construction.

# When to disable

Set `clamp = false` only for:
- Research or diagnostic runs to measure the raw effect of the PWA intercepts.
- Networks where all links are guaranteed to always have `has_flow = 1` (no inactive
  reverse links), making clamping unnecessary.
- Benchmarking the impact of clamping on solution quality.

!!! warning
    When `clamp = false` the model **may** become infeasible in bidirectional Blend
    networks without H2 injection if any fitted plane has a positive intercept.

# Default

`true` (clamping is enabled).
"""
set_clamp_pwa_intercepts!(clamp::Bool) = (_CLAMP_PWA_INTERCEPTS[] = clamp)

@info "By default, the steps for pressure PWA approximations is set to $(get_step_pressure()) units. Use `EMGN.set_step_pressure!(step)` to change it."
@info "By default, the optimizer for PWA is not set. Use `EMGN.set_optimizer_pwa!(opt)` before calling `create_model()`."
@info "By default, PWA plane intercepts are clamped to β ≤ 0 (clamp_pwa_intercepts = true). Use `EMGN.set_clamp_pwa_intercepts!(false)` to disable."

include("utils.jl")
include("scratch.jl")
include("structures/resource.jl")
include("structures/node.jl")
include("structures/link.jl")
include("structures/data.jl")
include("structures/data_units.jl")
include("constraint_functions.jl")
include("constraint_blend.jl")
include("constraint_pressure.jl")
include("data_functions.jl")
include("model.jl")
include("checks.jl")

export set_optimizer_pwa!, set_step_pressure!, delete_cache
export get_clamp_pwa_intercepts, set_clamp_pwa_intercepts!
export SimpleCompressor, PoolingNode, CapDirect
export ResourcePressure, ResourceComponentPotential, ResourceComponent, ResourcePooling
export FixPressureData, MaxPressureData, MinPressureData, PressureLinkData
export RefBlendData, BlendLinkData
export RefConversion
export FlowToEnergyData

end
