include("ha-trade-environment.jl")
include("ha-trade-solution.jl")
include("ha-trade-helper-functions.jl")
include("static-trade-environment.jl")
using MINPACK
using Plots
using CSV
using DataFrames

####################################################################################
####################################################################################
println(" ")
println(" ")
println("########### computing initial eq ################")
println(" ")

Ncntry = 19

dftrade = DataFrame(CSV.File("ek-trade.csv"))

d = reshape(dftrade.d, Ncntry,Ncntry)

df = DataFrame(CSV.File("solution.csv"))

initial_x = [df.wage[2:end]; df.interest_rate]

#initial_x =[df.TFP[2:end]; 1.02*ones(Ncntry)]

TFP = df.TFP
L = df.L

Ncntry = size(d)[1]

mdl_prm = world_model_params(Ncntry = Ncntry, Na = 100, 
γ = 1.5, ϕ = 2.0, amax = 8.0, σϵ = 0.25, d = d, TFP = TFP, L = L)

f(x) = world_equillibrium(x, mdl_prm, hh_solution_method = "itteration", stdist_sol_method = "itteration");

function f!(fvec, x)

    fvec .= f(x)

end

###################################################################

n = length(initial_x)
diag_adjust = n - 1

sol = fsolve(f!, initial_x, show_trace = true, method = :hybr;
      ml=diag_adjust, mu=diag_adjust,
      diag=ones(n),
      mode= 1,
      tol=1e-5,
       )

print(sol)

Wsol = [1.0; sol.x[1:Ncntry-1]]
Rsol = sol.x[Ncntry:end]

Y, tradeflows, A_demand, tradeshare, hh, dist = world_equillibrium(Rsol,
    Wsol, mdl_prm, hh_solution_method = "itteration");

plot(log.(vec(tradeshare)), log.(dftrade.tradesharedata), seriestype = :scatter)

dftrade_model_data = DataFrame(
    trademodel = log.(vec(tradeshare)),
    tradedata = log.(dftrade.tradesharedata)
     );

CSV.write("trade_model_data.csv", dftrade_model_data)

# ####################################################################################
println(" ")
println(" ")
println("########### computing counter factual eq ################")
println(" ")

Δ_d = 0.01

d_prime =  1.0 .+ (d .- 1.0).*(1.0 - Δ_d)

Δ_mdl_prm = world_model_params(Ncntry = Ncntry, Na = 100, 
γ = 1.5, ϕ = 2.0, amax = 8.0, σϵ = 0.25, d = d_prime, TFP = TFP, L = L)

f(x) = world_equillibrium(exp.(x), Δ_mdl_prm, hh_solution_method = "itteration", stdist_sol_method = "itteration");

function f!(fvec, x)

    fvec .= f(x)

end

#initial_x =[ones(Ncntry-1); 1.02*ones(Ncntry)]

###################################################################

n = length(initial_x)
diag_adjust = n - 1

Δ_sol = fsolve(f!, log.(initial_x), show_trace = true, method = :hybr;
      ml=diag_adjust, mu=diag_adjust,
      diag=ones(n),
      mode= 1,
      tol=1e-5,
       )

print(Δ_sol)

Δ_Wsol = exp.([0.0; Δ_sol.x[1:Ncntry-1]])
Δ_Rsol = exp.(Δ_sol.x[Ncntry:end])

Δ_Y, Δ_tradeflows, Δ_A_demand, Δ_tradeshare, Δ_hh, Δ_dist = world_equillibrium(Δ_Rsol,
Δ_Wsol, Δ_mdl_prm, hh_solution_method = "itteration");

∂W = welfare_by_state(hh, Δ_hh, 19, mdl_prm.σϵ)

dfwelfare = make_welfare_dataframe(∂W, mdl_prm)

CSV.write("welfare-US-%1.csv", dfwelfare)

global_trade_elasticity =  (log.(Δ_tradeshare ./ diag(Δ_tradeshare)) .- log.(tradeshare ./ diag(tradeshare))) ./ Δ_d

