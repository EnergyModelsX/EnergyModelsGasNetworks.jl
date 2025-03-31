abstract type PressureData <: EnergyModelsBase.Data end

struct PressurePipe <: PressureData
    id::Any
    max_pressure::Int
    weymouth::Float64  # Weymouth constant
    lin_pressures::Vector{Tuple{<:Real, <:Real}}
end
function PressurePipe(
    id, maxpressure;
    FLOW::Any,
    PIN::Any,
    POUT::Any,
)
    # Calculate weymouth constant
    weymouth = FLOW^2/(PIN^2 - POUT^2)

    # Calculate linearised pressures
    pressures = range(PIN, POUT, length=150)
    lin_pressures = [(PIN, p) for p in pressures[2:end]]
    
    return PressurePipe(
        id,
        maxpressure,
        weymouth,
        lin_pressures
    )

end

struct PressBlendPipe <: PressureData
    id::Any
    max_pressure::Int
    weymouth::Float64   # Weymouth constant normalised with respect to specific gravity
    pwa::Any
end
function PressBlendPipe(
        id, max_pressure, optimizer; 
        FLOW::Any, # CH4 flow in accordance with Weymouth equation for a given pressure drop
        PIN::Any, # Inlet pressure corresponding to FLOW
        POUT::Any, # Outlet pressure corresponding to FLOW
        pin = [50, 53, 58, 58, 60, 63, 65, 67, 70], 
        pout = [30, 34, 35, 37, 43, 43, 45, 40, 50],
        c2_fraction = [0.0, 0.05, 0.1, 0.0, 0.05, 0.1, 0.0, 0.05, 0.1],
        M1 = 16.042,
		M2 = 2.016
        )
    
    weymouth_ct = weymouth_constant(FLOW, PIN, POUT)

    flow = weymouth_specgrav.(weymouth_ct, pin, pout, c2_fraction, M1, M2)

    fn = get_input_fn([weymouth_ct, pin, pout, c2_fraction], flow)

    if isfile(fn)
        pwa = read_from_json(fn)
    else
        pwa = approx(   
            FunctionEvaluations(collect(zip(pin, pout, c2_fraction)), flow),
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
        weymouth_ct,
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

