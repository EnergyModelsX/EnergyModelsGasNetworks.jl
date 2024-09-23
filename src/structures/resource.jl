
"""
    ResourceBlend <: EMB.Resource

Resources that composed of ResourceCarrier resources

#Fields
- **`id`** is the name/identifier of the resource.\n
- **`res_blend`** is the ResourceCarriers forming the blend.\n
"""
struct ResourceBlend <: EMB.Resource
    id
    res_blend::Vector{<:EMB.ResourceCarrier}
end

"""
    ResourceComponent <: EMB.Resource

Resources whose quality needs to be tracked in other Resources (e.g., Sulfur)
"""
struct ResourceComponent <: EMB.Resource
    id
end



function EMB.co2_int(p::ResourceBlend)
    resources = p.res_blend
    co2 = []
    for r in resources
        push!(co2,r.co2_int)
    end
    return co2
end

function output(n::ResourceBlend, p::ResourceCarrier)
    e = n.output
    return e[p]
end

EMB.is_resource_emit(p::ResourceBlend) = false
is_resource_blend(p::Resource) = false
is_resource_blend(p::ResourceBlend) = true
