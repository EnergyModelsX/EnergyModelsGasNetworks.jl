abstract type Component <: EMB.Resource end
struct ComponentBlend <: EMB.Resource
	id::Any
	components::Vector{Any}
end

struct AbstractComponent{T<:Real} <: Component
	id::Any
	co2_int::T
end

struct ComponentTrack{T<:Real} <: Component
	id::Any
	co2_int::T
end

function EMB.co2_int(p::ComponentBlend) # TODO: Look into how to integrate it in EMB
	co2_int.(p.components)
end

EMB.co2_int(p::Component) = p.co2_int

components(n::ComponentBlend) = n.components

is_resource_blend(p::Resource) = false
is_resource_blend(p::ComponentBlend) = true

is_component(p::Resource) = false
is_component(p::Component) = true

is_component_track(p::Resource) = false
is_component_track(p::ComponentTrack) = true
