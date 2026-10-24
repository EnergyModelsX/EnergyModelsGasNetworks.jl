@testitem "API - convenience constructors without extension data" begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using TimeStruct
    const EMB = EnergyModelsBase

    NG = ResourcePressure("NG", 0.0)
    Power = ResourceCarrier("Power", 0.0)
    sc = SimpleCompressor("c", FixedProfile(10), FixedProfile(0), FixedProfile(0),
        Dict(NG => 1, Power => 0.1), Dict(NG => 1), FixedProfile(50))
    @test isempty(EMB.node_data(sc))
    fpc = FlowPressureCompressor("f", FixedProfile(10), FixedProfile(0), FixedProfile(0),
        Dict(NG => 1, Power => 0.1), Dict(NG => 1), FixedProfile(50),
        FixedProfile(0.01),
        FixedProfile(0.02))
    @test isempty(EMB.node_data(fpc))

    src = RefSource("s", FixedProfile(1), FixedProfile(0), FixedProfile(0), Dict(NG => 1))
    snk = RefSink("k", FixedProfile(1),
        Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1)), Dict(NG => 1))
    l = CapDirect("l", src, snk, Linear(), FixedProfile(5))
    @test isempty(EMB.link_data(l))
    @test EMB.capacity(l, first(SimpleTimes(1, 1))) == 5
    @test string(l) == "l_l"

    # UnitConversion nodes have no capacity, OPEX or emissions of their own
    u = RefConversion("u", Dict(NG => 1), Dict(Power => 1), EMB.Data[])
    @test !EMB.has_capacity(u)
    @test !EMB.has_opex(u)
    @test !EMB.has_emissions(u)
end

@testitem "API - DeblendNode data accessors" begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks

    H2 = ResourcePressure("H2", 0.0)
    CH4 = ResourcePressure("CH4", 0.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    args = ("d", FixedProfile(5), FixedProfile(0), FixedProfile(0), Dict(Blend => 1),
        Dict(Blend => 1, H2 => 1))

    n = DeblendNode(args..., DeblendData(0.5, 0.9))
    @test EMGN.max_extract_fraction(n) == 0.5
    @test EMGN.psa_efficiency(n) == 0.9

    # Without DeblendData the accessors fail with a clear error
    bare = DeblendNode(args..., EMB.Data[])
    @test_throws ErrorException EMGN.max_extract_fraction(bare)
    @test_throws ErrorException EMGN.psa_efficiency(bare)
end

@testitem "API - PWA from a link, JSON round trip and fit check" setup = [EMGNSetup] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using TimeStruct
    using PiecewiseAffineApprox
    const EMGN = EnergyModelsGasNetworks

    EMGNSetup.setup_pwa!()
    H2 = ResourcePressure("H2", 0.0)
    CH4 = ResourcePressure("CH4", 0.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    pd = PressureLinkData(0.24, 100.0, 60.0)
    bd = BlendLinkData{ResourcePressure{Float64}}(Blend, Dict(H2 => 2.016),
        Dict(H2 => 0.0), 0.2, 0.0, Dict(CH4 => 16.04))
    src =
        RefSource("s", FixedProfile(1), FixedProfile(0), FixedProfile(0), Dict(Blend => 1))
    snk = RefSink("k", FixedProfile(1),
        Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1)), Dict(Blend => 1))
    l = CapDirect("l", src, snk, Linear(), FixedProfile(10), [pd, bd])

    pwa = EMGN.get_pwa(pd, bd, EMGNSetup.mip_optimizer())
    x = (90.0, 70.0, 0.1)
    @test PiecewiseAffineApprox.evaluate(EMGN.get_pwa(l, EMGNSetup.mip_optimizer()), x) ≈
          PiecewiseAffineApprox.evaluate(pwa, x)

    fn = tempname() * ".json"
    EMGN.write_to_json(fn, pwa)
    @test PiecewiseAffineApprox.evaluate(EMGN.read_from_json(fn), x) ≈
          PiecewiseAffineApprox.evaluate(pwa, x)
    rm(fn)

    # The fitted PWA does not underestimate the pure-CH₄ Weymouth flow by more than 10 %
    exact = sqrt(0.24 * (90.0^2 - 70.0^2))
    @test EMGN._pwa_fit_ok(pwa, [(90.0, 70.0, 0.0)], [exact])
end

@testitem "API - PWA rejects a pressure step coarser than the pressure range" setup =
    [EMGNSetup] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using TimeStruct
    const EMGN = EnergyModelsGasNetworks

    H2 = ResourcePressure("H2", 0.0)
    CH4 = ResourcePressure("CH4", 0.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    pd = PressureLinkData(0.24, 100.0, 60.0)
    bd = BlendLinkData{ResourcePressure{Float64}}(Blend, Dict(H2 => 2.016),
        Dict(H2 => 0.0), 0.2, 0.0, Dict(CH4 => 16.04))
    try
        # 60:35:100 has two levels only
        EMGNSetup.setup_pwa!(; step = 35)
        @test_throws ArgumentError EMGN.get_pwa(pd, bd, EMGNSetup.mip_optimizer())
    finally
        EMGNSetup.setup_pwa!()
    end
end
