include("ha-trade-environment.jl")
include("ha-trade-solution.jl")
include("ha-trade-helper-functions.jl")
include("static-trade-environment.jl")
include("gravity-tools.jl")
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

df = DataFrame(CSV.File("solution-fg.csv"))

initial_x = [df.wage[2:end]; 1.00]

TFP = df.TFP
L = df.L

Ncntry = size(d)[1]

# mdl_prm = world_model_params(Ncntry = Ncntry, Na = 100, 
# γ = 1.01, ϕ = 2.0, amax = 8.0, σϵ = 0.25, d = d, TFP = TFP, L = L)

hh_prm = household_params(Ncntry = Ncntry, Na = 100, β = 0.92,
γ = 1.5, ϕ = 0.5, amax = 8.0, σϵ = 0.25)

cntry_prm = country_params(Ncntry = Ncntry, d = d, TFP = TFP, L = L)

f(x) = world_equillibrium_FG(x, hh_prm, cntry_prm);

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
      tol=1e-5
       )

print(sol)

Wsol = [sol.x[1:(Ncntry - 1)]; 1.0]

Rsol = ones(Ncntry)*sol.x[end]

Y, tradeflows, A_demand, tradeshare, hh, dist = world_equillibrium(Rsol,
    Wsol, hh_prm, cntry_prm);


# ###################################################################
# dftrade = DataFrame(CSV.File("../../ek-data/ek-data.csv"))

# dftrade.trade = parse.(Float64, dftrade.trade)
#     # forsome reason, now it reads in as a "String7"
    
# dflang = DataFrame(CSV.File("../../ek-data/ek-language.csv"))
    
# dflabor = DataFrame(CSV.File("../../ek-data/ek-labor.csv"))
    
# filter!(row -> ~(row.trade ≈ 1.0), dftrade);
    
# filter!(row -> ~(row.trade ≈ 0.0), dftrade);
    
# dftrade = hcat(dftrade, dflang);
    
#     #dfcntryfix = select(dftrade,Not("trade"))
# dfcntryfix = DataFrame(CSV.File("../../ek-data/ek-cntryfix.csv"))
#     # these are the fixed characteristics of each country...


# trademodel = log.(normalize_by_home_trade(tradeshare, Ncntry)')

# dfmodel = DataFrame(trade = vec(drop_diagonal(trademodel, Ncntry)))

# dfmodel = hcat(dfmodel, dfcntryfix)

# plot(dfmodel.trade, dftrade.trade, seriestype = :scatter, alpha = 0.75,
#     xlabel = "model",
#     ylabel = "data",
#     legend = false)

# gravity(dfmodel, trade_cost_type =  "ek")

###################################################################

# plot(log.(vec(tradeshare)), log.(dftrade.tradesharedata), seriestype = :scatter)

# dftrade_model_data = DataFrame(
#     trademodel = log.(vec(tradeshare)),
#     tradedata = log.(dftrade.tradesharedata)
#      );

# # dfsolution = DataFrame(
# #         wage = Wsol,
# #         R = Rsol,
# #         TFP = TFP,
# #         L = L
# #          );

# # CSV.write("solution-fg.csv", dfsolution)

# rootfile = "../../notebooks/output/"

# CSV.write(rootfile*"trade_model_data_fg_log.csv", dftrade_model_data)

# hh_df = make_hh_dataframe(dist, hh, 19, Rsol, Wsol, mdl_prm)

# CSV.write(rootfile*"household_data_pre_fg_log.csv", hh_df)

# # ####################################################################################
# println(" ")
# println(" ")
# println("########### computing counter factual eq ################")
# println(" ")


# country = 11
# country_name = "-JPN"

# Δ_d = 0.10

# d_prime = deepcopy(d)
# d_prime[19,country] =  (d[19,country]).*(1.0 - Δ_d)


# Δ_mdl_prm = world_model_params(Ncntry = Ncntry, Na = 100, 
# γ = 1.01, ϕ = 2.0, amax = 8.0, σϵ = 0.25, d = d_prime, TFP = TFP, L = L)

# # ###################################################################################
# # # Fix prices, change d, see what happens...

# Δp_Y, Δp_tradeflows, Δp_A_demand, Δp_tradeshare, Δp_hh, Δp_dist = world_equillibrium(Rsol,
# Wsol, Δ_mdl_prm, hh_solution_method = "itteration");

# ∂W, ∂logW = welfare_by_state(hh, Δp_hh, 19, Δ_mdl_prm.σϵ)

# dfwelfare = make_welfare_dataframe(∂W, ∂logW, Δ_mdl_prm)

# root = rootfile*"welfare-US"

# CSV.write(root*country_name*"-fix-p-fg-log.csv", dfwelfare)

# hh_df = make_hh_dataframe(Δp_dist, Δp_hh, 19, Rsol, Wsol, Δ_mdl_prm)

# root = rootfile*"household-data-US"

# CSV.write(root*country_name*"-fix-p-fg-log.csv", hh_df)


# # ###################################################################################
# f(x) = world_equillibrium_FG(exp.(x), Δ_mdl_prm, hh_solution_method = "itteration", stdist_sol_method = "itteration");

# function f!(fvec, x)

#     fvec .= f(x)

# end

# ###################################################################

# n = length(initial_x)
# diag_adjust = n - 1

# Δ_sol = fsolve(f!, log.(initial_x), show_trace = true, method = :hybr;
#       ml=diag_adjust, mu=diag_adjust,
#       diag=ones(n),
#       mode= 1,
#       tol=1e-5,
#        )

# print(Δ_sol)

# Δ_Wsol = exp.([0.0; Δ_sol.x[1:Ncntry-1]])
# Δ_Rsol = ones(Ncntry)*exp.(Δ_sol.x[end])

# Δ_Y, Δ_tradeflows, Δ_A_demand, Δ_tradeshare, Δ_hh, Δ_dist = world_equillibrium(Δ_Rsol,
# Δ_Wsol, Δ_mdl_prm, hh_solution_method = "itteration")

# ∂W, ∂logW = welfare_by_state(hh, Δ_hh, 19, Δ_mdl_prm.σϵ)

# dfwelfare = make_welfare_dataframe(∂W, ∂logW, Δ_mdl_prm)

# root = rootfile*"welfare-US"
# CSV.write(root*country_name*"-ge-fg-log.csv", dfwelfare)

# hh_df = make_hh_dataframe(Δ_dist, Δ_hh, 19, Δ_Rsol, Δ_Wsol, Δ_mdl_prm)

# root = rootfile*"household-data-US"
# CSV.write(root*country_name*"-ge-fg-log.csv", hh_df)

# global_trade_elasticity =  (log.(Δ_tradeshare ./ diag(Δ_tradeshare)) .- 
#     log.(tradeshare ./ diag(tradeshare))) ./ (log.(d_prime) .- log.(d))

