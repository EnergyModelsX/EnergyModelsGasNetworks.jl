using PiecewiseAffineApprox

@testset "Generation of PressBlendPipe" begin
    
    weymouth = 53.7178761089193
    presblend_data = PressBlendPipe(
        "Weymouth",
        80, # max_pressure
        weymouth,
        70,
        30,
        HiGHS.Optimizer
    )

    pwa = EMP.get_pwa(presblend_data)
    @test isa(pwa, PiecewiseAffineApprox.PWAFunc)

    EMP.delete_cache()
end

@testset "Testing Get and Read" begin
    Mᶜᴴ⁴ = 16.042 # molecular weight
    Mᴴ² = 2.016
    weymouth = 53.7178761089193
    
    f(X) = sqrt(weymouth) .* sqrt.(X[:, 1].^2 - X[:, 2].^2) ./ sqrt.(Mᶜᴴ⁴ .* (1 .- X[:, 3]) .+ Mᴴ² .* X[:, 3])
    X1 = EMP._calculate_input(70, 30)
    z1 = f(X1)
    pwa1 = approx(   
            FunctionEvaluations(tuple.(eachcol(X1)...), z1),
            Concave(),
            Cluster(
                ;optimizer = HiGHS.Optimizer,
                planes = 10,
                strict = :none,
                metric = :l1,
        ))
    fn = EMP.get_input_fn(X1, z1)
    EMP.write_to_json(fn, pwa1)

    fn1 = EMP.get_input_fn(X1, z1)
    @test isfile(fn1)
    @test pwa1_r = EMP.read_from_json(fn1) !== nothing
end

@testset "Testing No Saving and Get" begin
    Mᶜᴴ⁴ = 16.042 # molecular weight
    Mᴴ² = 2.016
    weymouth = 53.7178761089193
    f(X) = sqrt(weymouth) .* sqrt.(X[:, 1].^2 - X[:, 2].^2) ./ sqrt.(Mᶜᴴ⁴ .* (1 .- X[:, 3]) .+ Mᴴ² .* X[:, 3])

    X2 = EMP._calculate_input(120, 90)
    z2 = f(X2)
    pwa2 = approx(   
        FunctionEvaluations(tuple.(eachcol(X2)...), z2),
        Concave(),
        Cluster(
            ;optimizer = HiGHS.Optimizer,
            planes = 10,
            strict = :none,
            metric = :l1,
    ))
    fn = EMP.get_input_fn(X2, z2)
    # EMP.write_to_json(fn, pwa2)

    fn2 = EMP.get_input_fn(X2, z2)
    @test isfile(fn2) == false

    EMP.delete_cache()
end