struct SourcePressure <: EMG.Area
    id::Any
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    out_pressure::Any
end

struct BlendArea <: EMG.Area
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    limit::Dict{<:Component, <:TimeProfile}
end

"""
    No pressure change assumed in `BlendPressureArea`.
"""
struct BlendPressureArea <: EMG.Area
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    limit::Dict{<:EMB.Resource, <:TimeProfile}
end

struct TerminalArea <: EMG.Area #TODO: Take out TerminalArea and dispatch functions in RefBlendingSink instead
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
end

struct TerminalPressureArea <: EMG.Area
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    in_pressure::Int
end

is_blendarea(a::Area) = false
is_blendarea(a::Union{BlendArea, BlendPressureArea}) = true


is_terminalarea(a::Area) = false
is_terminalarea(a::Union{TerminalArea, TerminalPressureArea}) = true

is_pressurearea(a::Area) = false
is_pressurearea(a::Union{BlendPressureArea, SourcePressure, TerminalPressureArea}) = true

"""
    limit_resources(a::LimitedExchangeArea)

Returns the limited resources of a `LimitedExchangeArea` `a`. All other resources are
considered unlimited.
"""
limit_resources(a::Union{BlendArea, BlendPressureArea}) = collect(keys(a.limit))

"""
    exchange_limit(a::BlendArea)

Returns the limits of the exchange resources in area `a`.
"""
exchange_limit(a::Union{BlendArea, BlendPressureArea}) = a.limit
"""
    exchange_limit(a::BlendArea, p::Resource)

Returns the limit of exchange resource `p` in area `a` a `TimeProfile`.
"""
exchange_limit(a::Union{BlendArea, BlendPressureArea}, p::Component) =
    haskey(a.limit, p) ? a.limit[p] : FixedProfile(0)
"""
    exchange_limit(a::BlendArea, p::Resource, t)

Returns the limit of exchange resource `p` in area `a` at time period `t`.
"""
exchange_limit(a::Union{BlendArea, BlendPressureArea}, p::Component, t) =
    haskey(a.limit, p) ? a.limit[p][t] : 0

out_pressure(a::SourcePressure) = a.out_pressure
in_pressure(a::TerminalPressureArea) = a.in_pressure