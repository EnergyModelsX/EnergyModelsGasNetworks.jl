"""
Compund resources that have a potential in addition to a flow rate,
these potential behave differently when summarized in a junction.
E.q. electric power which consist of voltage (potential) and power/current (flow rate),
    or gas which have both pressure (potential) and gas flow (flow rate).
"""
abstract type CompoundResource <: EMB.Resource end

"""
    ResourcePressure{T<:Real} <: CompoundResource

Resources that can be transported and converted, but also have energy potential.

# Fields
- **`id`** is the name/identifyer of the resource.
- **`co2_int::T`** is the CO₂ intensity, *e.g.*, t/MWh.
"""
struct ResourcePressure{T<:Real} <: CompoundResource
    id::Any
    co2_int::T
end

"""
    ResourcePooling{T<:Real} <: EMB.Resource

Resources that can be composed of other subresources of subtypes `Resources`. 
Using `ResourcePressure` activates the potential variables and constraints in the model.
"""
struct ResourcePooling{R<:EMB.Resource} <: CompoundResource
    id::Any
    subresources::AbstractVector{R}
end

subresources(𝒫::Array{<:ResourcePooling}) = Dict(blend => blend.subresources for blend ∈ 𝒫)
subresources(r::ResourcePooling) = r.subresources

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
