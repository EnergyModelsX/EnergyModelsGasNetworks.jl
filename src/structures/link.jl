"""
    struct CapDirect{T} <: Link

A direct link between two nodes with a maximum capacity and data.

# Fields
- **`id`** is the name/identifier of the link.
- **`from::Node`** is the node from which there is flow into the link.
- **`to::Node`** is the node to which there is flow out of the link.
- **`formulation::Formulation`** is the used formulation of links. If not specified, a
  `Linear` link is assumed.
- **`cap::T`** is the maximum capacity of the link.
- **`data::Vector{<:ExtensionData}`** is a vector of extension data associated with the link.
"""
struct CapDirect <: Link
    id::Any
    from::EMB.Node
    to::EMB.Node
    formulation::EMB.Formulation
    cap::TimeProfile
    data::Vector{<:EMB.ExtensionData}
end
Base.show(io::IO, l::CapDirect) = print(io, "l_$(l.id)")
CapDirect(id, from, to, formulation, cap) =
    CapDirect(id, from, to, formulation, cap, EMB.ExtensionData[])

EMB.capacity(l::EMB.Link, t) = 1e6 # Default large capacity
EMB.capacity(l::CapDirect, t) = l.cap[t]
EMB.capacity(l::CapDirect) = l.cap
EMB.has_capacity(l::CapDirect) = true
EMB.has_opex(l::CapDirect) = false # TODO: Modify struct to be able to associate a cost to CapDirect (e.g., mantainance), see constraint_functions.jl for constraints definition

"""
    link_data(l::CapDirect)

Returns the [`ExtensionData`] array of link `l`.

It overwrites the EMB.link_data(l::Link) method, which returns an empty `ExtensionData` vector.
"""
EMB.link_data(l::CapDirect) = l.data
EMB.element_data(l::CapDirect) = EMB.link_data(l)
