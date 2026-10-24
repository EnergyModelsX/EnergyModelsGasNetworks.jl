@testmodule EMGNSetup begin
    using EnergyModelsGasNetworks
    using HiGHS
    using SCIP
    using JuMP
    using MathOptInterface

    const MOI = MathOptInterface

    # Pressure step for the PWA grids in the tests. A coarse grid keeps each fit to a few
    # seconds; tests that check PWA accuracy set their own step.
    const PWA_STEP = 20

    function mip_optimizer()
        return optimizer_with_attributes(HiGHS.Optimizer, MOI.Silent() => true)
    end

    function scip_optimizer()
        return optimizer_with_attributes(
            SCIP.Optimizer, "display/verblevel" => 0, "limits/gap" => 0.0,
        )
    end

    """
        setup_pwa!(; step = PWA_STEP)

    Reset the global PWA settings, so that a test item does not depend on the settings left
    by an earlier item in the same process.
    """
    function setup_pwa!(; step = PWA_STEP)
        set_optimizer_pwa!(mip_optimizer())
        set_step_pressure!(step)
        set_clamp_pwa_intercepts!(true)
        return nothing
    end
end
