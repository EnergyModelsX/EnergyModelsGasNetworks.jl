using DataFrames

TEST_ATOL = 1e-6
function optimize(m)
    optimizer = Xpress.Optimizer
    set_optimizer(m, optimizer)
    set_optimizer_attribute(m, MOI.Silent(), true)
    optimize!(m)
    return m
end

function df_variable(m, element::Symbol)
    val = Containers.rowtable(value, m[element])

    return DataFrame(val)
end