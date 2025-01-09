using DataFrames

TEST_ATOL = 1e-6
function optimize(m; nlp_constraints=true)
    
    if nlp_constraints
        optimizer = Xpress.Optimizer
    else
        optimizer = HiGHS.Optimizer
    end

    set_optimizer(m, optimizer)
    set_optimizer_attribute(m, MOI.Silent(), false)
    optimize!(m)
    return m
end

function df_variable(m, element::Symbol)
    val = Containers.rowtable(value, m[element])

    return DataFrame(val)
end