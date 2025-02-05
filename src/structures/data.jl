abstract type PressureData <: EnergyModelsBase.Data end

struct PressurePipe <: PressureData
    id::Any
    max_pressure::Int
    weymouth::Float64
    lin_pressures::Vector{Tuple{<:Real, <:Real}}
end

struct PressBlendPipe <: PressureData
    id::Any
    max_pressure::Int
    weymouth::Float64
    pwa::Any
end
function PressBlendPipe(id, max_pressure, weymouth, pin, pout, optimizer)
    Mᶜᴴ⁴ = 16.042 # molecular weight
    Mᴴ² = 2.016
    f(X) = sqrt(weymouth) .* sqrt.(X[:, 1].^2 - X[:, 2].^2) ./ sqrt.(Mᶜᴴ⁴ .* (1 .- X[:, 3]) .+ Mᴴ² .* X[:, 3])
    
    X = _calculate_input(pin, pout)
    z = f(X)

    fn = get_input_fn(X, z)

    if isfile(fn)
        pwa = read_from_json(fn)
    else
        pwa = approx(   
            FunctionEvaluations(tuple.(eachcol(X)...), z),
            Concave(),
            Cluster(
                ;optimizer,
                planes = 10,
                strict = :none,
                metric = :l1,
        ))
        println(typeof(pwa))
        write_to_json(fn, pwa)
    end
    return PressBlendPipe(
        id,
        max_pressure,
        weymouth,
        pwa
    )
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

