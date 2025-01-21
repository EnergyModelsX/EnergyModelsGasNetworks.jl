using DataFrames

TEST_ATOL = 1e-6
function optimize(m; nlp_constraints=true)
    
    if nlp_constraints
        nl_solver = optimizer_with_attributes(Ipopt.Optimizer, MOI.Silent() => true, "sb" => "yes")
        mip_optimizer = optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true)
        optimizer = optimizer_with_attributes(
            Alpine.Optimizer,
            "nlp_solver" => nl_solver,
            "mip_solver" => mip_optimizer,
        )
    else
        optimizer = HiGHS.Optimizer
    end

    set_optimizer(m, optimizer)
    # set_optimizer_attribute(m, MOI.Silent(), false)
    optimize!(m)
    return m
end

function df_variable(m, element::Symbol)
    val = Containers.rowtable(value, m[element])

    return DataFrame(val)
end

function calculate_linearise_pressures()
    P_min = 30.0  # example minimum pressure
    P_max = 70.0  # example maximum pressure
    n = 5         # number of points

    pressures = range(P_min, P_max, length=n)
    pairs = [(p1, p2) for p1 in pressures, p2 in pressures if p1 > p2]

    return pairs
end