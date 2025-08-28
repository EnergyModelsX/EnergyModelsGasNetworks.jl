"""
    Compressor <: EMB.NetworkNode

NetworkNode that increases its potential_out.

# Fields
- **`id::Any`** is the name/identifier of the link.
- **`cap::TimeProfile`** the maximum flow allowed through the compressor.
- **`opex_var::TimeProfile`** is the variable operating expense per cap_use
- **`opex_fixed::TimeProfile`** is the fixed operating expense per time unit.
- **`input::Dict{<:Resource,<:Real}`** is the input flow into the compressor.
- **`output::Dict{<:Resource,<:Real}`** is the output flow from the compressor.
- **`potential_increase::TimeProfile`** maximum potential increase the compressor can provide.
- **`potential_opex_var::TimeProfile`** is the variable operating expense per potential unit increased.

!NOTE: In Compressors, the operational cost is determined by the potential increase and not the :cap_use (flow within compressor).
"""
struct Compressor <: EMB.NetworkNode
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
function Compressor(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
    potential_increase::TimeProfile,
    potential_opex_var::TimeProfile
)
    return Compressor(id, cap, opex_var, opex_fixed, input, output, potential_increase, potential_opex_var, ExtensionData[])
end

get_potential(n::Compressor, t) = n.potential_increase[t]

"""
New NetworkNode that overwrite the function constraints flow_in such that cap_use is the sum of the flow_in for blend resources.
The constraint flow_out remain as standard NetworkNodes where cap_use = flow_out (only one resource is out of RefBlend)
# TODO: Define a check that guarantees that only one resource is in output.
"""
struct RefBlend <: EMB.NetworkNode
    id::Any
    cap::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    input::Dict{<:Resource,<:Real}
    output::Dict{<:Resource,<:Real}
    data::Vector{<:Data}
end
function RefBlend(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
)
    return RefBlend(id, cap, opex_var, opex_fixed, input, output, Data[])
end


# """
# 	RefSourceComponent <: EMB.Source

# A source node with specific qualities of ResourceComponent resources.

# # Fields
# - **`id`** is the name/identifier of the node.
# - **`cap::TimeProfile`** is the installed capacity.
# - **`opex_var::TimeProfile`** is the variable operating expense per energy unit produced.
# - **`opex_fixed::TimeProfile`** is the fixed operating expense.
# - **`output::Dict{<:Resource, <:Real}`** are the generated [`Resource`](@ref)s with
#   conversion value `Real`.
# - **`data::Vector{<:Data}`** is the additional data (e.g. for investments). The field `data`
#   is conditional through usage of a constructor.
# """

# struct SourceComponent <: EMB.Source
# 	id::Any
# 	cap::TimeProfile
# 	opex_var::TimeProfile
# 	opex_fixed::TimeProfile
# 	output::Dict{<:Resource, <:Real}
# 	quality::Dict{<:Component, <:Real}
# 	data::Vector{Data}
# end
# function SourceComponent(
# 	id,
# 	cap::TimeProfile,
# 	opex_var::TimeProfile,
# 	opex_fixed::TimeProfile,
# 	output::Dict{<:Resource, <:Real},
# 	quality::Dict{<:Component, <:Real},
# )
# 	return SourceComponent(id, cap, opex_var, opex_fixed, output, quality, Data[])
# end

# """ A reference `BlendingSink` node

# `Sink` node with max. boundaries in quality of `ResourceComponent`s and proportion of `ResourceCarrier`s. 

# #Fields
# - **`id`** is the name/identifier of the node.\n
# - **`cap::TimeProfile`** is the demand.\n
# - **`penalty::Dict{Symbol, <:TimeProfile}
# - **`input::Dict{<:ResourceBlend, <:Real}`** are the input `Resources`s.\n
# - **`data::Vector{Data}`** is the additional data (e.g. for investments). The field \
# `data` is conditional through usage of a constructor.
# """
# struct BlendingSink <: EMB.Sink
# 	id::Any
# 	cap::TimeProfile
# 	penalty::Dict{Symbol, <:TimeProfile}
# 	input::Dict{<:Resource, <:Real}
# 	upperbound::Dict{<:Component, <:Real}
# 	lowerbound::Dict{<:Component, <:Real}
# 	data::Vector{Data}
# end
# function BlendingSink(
# 	id,
# 	cap::TimeProfile,
# 	penalty::Dict{<:Any, <:TimeProfile},
# 	input::Dict{<:Resource, <:Real},
# 	upperbound::Dict{<:Component, <:Real},
# 	lowerbound::Dict{<:Component, <:Real},
# )
# 	return BlendingSink(id, cap, penalty, input, upperbound, lowerbound, Data[])
# end

# components(n::SourceComponent) = collect(keys(n.quality))

# function get_quality(s::SourceComponent, p::Component)
# 	return get(s.quality, p, 0)
# end

# res_upper(n::BlendingSink) = collect(keys(n.upperbound))
# res_lower(n::BlendingSink) = collect(keys(n.lowerbound))

# function get_upper(s::BlendingSink, p::Component)
# 	upperbound = s.upperbound
# 	if p in keys(upperbound)
# 		return upperbound[p]
# 	else
# 		return 0
# 	end
# end

# function get_lower(s::BlendingSink, p::Component)
# 	lowerbound = s.lowerbound
# 	if p in keys(lowerbound)
# 		return lowerbound[p]
# 	else
# 		return 0
# 	end
# end



# """
# 	is_geoavailability(n::Node)

# Checks, whether node `n` is a `GeoAvailability` node
# """
# is_geoavailability(n::EMB.Node) = false
# is_geoavailability(n::EMG.GeoAvailability) = true

# """
# 	is_blending_sink(n::Node)

# Checks, whether node `n` is a `BlendingSink` node
# """
# is_blending_sink(::EMB.Node) = false
# is_blending_sink(::BlendingSink) = true

# cap_price(n::BlendingSink, t) = n.penalty[:cap_price][t]