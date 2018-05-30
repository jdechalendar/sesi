# Setup script
println(repeat("#", 80))
println("Running setup script")
println(repeat("#", 80))

if VERSION < v"0.6"
    warn("This code was written and tested with julia version 0.6.2")
end
Pkg.pin("JuMP", v"0.18.1")
Pkg.pin("Gurobi", v"0.4.0")
Pkg.pin("CSV", v"0.2.4")
Pkg.pin("DataFrames", v"0.11.6")
Pkg.pin("IterTools", v"0.2.1")
Pkg.pin("JSON", v"0.17.2")

if !haskey(ENV, "REPO_PATH")
    warn("REPO_PATH variable not set!")
end
