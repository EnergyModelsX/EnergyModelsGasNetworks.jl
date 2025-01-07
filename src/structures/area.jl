"""
PressureBlendingBehaviour as supertype for area behaviours.

PressureBlendingBehaviour is used to identify if a source, pool and terminal area include pressure, blending or both types of parameters. It is used to dispatch the constraints in the model.
"""
abstract type PressureBlendingBehaviour end

struct Pressure <: PressureBlendingBehaviour
    pressure::Any
end

struct Blending <: PressureBlendingBehaviour end

struct PressBlend <: PressureBlendingBehaviour 
    pressure::Any
end

"""
Three new types of Areas are included SourceArea, PoolingArea and TerminalArea, following the structure of typical gas networks.
"""

struct SourceArea <: EMG.Area
    id::Any
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    behaviour::PressureBlendingBehaviour #outlet pressure
end

struct PoolingArea <: EMG.Area
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    behaviour::PressureBlendingBehaviour
    limit::Dict{<:EMB.Resource, <:TimeProfile} #TODO: Check utility
end

struct TerminalArea <: EMG.Area #TODO: Take out TerminalArea and dispatch functions in RefBlendingSink instead
    id
    name
    lon::Real
    lat::Real
    node::EMB.Availability
    behaviour::PressureBlendingBehaviour # inlet pressure
end

is_blendbehaviour(b::PressureBlendingBehaviour) = true
is_blendbehaviour(b::Pressure) = false

is_pressurebehaviour(b::PressureBlendingBehaviour) = true
is_pressurebehaviour(b::Blending) = false

is_blendarea(a::Area) = false
function is_blendarea(a::Union{SourceArea, PoolingArea, TerminalArea}) #TODO: Ensure all areas have the field behaviour
    behaviour = a.behaviour
    is_blendbehaviour = is_blendbehaviour(behaviour)
    if is_blendbehaviour
        return true
    else
        return false
    end
end

is_pressurearea(a::Area) = false
function is_pressurearea(a::Union{PoolingArea, SourceArea, TerminalArea}) 
    behaviour = a.behaviour
    is_pressurebehaviour = is_pressurebehaviour(behaviour)
    if is_pressurebehaviour
        return true
    else
        return false
    end
end

function pressure(a::Union{SourceArea, PoolingArea, TerminalArea}) 
    behaviour = a.behaviour
    is_pressurebehaviour = is_pressurebehaviour(behaviour)
    if is_pressurebehaviour
        return behaviour.pressure
    else
        error("The area $a.id has not a pressure behaviour.")
    end
end

is_terminalarea(a::Area) = false
is_terminalarea(a::TerminalArea) = true