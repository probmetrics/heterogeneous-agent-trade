
include("ha-trade.jl")
using MINPACK
import DataFrames


haparams = model_params()

d, τ, A = make_trade_params(1.95, 0.0, 1.0, 8)

inital_tradeparams = trade_params(A = A, τ = τ, d = d)
             
Ncntry = inital_tradeparams.Ncntry

new_τ = deepcopy(inital_tradeparams.τ)
new_τ[1,2] = 0.10
new_τ[2,1] = 0.10

T = 25

τ_path = Array{Array{Float64}}(undef, 5)
fill!(τ_path, inital_tradeparams.τ)

n_path = Array{Array{Float64}}(undef, 20)
fill!(n_path, new_τ  )

τ_path = [τ_path; n_path]

@assert length(τ_path) == T

###############################################################################################
# STEP 1 Solve for initial equillibrium



R = 1.002

f(x) = ha_trade_equilibrium(x, R, haparams, inital_tradeparams )

function f!(fvec, x)
    
      fvec .= f(x)
  
end

W = Array{eltype(Float64)}(undef, Ncntry)
fill!(W, 1.0)

τ_revenue = Array{eltype(Float64)}(undef, Ncntry)
fill!(τ_revenue, 0.0)

initial_x = [W; τ_revenue]

n = length(initial_x)
diag_adjust = n - 1

solint = fsolve(f!, initial_x, show_trace = true, method = :hybr;
      ml=diag_adjust, mu=diag_adjust,
      diag=ones(n),
      mode= 1,
      tol=1e-5,
       )

println(" ")
println(solint)
println(" ")

output_int = ha_trade_equilibrium(solint.x, R, haparams , inital_tradeparams, display = true)[2]

Wint, τ_rev_int, Rint = unpack_solution(solint.x, R, Ncntry)

dist_int = collect_intial_conditions(Wint, τ_rev_int, R, haparams, inital_tradeparams )


# ###############################################################################################
# ###############################################################################################
# # STEP 2 Solve for final ss equillibrium

tparams_end = trade_params(A = A, d = d, τ = τ_path[end])

f(x) = ha_trade_equilibrium(x, R, haparams , tparams_end )

function f!(fvec, x)
    
      fvec .= f(x)
  
end

sol_end = fsolve(f!, initial_x, show_trace = true, method = :hybr;
      ml=diag_adjust, mu=diag_adjust,
      diag=ones(n),
      mode= 1,
      tol=1e-5,
       )

println(" ")
println(sol_end)
println(" ")
       
Wend, τ_rev_end, Rend = unpack_solution(sol_end.x, R, Ncntry)
       

# # ###############################################################################################
# # ###############################################################################################
# # # STEP 3 Solve for PATH

W = repeat(Wend, T)
τ_rev = repeat(τ_rev_end, T)


hh_end = collect_end_conditions(Wend, τ_rev_end, Rend, haparams, tparams_end )

trade_path = Array{trade_params}(undef,T)

for xxx = 1:T

      trade_path[xxx] = trade_params(A = A, d = d, τ = τ_path[xxx])

end

initial_x = [W; τ_rev]

f(x)  = transition_path_FixedR(x, R[1], R[1], trade_path, dist_int, hh_end, haparams);

function f!(fvec, x)
    
      fvec .= f(x)
  
end

sol_path = fsolve(f!, initial_x, show_trace = true, method = :hybr;
      ml=diag_adjust, mu=diag_adjust,
      diag=ones(n),
      mode= 1,
       )

println(" ")
println(sol_path)
println(" ")

path_stats = transition_path_FixedR(sol_path.x, R[1], R[1], 
            trade_path, dist_int, hh_end, haparams, display = true)[3]

df = make_dataset(path_stats, output_int, R[1], T)








