"""
    abstract type UnitsData <: EMB.ExtensionData end
Abstract type for data used in conversion units (`UnitConversion`).
"""
abstract type UnitsData <: EMB.ExtensionData end

"""
    struct FlowToEnergyData <: UnitsData

Data structure for converting flow units to energy units in `UnitConversion` nodes.
# Fields
- **`LHV::Dict{<:Resource,<:Real}`** is a dictionary that maps the lower heating value (LHV) for the resources involved in the conversion.
- **`flow_units::Symbol`** is the symbol representing the flow units (e.g., :Sm3/d).
- **`time_units::Symbol`** is the symbol representing the time resolution of the model (e.g, hour)

The symbols for `flow_units`` are:
- :Sm3s for standard cubic meters per second
- :Sm3m for standard cubic meters per minute
- :Sm3h for standard cubic meters per hour
- :Sm3d for standard cubic meters per day

The symbols for `time_units` are:
- :s for seconds
- :m for minutes
- :h for hours
- :d for days
"""
struct FlowToEnergyData <: UnitsData
    LHV::Dict{<:Resource,<:Real}
    flow_units::Symbol
    time_units::Symbol
end

"""
    get_time_factor(data::FlowToEnergyData)

Function to calculate the time conversion factor based on the flow units and time units in `FlowToEnergyData`. 
This factor is used to convert flow rates to volume over the time period defined by the model's time resolution.
"""
function get_time_factor(data::FlowToEnergyData)
    flow_units = data.flow_units
    time_units = data.time_units

    flow_units_to_seconds = Dict(
        :Sm3s => 1,
        :Sm3m => 60,
        :Sm3h => 3600,
        :Sm3d => 86400,
    )

    time_units_to_seconds = Dict(
        :s => 1,
        :m => 60,
        :h => 3600,
        :d => 86400,
    )

    Δt = 1/(flow_units_to_seconds[flow_units]) * time_units_to_seconds[time_units]
    return Δt
end

get_LHV(data::FlowToEnergyData) = collect(keys(data.LHV))
get_LHV(data::FlowToEnergyData, p::EMB.Resource) = data.LHV[p]