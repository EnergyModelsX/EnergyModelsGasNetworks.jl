abstract type PressureData <: EnergyModelsBase.Data end

abstract type PressureDataArea <: PressureData end
#abstract type PressurePipe <: PressureData end #TODO: modify the pressure pipe data to an abstract type

"""
    PressureFixedArea(id, pressure)

    Used to define the `Behaviour`` of pressure in `NetworkAreas` (e.g. `TerminalArea`, `SourceArea`). The pressure is set as a node.
"""
struct PressureFixedArea <: PressureDataArea
    pressure::TimeProfile
end

"""
    PressureMaxArea(id, pressure)

    Used to define the `Behaviour`` of pressure in `NetworkAreas` (e.g. `TerminalArea`, `SourceArea`). The pressure is set as maximum.
"""
struct PressureMaxArea <: PressureDataArea
    pressure::TimeProfile
end

"""
    PressureMinArea(id, pressure)

    Used to define the `Behaviour` of pressure in `NetworkAreas` (e.g. `TerminalArea`, `SourceArea`). The pressure is set as the minimum.
"""
struct PressureMinArea <: PressureDataArea
    pressure::TimeProfile
end

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
function PressurePipe(
    id, max_pressure, weymouth::Float64;
    PIN::Float64,
    POUT::Float64
)
     # Calculate linearised pressures
     pressures = range(PIN, POUT, length=150)
     lin_pressures = [(float(PIN), p) for p in pressures[2:end]]
    
     return PressurePipe(
        id,
        max_pressure,
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
        pin = 70, 
        pout = 50,
        c2_fraction = 0.2,
        M1 = 16.042,
		M2 = 2.016
        )
    
    p1 = [i for i ∈ pout:5:pin]
    p2 = [i for i ∈ pout:5:pin]
    prop = [j for j ∈ 0:0.01:c2_fraction]
    X = hcat(
        repeat(p1, inner = [length(p2) * length(prop)]),
        repeat(p2, inner = [length(prop)], outer = [length(p1)]),
        repeat(prop, outer = [length(p1) * length(p2)])
    )
    valid_indices = X[:, 1].^2 .>= X[:, 2].^2
    X = X[valid_indices, :]

    weymouth_ct = weymouth_constant(FLOW, PIN, POUT)

    flow = weymouth_specgrav.(weymouth_ct, X[:,1], X[:,2], X[:,3], M1, M2)

    fn = get_input_fn([weymouth_ct, X[:,1], X[:,2], X[:,3]], flow)

    if isfile(fn)
        pwa = read_from_json(fn)
    else
        pwa = approx(   
            FunctionEvaluations(collect(zip(X[:,1], X[:,2], X[:,3])), flow),
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
function PressBlendPipe(
    id, max_pressure, optimizer, weymouth::Float64; 
    pout = 100, 
    pin = 180,
    c2_fraction = 0.2,
    M1 = 16.042,
    M2 = 2.016
    )

    p1 = [i for i ∈ pout:5:pin]
    p2 = [i for i ∈ pout:5:pin]
    prop = [j for j ∈ 0:0.05:c2_fraction]
    X = hcat(
        repeat(p1, inner = [length(p2) * length(prop)]),
        repeat(p2, inner = [length(prop)], outer = [length(p1)]),
        repeat(prop, outer = [length(p1) * length(p2)])
    )
    valid_indices = X[:, 1].^2 .>= X[:, 2].^2
    X = X[valid_indices, :]

    weymouth_ct = weymouth_constant(weymouth) # normalise the weymouth constant

    flow = weymouth_specgrav.(weymouth_ct, X[:,1], X[:,2], X[:,3], M1, M2)

    fn = get_input_fn([weymouth_ct,  X[:,1], X[:,2], X[:,3]], flow)

    if isfile(fn)
        pwa = read_from_json(fn)
    else
        pwa = approx(   
            FunctionEvaluations(collect(zip(X[:,1], X[:,2], X[:,3])), flow),
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

