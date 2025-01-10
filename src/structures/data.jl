abstract type PressureData <: Data end

struct PressurePipe <: PressureData
    max_pressure::Int
    weymouth::Float64
    lin_pressures::Vector{Tuple{<:Real, <:Real}}
end

function is_pressurepipe(tm::PipeMode) 
    return any(typeof(data) <: PressureData for data ∈ tm.data)
end 

max_pressure(data::PressureData) = data.max_pressure
function max_pressure(tm::PipeMode)
    if is_pressurepipe(tm)
        data = first(filter(data -> data isa PressureData, tm.data))
        return max_pressure(data)
    else
        throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
    end
end

weymouth_ct(data::PressureData) = data.weymouth
function weymouth_ct(tm::PipeMode)
    if is_pressurepipe(tm)
        data = first(filter(data -> data isa PressureData, tm.data))
        return weymouth_ct(data)
    else
        throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
    end
end
linearised_pressures(data::PressureData) = data.lin_pressures
function linearised_pressures(tm::PipeMode)
    if is_pressurepipe(tm)
        data = first(filter(data -> data isa PressureData, tm.data))
        return linearised_pressures(data)
    else
        throw(ArgumentError("Pipeline $tm does not have data type PressureData"))
    end
end

