# Sesi.jl
This repository contains supplementary code and data for "Grid, carbon and economic case for electrified district-scale heat recovery with thermal storage", by J.A. de Chalendar, P.W. Glynn, and S.M. Benson:
* The Sesi.jl module
* The data folder contains all necessary data, and outputs will be generated here by default
* The jl_scripts folder contains julia scripts that can be used to regenerate the results in
* The py_notebooks folder contains jupyter notebooks that can be used to regenerate the figures in

*Installation instructions*
The optimization model was implemented in the [Julia](https://julialang.org) programming language using the [JuMP](https://github.com/JuliaOpt/JuMP.jl) package and solved using [Gurobi](https://gurobi.com), a commercial solver (another solver can be used, cf. the JuMP documentation for how to do that). Data pre- and post-processing was done using [Python](https://python.org). The `jl_scripts/setup.jl` file gives the Julia requirements and the file `py_notebook/requirements.txt` gives the Python requirements.

*Running the code*
The optimization models can be built and solved from the scripts in the `jl_scripts` directory, that use the Sesi.jl module (in the directory with the same name). The `setup.jl` script should be run first to make sure Julia packages are pinned to the correct versions. Jupyter notebooks in the `py_notebooks` can be used to regenerate the figures in the paper.

Before running either the optimization scripts or the pre/post-processing notebooks, the `REPO_PATH` environment variable should be set and point to this repository. 

The optimization scripts can be run in batch by using the `run.sh` bash script.

*Data*
The `data` folder contains all of the necessary data to regenerate results. Outputs from running the code will be generated here by default as well, in the `jl_out` folder. We detail the data sources below:
* CAISO grid mix data: generation data from the CAISO balancing area was scraped from this URL `http://content.caiso.com/green/renewrpt/%Y%m%d_DailyRenewablesWatch.txt`, where `%Y%m%d` is replaced with the date that we would like to scrape.
* Energy and price data from the Stanford Energy Systems Innovations project was collected at Stanford University and is provided in the `data` folder.