struct household{T}
    Tv::Array{T} # value function
    asset_policy::Array{T} # asset_policy
    work_policy::Array{T} # work_policy
end

struct distribution{T}
    Q::Array{T} # transition matrix
    λ::Array{T} # λ
    state_index::Array{Tuple{Int64, Int64}} # index of states, lines up with λ
end

##########################################################################
# functions used to find a solution to the households problem and then
# the stationary equillibrium. 
# Keep the idea in mind seperate model vs. solution technique.
# so this files is about solution. Model enviornment is in envronment.jl file

function clear_asset_market(Pces, W, τ_rev, R, model_params; tol_vfi = 1e-6, tol_dis = 1e-10, 
    vfi_solution_method = "nl-fixedpoint", stdist_sol_method = "nl-fixedpoint")

@assert model_params.ϕ > 0.0

hh = solve_household_problem(Pces, W, τ_rev, R, model_params; tol = tol_vfi, solution_method = vfi_solution_method)

dist = make_stationary_distribution(hh, model_params, tol = tol_dis, solution_method = stdist_sol_method)

output = aggregate(Pces, W, τ_rev, R, hh, dist, 1.0, model_params)

return output.Aprime

end

function clear_asset_market(Pces, W, 
    τ_rev, R::ForwardDiff.Dual, model_params; tol_vfi = 1e-6, tol_dis = 1e-10)
# for some reason NLsolve fixedpoint does not work well with ForwardDiff.Dual numbers.
# the work around is to use multiple dispatch. So if R a dual number...then revert to 
# basic itterative methods to solve hh problem and stationary distribution.

@assert model_params.ϕ > 0.0

hh = solve_household_problem(Pces, W, τ_rev, R, model_params; tol = tol_vfi, solution_method = "vfi-itteration")

dist = make_stationary_distribution(hh, model_params, tol = tol_dis, solution_method = "itteration")

output = aggregate(Pces, W, τ_rev, R, hh, dist, 1.0, model_params)

return output.Aprime

end

##########################################################################
##########################################################################

function compute_eq(Pces, W::ForwardDiff.Dual, τ_rev::ForwardDiff.Dual, 
    R::ForwardDiff.Dual, model_params; tol_vfi = 1e-6, tol_dis = 1e-10)
# Does everything...
# (1) Sovles hh problem
# (2) Constructs stationary distribution
hh = solve_household_problem(Pces, W, τ_rev, R, model_params; tol = tol_vfi, solution_method = "vfi-itteration")

dist = make_stationary_distribution(hh, model_params, tol = tol_dis, solution_method = "itteration")

return hh, dist

end

function compute_eq(Pces, W, τ_rev, R, model_params; tol_vfi = 1e-6, tol_dis = 1e-10, 
    vfi_solution_method = "nl-fixedpoint", stdist_sol_method = "nl-fixedpoint")
# Does everything...
# (1) Sovles hh problem
# (2) Constructs stationary distribution
hh = solve_household_problem(Pces, W, τ_rev, R, model_params; tol = tol_vfi, solution_method = vfi_solution_method)

dist = make_stationary_distribution(hh, model_params, tol = tol_dis, solution_method = stdist_sol_method)

return hh, dist

end

##########################################################################
##########################################################################

function solve_household_problem(Pces, W, τ_rev, R, model_params; tol = 10^-6, solution_method = "nl-fixedpoint")

    if solution_method == "nl-fixedpoint"

        solution, u = value_function_fixedpoint(Pces, W, τ_rev, R, model_params; tol = tol)

        Tv = solution.zero

    elseif solution_method == "vfi-itteration"

        Tv, u = value_function_itteration(Pces, W, τ_rev, R, model_params; tol = tol, Niter = 500)
        
    end
    
    @unpack Na, Nshocks,
     mc, β, σa, σw = model_params

    return bellman_operator_policy(Tv, u, mc.p, β, σa, σw);

end

##########################################################################
##########################################################################

function make_stationary_distribution(household, model_params; tol = 1e-10, solution_method = "nl-fixedpoint") 

@unpack Na, Nshocks, statesize = model_params

state_index = Array{Tuple{eltype(Na), eltype(Na)}}(undef, statesize, 1)

Q = Array{eltype(household.asset_policy)}(undef, statesize, statesize)

make_Q!(Q, state_index, household.asset_policy, household.work_policy, model_params)

if solution_method == "nl-fixedpoint"

    g(λ) = law_of_motion(λ, transpose(Q))

    initialvalue = zeros(size(Q)[1], 1)

    initialvalue .= 1.0 / size(Q)[1]

    solution = fixedpoint(g, initialvalue, ftol = tol, method = :anderson)

    λ = solution.zero

elseif solution_method == "itteration"

    λ = itterate_stationary_distribution(Q; tol = 1e-10)

end

return distribution(Q, λ, state_index)

end

##########################################################################
##########################################################################
function itterate_stationary_distribution(Q; tol = 1e-10, Niter = 5000) 
    # this is faster than the quant econ canned routine
    # from lyon-waugh implementation. Not as fast as using
    # NLsolve fixedpoint routine below.
    
    # Takes the transition matrix above then we know a stationary distribution
    # must satisfy the fixed point relationsip λ = Q'*λ  
    
    λ = zeros(size(Q)[1], 1)
    λ = convert(Array{eltype(Q)}, λ)
    
    λ .= 1.0 / size(Q)[1]
    
    Lnew = similar(λ)
    
    for iter in 1:Niter
        
        #Lnew = transpose(Q) * λ
        
        Lnew = law_of_motion(λ, transpose(Q))
        #this ordering is also better in julia
        # than my matlab implementation of Q*λ (1, na*nshock)
                
        err = maximum(abs, λ - Lnew)
        
        copy!(λ, Lnew)
        # this surprisingly makes a big difference
        # but in the vfi it causes a slowdown?
        
        err < tol && break

        if iter == Niter

            println("distribution may not have converged")
            println("check the situation")
    
        end
        
    end

    return λ

end

##########################################################################
##########################################################################


function value_function_itteration(Pces, W, τ_rev, R, model_params; tol = 10^-6, Niter = 500)
    # this is the boiler plate vfi routine (1) make grid (2) itterate on 
    # bellman operator untill convergence. 
    #
    # as Fast/ ~faster than Matlab (but nothing is multithreaded here)
    # fastest is using nlsove fixed point to find situation where
    # v = bellman_operator(v)
    
    @unpack Na, Nshocks, Woptions, β, mc, σw = model_params

    u = Array{eltype(R)}(undef, Na, Na, Nshocks, Woptions)

    make_utility!(u, Pces, W, τ_rev, R, model_params)

    v = -ones(Na, Nshocks) / (1-β); #initial value
    
    v = convert(Array{eltype(u)}, v)
    Tv = similar(v)

    for iter in 1:Niter
        
        Tv = bellman_operator_upwind(v, u, mc.p, β, σw) 
        #there is some advantage of having it
        # explicity, not always recreating the Tv 
        # array in the function
    
        err = maximum(abs, Tv - v)

        err < tol && break
                
        v = copy(Tv)

        if iter == Niter

          println("value function may not have converged")
          println("check the situation")
        end

    end

    return Tv, u
    
end

##########################################################################
##########################################################################

function policy_function_itteration(W, R, model_params; tol = 10^-6, Niter = 500)
    # this is the boiler plate vfi routine (1) make grid (2) itterate on 
    # bellman operator untill convergence. 
    #
    # as Fast/ ~faster than Matlab (but nothing is multithreaded here)
    # fastest is using nlsove fixed point to find situation where
    # v = bellman_operator(v)
    
    @unpack Na, Nshocks = model_params

    gc = ones(Na, Nshocks)

    Kgc = similar(gc)

    for iter in 1:Niter
        
        Kgc = coleman_operator(gc, R, W, model_params)
        #there is some advantage of having it
        # explicity, not always recreating the Tv 
        # array in the function
    
        err = maximum(abs, Kgc - gc)

        err < tol && break
                
        gc = copy(Kgc)

        if iter == Niter

          println("value function may not have converged")
          println("check the situation")
        end

    end

    return Kgc
    
end

##########################################################################
##########################################################################

function policy_function_fixedpoint(W, R, model_params; tol = 10^-6)

    @unpack Na, Nshocks = model_params

    gco = ones(Na, Nshocks)
    
# define the inline function on the bellman operator. 
# so the input is v (other stuff is fixed)
    
    K(gc) = coleman_operator(gc, R, W, model_params)

    solution = fixedpoint(K, gco, ftol = tol, method = :anderson);
    
    if solution.f_converged == false
        println("did not converge")
    end

    return solution

end

##########################################################################
##########################################################################

function value_function_fixedpoint(Pces, W, τ_rev, R, model_params; tol = 10^-6)

    @unpack Na, Nshocks, Woptions, β, mc, σw = model_params

    u = Array{eltype(R)}(undef, Na, Na, Nshocks, Woptions)
    
    make_utility!(u, Pces, W, τ_rev, R, model_params)

# define the inline function on the bellman operator. 
# so the input is v (other stuff is fixed)
    
    T(v) = bellman_operator_upwind(v, u, mc.p, β, σw)

    Vo = -ones(Na, Nshocks) / (1-β); #initial value
    Vo = convert(Array{eltype(u)}, Vo)

    solution = fixedpoint(T, Vo, ftol = tol, method = :anderson);
    
    if solution.f_converged == false
        println("did not converge")
    end

    return solution, u

end


##########################################################################
##########################################################################



