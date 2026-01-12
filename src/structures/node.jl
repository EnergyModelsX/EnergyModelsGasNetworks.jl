"""
    SimpleCompressor <: EMB.NetworkNode

NetworkNode that increases its potential_out.

# Fields
- **`id::Any`** is the name/identifier of the link.
- **`cap::TimeProfile`** the maximum flow allowed through the SimpleCompressor.
- **`opex_var::TimeProfile`** is the variable operating expense per cap_use
- **`opex_fixed::TimeProfile`** is the fixed operating expense per time unit.
- **`input::Dict{<:Resource,<:Real}`** is the input flow into the SimpleCompressor.
- **`output::Dict{<:Resource,<:Real}`** is the output flow from the SimpleCompressor.
- **`potential_increase::TimeProfile`** maximum potential increase the SimpleCompressor can provide.
- **`potential_opex_var::TimeProfile`** is the variable operating expense per potential unit increased.

!NOTE: In SimpleCompressors, the operational cost is determined by the potential increase and not the :cap_use (flow within SimpleCompressor).
"""
struct SimpleCompressor <: EMB.NetworkNode
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    potential_increase::TimeProfile
    potential_opex_var::TimeProfile
    data::Vector{<:ExtensionData}
end
function SimpleCompressor(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
    potential_increase::TimeProfile,
    potential_opex_var::TimeProfile,
)
    return SimpleCompressor(
        id,
        cap,
        opex_var,
        opex_fixed,
        input,
        output,
        potential_increase,
        potential_opex_var,
        ExtensionData[],
    )
end

get_potential(n::SimpleCompressor, t) = n.potential_increase[t]

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
