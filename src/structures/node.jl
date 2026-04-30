"""
    abstract type Compressor

A supertype for individual compressor behaviours.
These nodes are used to model potential increase in the network.
"""
abstract type Compressor <: EMB.NetworkNode end

"""
    SimpleCompressor <: Compressor

Compressor that adds a pressure increase (`potential_Δ`) and pays variable cost through an energy input proportional to `cap_use`.

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
New NetworkNode that overwrite the function constraints flow_in such that cap_use is the sum of the flow_in for blend resources.
The constraint flow_out remain as standard NetworkNodes where cap_use = flow_out (only one resource is out of PoolingNode)
# TODO: Define a check that guarantees that only one resource is in output.
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
    TransitNode <: EMB.NetworkNode

A corridor pass-through junction with no gas injection or extraction.

`TransitNode` is the node analogue of a `Direct` link: just as a `Direct` link propagates
pressure unchanged (no Weymouth loss), a `TransitNode` propagates blend proportions
unchanged (no bilinear mixing terms). It is appropriate for interior pipeline junctions
where the gas composition simply passes through without any blending.

Unlike `PoolingNode`, which requires bilinear `proportion_source × link_in` constraints to
track mixing from multiple sources, `TransitNode` uses a direct linear equality:
    proportion_source[n, s, t] == proportion_source[upstream, s, t]

This eliminates the main source of MINLP complexity at pure transit nodes and makes the
sub-problem solvable by an LP/MIP solver without Alpine's bilinear relaxation.

# When to use
- Interior network junctions with no direct H₂/CH₄ source injection.
- Corridor nodes where the incoming gas simply splits into multiple outgoing pipes.

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
abstract type UnitConversion <: NetworkNode end

Abstract node used to convert flow units (e.g. volumetric to energy) without capacity or cost.
"""
abstract type UnitConversion <: EMB.NetworkNode end

"""
    struct RefConversion <: UnitConversion

Default `UnitConversion` node to convert units.
# Fields
- **`id::Any`** is the name/identifier of the node.
- **`input::Dict{<:Resource,<:Real}`** is the input flow into the RefConversion. The conversion value `Real` is not used. #TODO: As the conversion value is not used, should we consider changing the type of `input` to `Vector{<:Resource}`?
- **`output::Dict{<:Resource,<:Real}`** is the output flow from the RefConversion. The conversion value `Real` is not used. #TODO: As the conversion value is not used, should we consider changing the type of `output` to `Vector{<:Resource}`?
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
