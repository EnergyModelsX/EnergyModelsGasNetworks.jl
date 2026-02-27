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
