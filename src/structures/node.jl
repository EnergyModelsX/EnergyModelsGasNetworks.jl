"""
    abstract type Compressor

A supertype for individual compressor behaviours.
These nodes are used to model potential increase in the network.
"""
abstract type Compressor <: EMB.NetworkNode end

"""
    SimpleCompressor <: Compressor

Compressor that adds a pressure increase (`potential_Δ`) and pays variable cost through
an energy input proportional to `potential_Δ` only:

    Power ≥ input[PowerRes] × potential_Δ

The `input` dict must include both the gas resource (coefficient 1.0) and the energy
resource (e.g. Power) whose coefficient is the power-per-bar parameter.

## Calibrating the energy coefficient

The constraint `Power ≥ c × Δp` models compression power as **independent of gas flow**,
which is only realistic when the compressor always operates near its design capacity.  For
variable flow, prefer `FlowPressureCompressor`.

**Rule of thumb:** for single-stage isentropic compression of gas G from p_in to p_out
at design capacity Q_design [MSm³/d] and efficiency η:

    P_design [pu] = Q_design × (γ/(γ-1)) × (R/M) × T_in × [(p_out/p_in)^((γ-1)/γ) − 1]
                    × ρ_std / (3.6×10⁶ × η × pu_MW×10³)

where pu_MW is the model's Power-unit in MW.  Then set:

    c = P_design / Δp_design

**Example – CH₄, 140 → 167 bar, Q = 300 MSm³/d, η = 0.80:**

Using γ = 1.31, R/M = 518 J/(kg·K), ρ_std = 0.717 kg/Sm³, T_in = 313 K, pu_MW = 41.8:
P_design ≈ 219 pu.  At Δp = 27 bar → c = 219 / 27 ≈ 8.1 pu/bar.

!!! note
    The constraint is a *lower bound*; the optimiser will set Power to the minimum
    required, which equals `c × Δp` at the binding constraint.

# Fields
- **`id::Any`** is the name/identifier of the link.
- **`cap::TimeProfile`** is the maximum flow that the compressor can handle.
- **`opex_var::TimeProfile`** is the variable operational expenditure of the compressor, based on inflow.
- **`opex_fixed::TimeProfile`** is the fixed operational expenditure of the compressor.
- **`input::Dict{<:Resource,<:Real}`** is the input flow into the SimpleCompressor. Include both the inflow resource and the energy resource needed for the potential increase.
- **`output::Dict{<:Resource,<:Real}`** is the output flow from the SimpleCompressor. Only include the outflow resource.
- **`max_incr_potential::TimeProfile`** is the maximum potential increase the SimpleCompressor can provide.
"""
struct SimpleCompressor <: Compressor
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    max_incr_potential::TimeProfile
    data::Vector{<:ExtensionData}
end
function SimpleCompressor(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
    max_incr_potential::TimeProfile,
)
    return SimpleCompressor(
        id,
        cap,
        opex_var,
        opex_fixed,
        input,
        output,
        max_incr_potential,
        ExtensionData[],
    )
end

get_max_potential(n::SimpleCompressor, t) = n.max_incr_potential[t]

"""
    FlowPressureCompressor <: Compressor

Compressor whose power consumption depends linearly on **both** the gas flow rate and the
pressure increase it provides:

    Power ≥ flow_weight × cap_use  +  pressure_weight × potential_Δ

This is physically more accurate than `SimpleCompressor` (which ignores flow rate) because
isentropic compression work scales with mass flow **and** the pressure ratio.

## Physical background and linearisation

The true isentropic shaft power for a single-stage compressor is:

    P = Q × (γ/(γ-1)) × (R/M) × T_in × [(p_out/p_in)^((γ-1)/γ) − 1] / η × ρ_std / (3.6×10⁶ × pu_MW×10³)

where Q is volumetric flow [MSm³/d], γ the heat-capacity ratio, R/M the specific gas
constant [J/(kg·K)], T_in the inlet temperature [K], η the isentropic efficiency, ρ_std
the gas density at standard conditions [kg/Sm³], and pu_MW the model Power-unit in MW.
This expression is bilinear in Q and a nonlinear function of p_out/p_in, so it must be
approximated for a linear programme.

**Linearisation strategy:** choose a representative operating point (Q₀, Δp₀), compute
the physical design power P₀, and allocate between the two terms using a split factor
s ∈ [0, 1] (fraction attributed to the flow term):

    flow_weight     = s       × P₀ / Q₀    [Power-units / (MSm³/d)]
    pressure_weight = (1 − s) × P₀ / Δp₀   [Power-units / bar]

A 50/50 split (s = 0.5) is a reasonable default.

## Example – H₂ compressor, 30 → 109 bar, 12 MSm³/d, η = 0.75

Using γ = 1.40, R/M = 4124 J/(kg·K), ρ_std = 0.0899 kg/Sm³, T_in = 288 K, s = 0.5,
P₀ ≈ 0.802 Power-units (33.5 MW), Q₀ = 12 MSm³/d, Δp₀ = 79 bar:

    flow_weight     = 0.5 × 0.802 / 12   ≈ 0.0334   [Power-units / (MSm³/d)]
    pressure_weight = 0.5 × 0.802 / 79   ≈ 0.00507  [Power-units / bar]

Physical P₀ = 0.802 Power-units = 33.5 MW.

Compare with the simpler but uncalibrated `SimpleCompressor` using `input[(Power, 0.332)]`:
`P = 0.332 × 79 = 26.2 Power-units = 1096 MW` — **33× the physical value**.

# Fields
- **`id::Any`** is the name/identifier of the node.
- **`cap::TimeProfile`** is the maximum gas flow the compressor can handle (MSm³/d).
- **`opex_var::TimeProfile`** is the variable operational expenditure, based on inflow.
- **`opex_fixed::TimeProfile`** is the fixed operational expenditure.
- **`input::Dict{<:Resource,<:Real}`** — include the gas resource and the energy resource (Power).
- **`output::Dict{<:Resource,<:Real}`** — only the outflow gas resource.
- **`max_incr_potential::TimeProfile`** is the maximum pressure increase the compressor can provide (bar).
- **`flow_weight::TimeProfile`** is the power coefficient for gas flow (Power unit per MSm³/d).
- **`pressure_weight::TimeProfile`** is the power coefficient for pressure increase (Power unit per bar).
- **`data::Vector{<:ExtensionData}`** — optional extension data (pressure bounds, investment data, etc.).
"""
struct FlowPressureCompressor <: Compressor
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    max_incr_potential::TimeProfile
    flow_weight::TimeProfile
    pressure_weight::TimeProfile
    data::Vector{<:ExtensionData}
end
function FlowPressureCompressor(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
    max_incr_potential::TimeProfile,
    flow_weight::TimeProfile,
    pressure_weight::TimeProfile,
)
    return FlowPressureCompressor(
        id,
        cap,
        opex_var,
        opex_fixed,
        input,
        output,
        max_incr_potential,
        flow_weight,
        pressure_weight,
        ExtensionData[],
    )
end

get_max_potential(n::FlowPressureCompressor, t) = n.max_incr_potential[t]
flow_weight(n::FlowPressureCompressor, t) = n.flow_weight[t]
pressure_weight(n::FlowPressureCompressor, t) = n.pressure_weight[t]

"""
    PoolingNode <: EMB.NetworkNode

A network junction that mixes incoming gas streams and distributes the blend across
**two or more** outgoing pipeline links, enforcing that every split carries the same
blend composition.

Introduces bilinear constraints
`flow_component[l_out, t, p] = proportion_out[n, t, p] × link_in[l_out, t, blend]`
for each outgoing blend link `l_out`. These are the source of MINLP nonlinearity: the
`proportion_out` variable pins the composition ratio across all outputs simultaneously.

Use `PoolingNode` only when there are **at least two** outgoing blend links that must
share a common composition. For single-output junctions (even those that mix multiple
upstream streams), prefer `BlendingNode`, which uses a fully linear formulation.

For pure pass-through junctions with no gas injection, use `TransitNode`.
"""
struct PoolingNode <: EMB.NetworkNode
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    data::Vector{<:Data}
end
function PoolingNode(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
)
    return PoolingNode(id, cap, opex_var, opex_fixed, input, output, Data[])
end

"""
    DiscretizedPoolingNode <: EMB.NetworkNode

A MILP-compatible alternative to [`PoolingNode`](@ref) that replaces the bilinear
`flow_component = proportion_out × link_in` constraint with a **piecewise linear
approximation** using `PiecewiseLinearOpt.jl`.

Instead of the continuous bilinear product (which requires an MINLP solver such as SCIP),
`DiscretizedPoolingNode` approximates `f(u, v) = u × v` over a grid of breakpoints for
`proportion_out ∈ [0, 1]` and `link_in ∈ [0, F_max]`. The default method is
`:Logarithmic`, which introduces ⌈log₂(K−1)⌉ binary variables per product term
(K = number of breakpoints).

This allows the gas network to be solved by standard MILP solvers (HiGHS, Gurobi, CPLEX)
without any MINLP machinery, at the cost of a bounded approximation error that decreases
with more breakpoints.

# When to use
- When you want to avoid MINLP solvers.
- When investment decisions make the overall problem a MILP anyway.
- When a moderate approximation error on blend proportions is acceptable.

# Breakpoints
Attach a [`DiscretizationData`](@ref) to `data` to control the number of breakpoints
(default: 5). The piecewise linear approximation is exact at breakpoints and linearly
interpolated between them.

# Fields
Identical to [`PoolingNode`](@ref):
- **`id::Any`** — node identifier
- **`cap::TimeProfile`** — maximum throughput capacity
- **`opex_var::TimeProfile`** — variable operational expenditure
- **`opex_fixed::TimeProfile`** — fixed operational expenditure
- **`input::Dict{<:Resource,<:Real}`** — input resource dictionary
- **`output::Dict{<:Resource,<:Real}`** — output resource dictionary
- **`data::Vector{<:Data}`** — optional data (pressure bounds, `DiscretizationData`)

# See also
[`PoolingNode`](@ref) for the bilinear (MINLP) formulation,
[`DiscretizationData`](@ref) for controlling the approximation grid.
"""
struct DiscretizedPoolingNode <: EMB.NetworkNode
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    data::Vector{<:Data}
end
function DiscretizedPoolingNode(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
)
    return DiscretizedPoolingNode(id, cap, opex_var, opex_fixed, input, output, Data[])
end

"""
    TransitNode <: EMB.NetworkNode

A corridor pass-through junction with no gas injection or extraction.

`TransitNode` is the node analogue of a `Direct` link: just as a `Direct` link propagates
pressure unchanged (no Weymouth loss), a `TransitNode` passes the blend on unchanged. Its
component flows are balanced linearly, so inflows from several links mix exactly.

A `TransitNode` only tracks the share `proportion_out` if a Weymouth pipe with
`BlendLinkData` reads it through the node (see [`blend_share_plan`](@ref)). It then copies
the share of its upstream nodes with a linear equality
    proportion_out[n, t, p] == proportion_out[upstream, t, p]
which requires simultaneously active inflows to have the same composition.

A `TransitNode` sends blend down **at most one outgoing link per period**. Nothing ties the
component flows on several outgoing links to a shared composition, so with several outgoing
blend links the constraint
`Σ has_flow[l_out, t] ≤ 1` is added. This allows bidirectional pipelines, where only one
direction is active. Several outgoing links are rejected by `validate_blend_topology` if
any of them has no `has_flow` binary tied to its flow (links without a pressure resource).
Use `PoolingNode` or `DiscretizedPoolingNode` where the blend must split into several
pipes at the same time.

# When to use
- Interior network junctions with no direct H₂/CH₄ source injection.

# Fields
- **`id::Any`** is the name/identifier of the node.
- **`cap::TimeProfile`** is the maximum throughput capacity.
- **`opex_var::TimeProfile`** is the variable operational expenditure.
- **`opex_fixed::TimeProfile`** is the fixed operational expenditure.
- **`input::Dict{<:Resource,<:Real}`** is the dict of input resources. Typically
  `Dict(H2 => 1, CH4 => 1, Blend => 1)` where H2 and CH4 come from composition-tracking
  `Direct` links and Blend comes from the upstream pipeline.
- **`output::Dict{<:Resource,<:Real}`** is the dict of output resources. Typically
  `Dict(Blend => 1)`.
- **`data::Vector{<:Data}`** is the vector of `Data`. Can include pressure bounds
  (`MaxPressureData`, `MinPressureData`, `FixPressureData`).
"""
struct TransitNode <: EMB.NetworkNode
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    data::Vector{<:Data}
end
function TransitNode(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
)
    return TransitNode(id, cap, opex_var, opex_fixed, input, output, Data[])
end

"""
    BlendingNode <: EMB.NetworkNode

A network junction that combines upstream blend streams (and optionally raw H₂/CH₄
injection) into a **single** outgoing blend link, using a fully **linear** formulation.

`BlendingNode` is appropriate whenever a mixing node has exactly one outgoing blend
output. Unlike `PoolingNode`, it does **not** introduce `proportion_out` variables or
bilinear constraints. The blend composition on the single output is fully determined
by the component mass balance (already linear):

    flow_component[l_out, t, p] == Σ_{l_in} flow_component[l_in, t, p] + raw_in[n, t, p]

Quality bounds (`max_h2`, `min_h2` from `RefBlendData`) are enforced as linear flow
bounds on the output link:

    flow_component[l_out, t, H₂] ≤ max_h2 × link_in[l_out, t, Blend]

This makes `BlendingNode` solvable by an LP/MIP solver without any MINLP machinery.

# When to use
- Gas supply entry points (single injector → single downstream pipeline).
- Pre-sink collecting nodes (multiple incoming pipelines → single sink connection).
- Any mixing junction that feeds exactly one downstream blend pipeline.

For nodes with **two or more** outgoing blend links that must share a common composition,
use `PoolingNode`. For pure pass-through junctions with no gas injection, use `TransitNode`.

# Fields
- **`id::Any`** is the name/identifier of the node.
- **`cap::TimeProfile`** is the maximum throughput capacity.
- **`opex_var::TimeProfile`** is the variable operational expenditure.
- **`opex_fixed::TimeProfile`** is the fixed operational expenditure.
- **`input::Dict{<:Resource,<:Real}`** is the dict of input resources. Typically
  `Dict(H2 => 1, CH4 => 1, Blend => 1)`.
- **`output::Dict{<:Resource,<:Real}`** is the dict of output resources. Must contain
  exactly one `ResourcePooling` blend resource, e.g. `Dict(Blend => 1)`.
- **`data::Vector{<:Data}`** is the vector of `Data`. Can include pressure bounds
  (`MaxPressureData`, `MinPressureData`, `FixPressureData`) and quality bounds
  (`RefBlendData`).
"""
struct BlendingNode <: EMB.NetworkNode
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    data::Vector{<:Data}
end
function BlendingNode(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
)
    return BlendingNode(id, cap, opex_var, opex_fixed, input, output, Data[])
end

"""
Abstract node used to convert flow units (e.g. volumetric to energy) without capacity or cost.
"""
abstract type UnitConversion <: EMB.NetworkNode end

"""
    struct RefConversion <: UnitConversion

Default `UnitConversion` node to convert units.
# Fields
- **`id::Any`** is the name/identifier of the node.
- **`input::Dict{<:Resource,<:Real}`** is the input flow into the RefConversion. The conversion value `Real` is not used.
- **`output::Dict{<:Resource,<:Real}`** is the output flow from the RefConversion. The conversion value `Real` is not used.
- **`data::Vector{<:EMB.ExtensionData}`** is the vector of `ExtensionData`. This data will define the type of conversion (e.g., volumetric flow to energy).
"""
struct RefConversion <: UnitConversion
    id::Any
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    data::Vector{<:EMB.ExtensionData}
end

EMB.has_capacity(n::UnitConversion) = false
EMB.has_opex(n::UnitConversion) = false
EMB.has_emissions(n::UnitConversion) = false

"""
    DeblendNode <: EMB.NetworkNode

A network node that physically separates pure H₂ from an incoming blend stream (H₂ + CH₄).

The extracted H₂ is sold as a raw resource (e.g. at a premium H₂ price) while the
remaining blend — with reduced H₂ content — continues downstream, typically to a
`UnitConversion` node with CO₂/ETS pricing.

Extraction is bounded by two independent linear constraints:

1. **Absolute rate limit**: `flow_out[H₂, t] ≤ cap_inst[t]`
   (installed extraction capacity, MSm³/d H₂; investable via `InvData`)
2. **Fraction limit**: `flow_out[H₂, t] ≤ max_extract_fraction × flow_component[l_in, t, H₂]`
   (cannot extract more than a fixed fraction of arriving H₂; specified by [`DeblendData`](@ref))

Both constraints are **linear** because `max_extract_fraction` is a fixed parameter.

Investment cost is linked to `cap` (H₂ extraction rate, MSm³/d) via a standard
`InvData` entry in `data`. Variable opex scales with actual H₂ extracted; fixed opex
scales with installed rate.

# Fields
- **`id::Any`** is the name/identifier of the node.
- **`cap::TimeProfile`** is the maximum H₂ extraction rate (MSm³/d).
- **`opex_var::TimeProfile`** is variable opex per unit H₂ extracted (MEUR/MSm³).
- **`opex_fixed::TimeProfile`** is fixed opex per installed rate per year (MEUR/(MSm³/d)/year).
- **`input::Dict{<:Resource,<:Real}`** must contain exactly one `ResourcePooling` blend.
  Typically `Dict(Blend => 1)`.
- **`output::Dict{<:Resource,<:Real}`** must contain the same `ResourcePooling` blend
  (for the remaining reduced-H₂ blend) and one sub-resource of that blend (the extracted H₂).
  Typically `Dict(Blend => 1, H2 => 1)`.
- **`data::Vector{<:Data}`** must include a [`DeblendData`](@ref) entry.
  Optionally includes `InvData` for investment in extraction capacity.
"""
struct DeblendNode <: EMB.NetworkNode
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    data::Vector{<:Data}
end
