using Xpress
using JuMP
using TimeStruct
using EnergyModelsBase
using EnergyModelsGeography
using EnergyModelsPooling
using Test
using TestItems

const EMB = EnergyModelsBase
const EMG = EnergyModelsGeography
const EMP = EnergyModelsPooling

include("utils.jl")

@testset "test EnergyModelsPooling" begin
    
    @testset "Pooling | Only Blend" begin
        include("case1.jl")
    end

    @testset "Pooling | Pressure + 1 Resource" begin
        include("case2.jl")
    end

    @testset "ConnectorSet" begin
        include("connectorstest.jl")
    end

end
