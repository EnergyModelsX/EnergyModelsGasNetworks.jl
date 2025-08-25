abstract type Component <: EMB.Resource end
struct ComponentBlend <: EMB.Resource
    id::Any
    components::Vector{Any}
end

struct AbstractComponent{T<:Real} <: Component
    id::Any
    co2_int::T
    energy_content::Any
end
AbstractComponent(id, co2_int) = AbstractComponent(id, co2_int, nothing)
struct ComponentTrack{T<:Real} <: Component
    id::Any
    co2_int::T
    upper_level::Any# maximum percentage allowed in TransmissionModes with Blends
    energy_content::Any
end
ComponentTrack(id, co2_int, upper_level) = ComponentTrack(id, co2_int, upper_level, nothing)

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

upper_level(p::ComponentTrack) = p.upper_level

energy_content(p::Component) = p.energy_content
