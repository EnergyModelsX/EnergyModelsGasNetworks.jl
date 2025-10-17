"""
Compund resources that have a potential in addition to a flow rate,
these potential behave differently when summarized in a junction.
E.q. electric power which consist of voltage (potential) and power/current (flow rate),
    or gas which have both pressure (potential) and gas flow (flow rate).
"""
abstract type CompoundResource <: EMB.Resource end

"""
    ResourcePotential{T<:Real} <: CompoundResource

Resources that can be transported and converted, but also have energy potential.

# Fields
- **`id`** is the name/identifyer of the resource.
- **`co2_int::T`** is the CO₂ intensity, *e.g.*, t/MWh.
"""
struct ResourcePotential{T<:Real} <: CompoundResource
    id::Any
    co2_int::T
end

"""
    ResourceBlend{T<:Real} <: EMB.Resource

Resources that can be composed of other subresources of subtypes `Resources`. 
Using `ResourcePotential` activates the potential variables and constraints in the model.
"""
struct ResourceBlend{R<:EMB.Resource} <: CompoundResource
    id::Any
    subresources::AbstractVector{R}
end

subresources(𝒫::Array{<:ResourceBlend}) = Dict(blend => blend.subresources for blend ∈ 𝒫)
subresources(r::ResourceBlend) = r.subresources

"""
    res_types(𝒫::Array{<:Resource})

Return the unique resource types in an Array of resources `𝒫`.
"""
res_types(𝒫::Array{<:Resource}) = unique(map(x -> typeof(x), 𝒫)) # FROM ESPEN

"""
    res_types_seg(𝒫::Array{<:Resource})

Return a Vector-of-Vectors of resources segmented by the sub-types.
"""
res_types_seg(𝒫::Array{<:Resource}) =
    [Vector{rt}(filter(x -> isa(x, rt), 𝒫)) for rt ∈ res_types(𝒫)] # FROM ESPEN

function get_source_prop(s::Source, p::EMB.Resource)
    if p ∈ EMB.outputs(s)
        return 1
    else
        return 0
    end
end

# ##############
# abstract type Component <: EMB.Resource end
# struct ComponentBlend <: EMB.Resource
# 	id::Any
# 	components::Vector{Any}
# end

# struct AbstractComponent{T<:Real} <: Component
# 	id::Any
# 	co2_int::T
# 	energy_content::Any
# end
# AbstractComponent(id, co2_int) = AbstractComponent(id, co2_int, nothing)
# struct ComponentTrack{T<:Real} <: Component
# 	id::Any
# 	co2_int::T
# 	upper_level::Any	# maximum percentage allowed in TransmissionModes with Blends
# 	energy_content::Any
# end
# ComponentTrack(id, co2_int, upper_level) = ComponentTrack(id, co2_int, upper_level, nothing)

# function EMB.co2_int(p::ComponentBlend) # TODO: Look into how to integrate it in EMB
# 	co2_int.(p.components)
# end

# EMB.co2_int(p::Component) = p.co2_int

# components(n::ComponentBlend) = n.components

# is_resource_blend(p::Resource) = false
# is_resource_blend(p::ComponentBlend) = true

# is_component(p::Resource) = false
# is_component(p::Component) = true

# is_component_track(p::Resource) = false
# is_component_track(p::ComponentTrack) = true

# upper_level(p::ComponentTrack) = p.upper_level

# energy_content(p::Component) = p.energy_content
