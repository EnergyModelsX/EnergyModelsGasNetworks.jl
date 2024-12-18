"""
    struct PipePressure <: PipeMode

This `TransmissionMode` allows for including pressure conditions. 
    
#TODO: Check if: it doesn't alter the transported `Resources` as with `PipeSimple` nor includes linepacking like `PipeLinepackSimple`.

A usage of this could be, *e.g.*, by defining a subtype struct of `Resource` with the field
'pressure'. This PipelineMode can then take `SomeSubtype<:Resource` with pressure p₁ at the
inlet, and pressure p₂ at the outlet.

This type also supports consuming resources proportionally to the volume of transported
`Resource` (at the inlet). This could be used for modeling the power needed for operating
the pipeline.

Pipeline transport using `PipeSimple` is assumed to be unidirectional. It is not possible to
use `PipeSimple` for bidirectional transport as the consuming resource would in this case
be consumed at the wrong `Area`.

# Fields
- **`id::String`** is the identifier used in printed output.
- **`inlet::Resource`** is the `Resource` going into transmission.
- **`outlet::Resource`** is the `Resource` going out of the outlet of the transmission.
- **`consuming::Resource`** is the `Resource` the transmission consumes by operating.
- **`consumption_rate::TimeProfile`** the rate of which the resource `Pipeline.consuming` is
  consumed, as a ratio of the volume of the resource going into the inlet, *i.e.*:

        `consumption_rate` = consumed volume / inlet volume (per operational period)
- **`trans_cap::Real`** is the capacity of the transmission mode.
- **`trans_loss::Real`** is the loss of the transported resource during transmission,
  modelled as a ratio.
- **`opex_var::TimeProfile`** is the variable operating expense per energy unit transported.
- **`opex_fixed::TimeProfile`** is the fixed operating expense per installed capacity.
- **`data::Vector{Data}`** is the additional data (*e.g.*, for investments). The field `data`
  is conditional through usage of a constructor.
"""
struct PipePressureSimple <: PipeMode
    id::String
    inlet::EMB.Resource
    outlet::EMB.Resource
    consuming::EMB.Resource
    consumption_rate::TimeProfile
    trans_cap::TimeProfile
    trans_loss::TimeProfile
    opex_var::TimeProfile
    opex_fixed::TimeProfile
    max_pressure::Int
    weymouth::Float64
    lin_pressures::Vector{Tuple}
    directions::Int
    data::Vector{<:Data}

    function PipePressureSimple(
        id::String,
        inlet::EMB.Resource,
        outlet::EMB.Resource,
        consuming::EMB.Resource,
        consumption_rate::TimeProfile,
        trans_cap::TimeProfile,
        trans_loss::TimeProfile,
        opex_var::TimeProfile,
        opex_fixed::TimeProfile,
        max_pressure::Int,
        weymouth::Float64,
        lin_pressures::Vector{Tuple},
        data::Vector{<:Data}
    )
        new(
            id,
            inlet,
            outlet,
            consuming,
            consumption_rate,
            trans_cap,
            trans_loss,
            opex_var,
            opex_fixed,
            max_pressure,
            weymouth,
            lin_pressures,
            1,
            data,
            )
    end
end
function PipePressureSimple(
    id::String,
    inlet::EMB.Resource,
    outlet::EMB.Resource,
    consuming::EMB.Resource,
    consumption_rate::TimeProfile,
    trans_cap::TimeProfile,
    trans_loss::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    max_pressure::Int,
    weymouth::Float64,
    lin_pressures::Vector{Tuple} # Tuples of pairs (P^in, P^out) 
)
    PipePressureSimple(
        id,
        inlet,
        outlet,
        consuming,
        consumption_rate,
        trans_cap,
        trans_loss,
        opex_var,
        opex_fixed,
        max_pressure,
        weymouth,
        lin_pressures,
        Data[],
        )
end

max_pressure(tm::PipePressureSimple) = tm.max_pressure
weymouth_ct(tm::PipePressureSimple) = tm.weymouth
linearised_pressures(tm::PipePressureSimple) = tm.lin_pressures