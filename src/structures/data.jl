abstract type PressureData <: Data end

struct PressurePipe <: PressureData
    max_pressure::Int
    weymouth::Float64
    lin_pressures::Vector{Tuple{<:Real, <:Real}}
end

struct PressBlendPipe <: PressureData
    max_pressure::Int
    weymouth::Float64
    pwa::Any
end

function has_pressuredata(tm::PipeMode) 
    return any(typeof(data) <: PressureData for data ∈ tm.data)
end 

is_pressurepipe(data::PressureData) = false
is_pressurepipe(data::PressurePipe) = true
function is_pressurepipe(tm::PipeMode)
    data = first(filter(data -> data isa PressureData, tm.data))
    return is_pressurepipe(data)
end

max_pressure(data::PressureData) = data.max_pressure
function max_pressure(tm::PipeMode)
    if has_pressuredata(tm)
        data = first(filter(data -> data isa PressureData, tm.data))
        return max_pressure(data)
    else
        throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
    end
end

weymouth_ct(data::PressureData) = data.weymouth
function weymouth_ct(tm::PipeMode)
    if has_pressuredata(tm)
        data = first(filter(data -> data isa PressureData, tm.data))
        return weymouth_ct(data)
    else
        throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
    end
end
linearised_pressures(data::PressureData) = data.lin_pressures
function linearised_pressures(tm::PipeMode)
    if has_pressuredata(tm)
        data = first(filter(data -> data isa PressureData, tm.data))
        return linearised_pressures(data)
    else
        throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
    end
end

get_pwa(data::PressureData) = data.pwa
function get_pwa(tm::PipeMode)
    if has_pressuredata(tm)
        data = first(filter(data -> data isa PressureData, tm.data))
        return get_pwa(data)
    else
        throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
    end
end

