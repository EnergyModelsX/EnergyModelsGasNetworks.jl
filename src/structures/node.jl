"""
    SimpleCompressor <: EMB.NetworkNode

NetworkNode that increases its potential_out and its input consumption depends on the potential increase.

# Fields
- **`id::Any`** is the name/identifier of the link.
- **`input::Dict{<:Resource,<:Real}`** is the input flow into the SimpleCompressor. Include both the inflow resource and the energy resource needed for the potential increase.
- **`output::Dict{<:Resource,<:Real}`** is the output flow from the SimpleCompressor. Only include the outflow resource.
- **`max_incr_potential::TimeProfile`** is the maximum potential increase the SimpleCompressor can provide.
- **`work_resource`::Dict{<:Resource,<:Real}** is the resource used to provide the work needed for the potential increase and the linear relationship energy/potential increase. 

!NOTE: In SimpleCompressors, the operational cost is determined by the potential increase.
"""
struct SimpleCompressor <: EMB.NetworkNode
    id::Any
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    max_incr_potential::TimeProfile
    energy_resource::Tuple{<:Resource, <:Real}
    data::Vector{<:ExtensionData}
end
function SimpleCompressor(
    id,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
    max_incr_potential::TimeProfile,
    energy_resource::Tuple{<:Resource, <:Real},
)
    return SimpleCompressor(
        id,
        input,
        output,
        max_incr_potential,
        energy_resource,
        ExtensionData[],
    )
end

get_max_potential(n::SimpleCompressor, t) = n.max_incr_potential[t]
get_energy_resource(n::SimpleCompressor) = n.energy_resource
EMB.has_capacity(n::SimpleCompressor) = false
EMB.has_emissions(n::SimpleCompressor) = false
EMB.has_opex(n::SimpleCompressor) = false # TODO: This might be temporal until we decide which operational variable will define the opex.

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
