struct BlendArea <: EMG.Area
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
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