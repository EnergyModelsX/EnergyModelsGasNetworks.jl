using PiecewiseAffineApprox

@testset "Generation of PressBlendPipe" begin
	
	# 3 points
	@test_throws Exception PressBlendPipe(
		"Weymouth",
		80, # max_pressure
		HiGHS.Optimizer,
		pin = [50, 63, 70], 
   		pout = [30, 43, 50],
    	h2_fraction = [0.0, 0.05, 0.1],
		M1 = 16.042,
		M2 = 2.016
	)

	presblend_data = PressBlendPipe(
		"Weymouth",
		80, # max_pressure
		HiGHS.Optimizer,
		M1 = 16.042,
		M2 = 2.016
	)

	pwa = EMP.get_pwa(presblend_data)
	@test isa(pwa, PiecewiseAffineApprox.PWAFunc)

	EMP.delete_cache()
end

@testset "Testing Get and Read" begin


    weymouth=58
    pin = [50,  58, 58, 63, 65, 67, 70] 
    pout = [30, 35, 37, 43, 45, 40, 50]
    h2_fraction = [0.0,  0.1, 0.0, 0.05, 0.0, 0.05, 0.1]
	M_ch4 = 16.042 # molecular weight
	M_h2 = 2.016

    z = weymouth_specgrav.(weymouth, pin, pout, h2_fraction, M_ch4, M_h2)
    
	pwa1 = approx(
		FunctionEvaluations(collect(zip(pin, pout, h2_fraction)), z),
		Concave(),
		Cluster(
			; optimizer = HiGHS.Optimizer,
			planes = 10,
			strict = :none,
			metric = :l1,
		))

	fn = EMP.get_input_fn([weymouth, pin, pout, h2_fraction], z)
	EMP.write_to_json(fn, pwa1)

	fn1 = EMP.get_input_fn([weymouth, pin, pout, h2_fraction], z)
	@test isfile(fn1)
	@test pwa1_r = EMP.read_from_json(fn1) !== nothing
end

@testset "Testing No Saving and Get" begin
	M_ch4 = 16.042 # molecular weight
	M_h2 = 2.016

	weymouth = 58
    pin = [50,  58, 58, 63, 65, 67, 70] 
    pout = [30, 35, 37, 43, 45, 40, 50]
    h2_fraction = [0.0,  0.1, 0.0, 0.05, 0.0, 0.05, 0.1]

	f(weymouth, pin, pout, h2_fraction) = sqrt(weymouth) * sqrt(pin^2 - pout^2) / sqrt(M_ch4 * (1 - h2_fraction) + M_h2 * h2_fraction)
    z = f.(weymouth, pin, pout, h2_fraction)

	pwa = approx(
		FunctionEvaluations(collect(zip(pin, pout, h2_fraction)), z),
		Concave(),
		Cluster(
			; optimizer = HiGHS.Optimizer,
			planes = 10,
			strict = :none,
			metric = :l1,
		))
	fn = EMP.get_input_fn([pin, pout, h2_fraction], z)
	# EMP.write_to_json(fn, pwa2)

	fn2 = EMP.get_input_fn([pin, pout, h2_fraction], z)
	@test isfile(fn2) == false

	EMP.delete_cache()
end
