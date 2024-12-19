"""
	RefSourceComponent <: EMB.Source

A source node with specific qualities of ResourceComponent resources.

# Fields
- **`id`** is the name/identifier of the node.
- **`cap::TimeProfile`** is the installed capacity.
- **`opex_var::TimeProfile`** is the variable operating expense per energy unit produced.
- **`opex_fixed::TimeProfile`** is the fixed operating expense.
- **`output::Dict{<:Resource, <:Real}`** are the generated [`Resource`](@ref)s with
  conversion value `Real`.
- **`data::Vector{<:Data}`** is the additional data (e.g. for investments). The field `data`
  is conditional through usage of a constructor.
"""

struct RefSourceComponent <: EMB.Source
	id::Any
	cap::TimeProfile
	opex_var::TimeProfile
	opex_fixed::TimeProfile
	output::Dict{<:Resource, <:Real}
	quality::Dict{<:Component, <:Real}
	data::Vector{Data}
end
function RefSourceComponent(
	id,
	cap::TimeProfile,
	opex_var::TimeProfile,
	opex_fixed::TimeProfile,
	output::Dict{<:Resource, <:Real},
	quality::Dict{<:Component, <:Real},
)
	return RefSourceComponent(id, cap, opex_var, opex_fixed, output, quality, Data[])
end

""" A reference `RefBlendingSink` node

`Sink` node with max. boundaries in quality of `ResourceComponent`s and proportion of `ResourceCarrier`s. 

#Fields
- **`id`** is the name/identifier of the node.\n
- **`cap::TimeProfile`** is the demand.\n
- **`penalty::Dict{Symbol, <:TimeProfile}
- **`input::Dict{<:ResourceBlend, <:Real}`** are the input `Resources`s.\n
- **`data::Vector{Data}`** is the additional data (e.g. for investments). The field \
`data` is conditional through usage of a constructor.
"""
struct RefBlendingSink <: EMB.Sink
	id::Any
	cap::TimeProfile
	penalty::Dict{Symbol, <:TimeProfile}
	input::Dict{<:Resource, <:Real}
	upperbound::Dict{<:Component, <:Real}
	lowerbound::Dict{<:Component, <:Real}
	data::Vector{Data}
end
function RefBlendingSink(
	id,
	cap::TimeProfile,
	penalty::Dict{<:Any, <:TimeProfile},
	input::Dict{<:Resource, <:Real},
	upperbound::Dict{<:Component, <:Real},
	lowerbound::Dict{<:Component, <:Real},
)
	return RefBlendingSink(id, cap, penalty, input, upperbound, lowerbound, Data[])
end

components(n::RefSourceComponent) = collect(keys(n.quality))

function get_quality(s::RefSourceComponent, p::Component)
	return get(s.quality, p, 0)
end

res_upper(n::RefBlendingSink) = collect(keys(n.upperbound))
res_lower(n::RefBlendingSink) = collect(keys(n.lowerbound))

function get_upper(s::RefBlendingSink, p::Component)
	upperbound = s.upperbound
	if p in keys(upperbound)
		return upperbound[p]
	else
		return 0
	end
end

function get_lower(s::RefBlendingSink, p::Component)
	lowerbound = s.lowerbound
	if p in keys(lowerbound)
		return lowerbound[p]
	else
		return 0
	end
end



"""
	is_geoavailability(n::Node)

Checks, whether node `n` is a `GeoAvailability` node
"""
is_geoavailability(n::EMB.Node) = false
is_geoavailability(n::EMG.GeoAvailability) = true

"""
	is_blending_sink(n::Node)

Checks, whether node `n` is a `RefBlendingSink` node
"""
is_blending_sink(::EMB.Node) = false
is_blending_sink(::RefBlendingSink) = true

surplus_penalty(n::RefBlendingSink) = nothing
surplus_penalty(n::RefBlendingSink, t) = nothing
deficit_penalty(n::RefBlendingSink) = nothing
deficit_penalty(n::RefBlendingSink, t) = nothing

price_penalty(n::RefBlendingSink) = n.penalty[:price]
price_penalty(n::RefBlendingSink, t) = n.penalty[:price][t]