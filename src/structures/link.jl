"""
    struct CapDirect{T} <: Link

A direct link between two nodes with a maximum capacity.

# Fields
- **`id`** is the name/identifier of the link.
- **`from::Node`** is the node from which there is flow into the link.
- **`to::Node`** is the node to which there is flow out of the link.
- **`formulation::Formulation`** is the used formulation of links. If not specified, a
  `Linear` link is assumed.
- **`cap::T`** is the maximum capacity of the link.
"""
struct CapDirect <: Link
    id::Any
    from::EMB.Node
    to::EMB.Node
    formulation::EMB.Formulation
    cap::TimeProfile
    data::Vector{<:EMB.ExtensionData}
end
CapDirect(id, from, to, formulation, cap) = 
    CapDirect{Float64}(id, from, to, formulation, cap, EMB.ExtensionData[])

EMB.capacity(l::EMB.Link, t) = 1e6 # Default large capacity
EMB.capacity(l::CapDirect, t) = l.cap[t]