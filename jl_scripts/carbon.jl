# NE - Run carbon cases
push!(LOAD_PATH, joinpath(ENV["REPO_PATH"], "Sesi.jl/src"))

using CSV
using JuMP
using IterTools
using JSON
using DataFrames

import Sesi # import vs using so I can reload this from the REPL

reload("Sesi")

include("utils.jl")

save = false
verb = true

if verb
    println(repeat("#",80))
    println("Starting carbon analysis")
    println(repeat("#",80))
end

folderIn = joinpath(ENV["REPO_PATH"], "dataR1/jl_in/")

results = Dict()
prices = Dict()
costs = Dict()
reductions = Dict()
#fileNms = ["jlInput_x0.csv","jlInput_2018.csv", "jlInput_x2.csv"]
fileNms = ["jlInput_x0.csv", "jlInput_x1.csv", "jlInput_x2.csv",
            "jlInput_x4.csv","jlInput_x6.csv", "jlInput_2018.csv"]

for dc_ratio in [1., 0.5, 0.1]
if verb
println("Dealing with demand ratio " * string(dc_ratio))
end

folderOut = joinpath(ENV["REPO_PATH"],
                     "dataR1/jl_out/demand_" * string(dc_ratio))

for sc in fileNms
    prices[sc] = []
    costs[sc] = []
    reductions[sc] = []

    println("Dealing with " * sc)
    results[sc] = Dict()
    fileNm = folderIn * sc

    carbonPrice_lst = [0., 50., 75., 100., 150., 200., 300., 500., 1000.,
        10000., 100000.]
    for carbonPrice in carbonPrice_lst
        sesi, p, f = build_model(fileNm; verb=false, startDate=Date(2016,1,1),
            endDate=Date(2016,12,31), carbonPrice=carbonPrice, dc_ratio=dc_ratio)
        status = solve(sesi)
        println(status)
        results[sc][carbonPrice] = Sesi.campus_bill(sesi, f, p, verb=0)
        if verb
            @printf("carbon price: %d - %.2f\n",carbonPrice,
                carbon_cost(results, sc, 0., carbonPrice))
            @printf("carbon reduction: %d - %.2f\n",carbonPrice,
                carbon_reduction(results, sc, 0., carbonPrice))
            @printf("sanity : %d - %.2f\n",carbonPrice,
                sanity(results, sc, 0., carbonPrice))
        end
        push!(prices[sc], carbonPrice)
        push!(costs[sc], carbon_cost(results, sc, 0., carbonPrice))
        push!(reductions[sc], carbon_reduction(results, sc, 0., carbonPrice))
        if save
            Sesi.save_data(sesi, f, p, folderOut * sc[1:end-4] * "_"
                * string(carbonPrice))
        end
    end
end

json_data = json([results, prices, costs, reductions]);
open(folderOut * "ne_carbon_json_data", "w") do fw
    write(fw, json_data)
end
end
