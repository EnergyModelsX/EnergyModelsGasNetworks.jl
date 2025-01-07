module EnergyModelsPooling

using JuMP
using EnergyModelsBase; const EMB = EnergyModelsBase
using EnergyModelsGeography; const EMG = EnergyModelsGeography
using TimeStruct
using MetaGraphs
using Graphs
using PiecewiseAffineApprox


# include("structures/energy.jl") # TODO: Include energy content
include("structures/resource.jl")
include("structures/node.jl")
include("structures/area.jl")
include("structures/mode.jl")
include("utils.jl")
include("model.jl")



export ResourceCarrierBlend, RefComponent, ComponentTrack
export RefSourceComponent, RefBlendingSink
export SourceArea, TerminalArea, PoolingArea, Pressure, Blending, PressBlend
export PipePressureSimple
export create_model


end