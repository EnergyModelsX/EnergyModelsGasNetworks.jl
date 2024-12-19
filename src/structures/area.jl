struct BlendArea <: EMG.Area
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    limit::Dict{<:EMB.Component, <:TimeProfile}
end

struct TerminalArea <: EMG.Area
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
end

struct BlendAvailability <: EMB.Availability
    id
    input::Array{Resource}
    output::Array{Resource}
end

is_blendarea(a::Area) = false
is_blendarea(a::BlendArea) = true


is_terminalarea(a::Area) = false
is_terminalarea(a::TerminalArea) = true

"""
    limit_resources(a::LimitedExchangeArea)

Returns the limited resources of a `LimitedExchangeArea` `a`. All other resources are
considered unlimited.
"""
limit_resources(a::BlendArea) = collect(keys(a.limit))

"""
    exchange_limit(a::BlendArea)

Returns the limits of the exchange resources in area `a`.
"""
exchange_limit(a::BlendArea) = a.limit
"""
    exchange_limit(a::BlendArea, p::Resource)

Returns the limit of exchange resource `p` in area `a` a `TimeProfile`.
"""
exchange_limit(a::BlendArea, p::Component) =
    haskey(a.limit, p) ? a.limit[p] : FixedProfile(0)
"""
    exchange_limit(a::BlendArea, p::Resource, t)

Returns the limit of exchange resource `p` in area `a` at time period `t`.
"""
exchange_limit(a::BlendArea, p::Component, t) =
    haskey(a.limit, p) ? a.limit[p][t] : 0