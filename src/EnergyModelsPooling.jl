module EnergyModelsPooling

using JuMP
using EnergyModelsBase; const EMB = EnergyModelsBase
using EnergyModelsGeography; const EMG = EnergyModelsGeography
using TimeStruct
using MetaGraphs
using Graphs
using PiecewiseAffineApprox


include("structures/energy.jl")
include("structures/resource.jl")
include("structures/node.jl")
include("structures/area.jl")
include("utils.jl")
include("model.jl")
include("readgms.jl")


export ResourceCarrierBlend, RefComponent, ComponentTrack
export BlendArea, TerminalArea, BlendAvailability
export RefSourceComponent, RefBlendingSink
export create_model
export loadGamsFile

end