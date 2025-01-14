using Xpress
using HiGHS
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
    
    @testset "EnergyModelsPooling | Only Blend" begin
        include("case1.jl")
    end

    @testset "EnergyModelsPooling | Only Pressure" begin
        include("case2.jl")
    end

    @testset "EnergyModelsPooling | Pressure + Blend" begin
        include("case3.jl")
    end

end
