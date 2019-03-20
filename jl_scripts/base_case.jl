# NE - run base case results
push!(LOAD_PATH, joinpath(ENV["REPO_PATH"], "Sesi.jl/src"))

using CSV
using JuMP
using IterTools
using JSON
using DataFrames

import Sesi # import vs using so I can reload this from the REPL

include("jl_utils.jl")

save = false
verb = true

folderIn = joinpath(ENV["REPO_PATH"], "data/jl_in/")
folderOut = joinpath(ENV["REPO_PATH"], "data/jl_out/")

fileNm = folderIn * "jlInput.csv"

if verb
    println(repeat("#",80))
    println("Starting base case")
    println(repeat("#",80))
end

# Build JuMP model
sesi, p, f = build_model(fileNm; verb=false, startDate=Date(2016,1,1),
    endDate=Date(2016,12,31))

# Solve JuMP model
status = solve(sesi)
println(status)

if status == :Optimal

if save
    Sesi.save_data(sesi, f, p, folderOut * "base")
end
end
