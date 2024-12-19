struct ResourceCarrierBlend <: EMB.Resource
	id::Any
	components::Vector{}
end

abstract type Component <: EMB.Resource end

struct RefComponent <: Component
	id::Any
	co2_int::T
end

struct ComponentTrack <: Component
	id::Any
	co2_int::T
end

function EMB.co2_int(p::ResourceCarrierBlend)
	components = p.components
	co2 = []
	for c in components
		push!(co2, co2_int(c))
	end
	return co2
end

EMB.co2_int(p::Component) = p.co2_int

components(n::ResourceCarrierBlend) = n.components

is_resource_blend(p::Resource) = false
is_resource_blend(p::ResourceCarrierBlend) = true

is_component(p::Resource) = false
is_component(p::Component) = true

is_component_track(p::Resource) = false
is_component_track(p::ComponentTrack) = true
