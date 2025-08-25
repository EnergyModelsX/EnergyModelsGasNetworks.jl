
TEST_ATOL = 1e-6
function optimize(m; nlp_constraints=true)
    
    if nlp_constraints
        nl_solver = optimizer_with_attributes(Ipopt.Optimizer, MOI.Silent() => true, "sb" => "yes")
        mip_optimizer = optimizer_with_attributes(HiGHS.Optimizer, MOI.Silent() => true)
        minlp_optimizer = optimizer_with_attributes(Juniper.Optimizer, MOI.Silent() => true, "mip_solver" => mip_optimizer, "nl_solver" => nl_solver)
        optimizer = optimizer_with_attributes(
            Alpine.Optimizer,
            "nlp_solver" => nl_solver,
            "mip_solver" => mip_optimizer,
            "minlp_solver" => minlp_optimizer,
            "rel_gap" => 20.00
        )
    else
        optimizer = HiGHS.Optimizer
    end

    set_optimizer(m, optimizer)
    # set_optimizer_attribute(m, MOI.Silent(), false)
    optimize!(m)
    return m
end