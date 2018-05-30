"""
    getMonthNum(t, f)

Returns month index in simulation
"""
function getMonthNum(t::Int, f::Dict)
    return 1 + (Dates.month(f[:timestamp][t])
        - Dates.month(f[:timestamp][1])
        + 12 * (Dates.year(f[:timestamp][t])
            - Dates.year(f[:timestamp][1])))
end

"""
    findDate(date, dates)

Returns index of first occurence of date in dates.
"""
function findDate(date::Date,
                  dates::Array{Date,1})
    candidates = find(x->x==date, dates)
    if length(candidates) == 0
        error("Could not find date " * string(date) * " in dataset")
    end
    if length(candidates) > 24
        error("More than 24 timestamps for date " * string(date) * "...")
    end
    if length(candidates) < 24
        warn("Less than 24 timestamps for date " * string(date) * " - OK?")
    end
    return candidates[1]
end

function save_data(sesi::JuMP.Model, f::Dict, p::Dict,
    folderNm::String)

    T = f[:T];

    # write results to csv
    output = DataFrame()

    for col in [:gHeater, :eHeater, :hwHeater, :eHRC,
        :hwHRC, :cwHRC, :eChiller, :cwChiller,
        :eGrid, :gGrid, :umHot, :umCold]
        output[col] = getvalue(sesi[col])
    end
    output[:elecCEF] = (output[:eHRC] + output[:eHeater]
                        + output[:eChiller])
    output[:cwStorage] = getvalue(sesi[:cwTank])[1:T-1];
    output[:hwStorage] = getvalue(sesi[:hwTank])[1:T-1];
    #output[:elecSolar] = getvalue(getvariable(sesi, :elecSolar));

    # Go back to UTC for storage
    output[:Date] = f[:timestamp] - Dates.Hour(p[:utc_offset])

    output[:elecCampus] = f[:loadKWH]
    output[:cwLoads] = f[:loadCW]
    output[:hwLoads] = f[:loadHW]
    output[:elecPrice] = f[:elecPrice]

    # rename some variables
    output[:hwHeater] = output[:hwHeater]
    output[:cwChiller] = output[:cwChiller]
    output[:cwHRC] = output[:cwHRC]
    output[:hwHRC] = output[:hwHRC]

    output[:elecGrid] = output[:eGrid]
    output[:gasGrid] = output[:gGrid]
    output[:elecHRC] = output[:eHRC]
    output[:elecChiller] = output[:eChiller]
    output[:elecHeater] = output[:eHeater]

    # make sure we have the write order for output
    cols = [:Date, :elecCEF,:elecCampus,:cwLoads, :hwLoads, :hwStorage,
    :cwStorage, :gHeater, :elecHeater, :hwHeater, :elecHRC, :hwHRC, :cwHRC,
    :elecChiller, :cwChiller, :elecPrice, :elecGrid, :gasGrid, :umHot, :umCold]

    if p[:ev]
        output[:evSOC] = sum(getvalue(sesi[:LevelOfCharge])[:,1:T-1])
        output[:elecEV_in] = getvalue(sesi[:elecEV_in])
        output[:elecEV_out] = getvalue(sesi[:elecEV_out])
        append!(cols, [:evSOC, :elecEV_in, :elecEV_out])
    end

    mkpath(folderNm)
    CSV.write(joinpath(folderNm, "data.csv"), output[cols])

    # write params and forecast to json file
    out_f = f
     # convert to UTC for storage
    if p[:cbp]
        out_f[:timestamp_cbp] = [ts - Dates.Hour(p[:utc_offset])
            for ts in out_f[:timestamp_cbp]]
        out_f[:cbp_bid] = getvalue(sesi[:cbp_bid]) # also store this here
    end
    forecast_json = json(out_f);
    open(joinpath(folderNm, "forecast.json"), "w") do fw
        write(fw, forecast_json)
    end
    params_json = json(p);
    open(joinpath(folderNm, "params.json"), "w") do fw
        write(fw, params_json)
    end
end

"""
    campus_bill(sesi, f, verb)

Calculate campus bill, after an optimization run. This is usually (slightly)
different from the optimization objective (that could include e.g. optimization
constraints). Note that this function also serves as a sanity check - it is
calculated after the optimization, just based on the resulting schedule
"""

function campus_bill(sesi::JuMP.Model, f::Dict, p::Dict; verb::Int=0)

    T = f[:T]
    M = f[:M]
    # startT = f[:startT]
    # endT = f[:endT]
    eGrid = getvalue(sesi[:eGrid])[1:T-1]
    gGrid = getvalue(sesi[:gGrid])[1:T-1]
    umCold = getvalue(sesi[:umCold])[1:T-1]
    umHot = getvalue(sesi[:umHot])[1:T-1]

    elecCEP = 0.
    for var in [:eChiller, :eHeater, :eHRC]
        if haskey(sesi.objDict, var)
            elecCEP = elecCEP + getvalue(sesi[var])[1:T-1]
        end
    end

    elecSolar = 0.;
    if haskey(sesi.objDict, :elecSolar)
        elecSolar = getvalue(sesi[:elecSolar])[1:T-1]
    end

    if p[:sw]
        swHRC = getvalue(sesi[:swHRC])
        swChiller = getvalue(sesi[:swChiller])
        swHeater = getvalue(sesi[:swHeater])
    end

    if p[:ev]
        evDischarge = getvalue(sesi[:evDischarge])
    end

    # bill dictionary contains detailed bill
    bill = Dict();

    bill["objective"] = 0.# recreate objective to make debugging easier

    # note: need to recalculate peak variables "by hand" because they will not
    # always exist in the JuMP model
    peak = zeros(M);
    for t = 1:T-1
        m = getMonthNum(t, f)
        peak[m] = max(peak[m], eGrid[t])
    end

    bill["demandCharge"] = sum(peak .* f[:demandCharge])
    bill["eEnergyCost"] = sum(eGrid .* f[:elecPrice])
    bill["gEnergyCost"] = sum(gGrid .* f[:gasPrice])

    bill["objective"] = bill["gEnergyCost"] + bill["eEnergyCost"]
    if p[:peak]
        bill["objective"] += bill["demandCharge"]
    end

    bill["agg_dollar"] = (bill["eEnergyCost"] + bill["demandCharge"]
                            + bill["gEnergyCost"])

    if haskey(f, :carbonIntensityGrid)
        bill["agg_carbon"] = (sum(eGrid .* f[:carbonIntensityGrid])
            + sum(gGrid * f[:carbonIntensityGas]))
        #+ sum(elecSolar * f[:carbonIntensitySolar])
        bill["CEP_carbon"] = (sum(elecCEP .* f[:carbonIntensityGrid])
        + sum(gGrid * f[:carbonIntensityGas]))
    end

    if p[:carbon]
        bill["objective"] += f[:carbonPrice] * bill["agg_carbon"]
    end

    if p[:cbp]
        cbp_bid = getvalue(sesi[:cbp_bid])
        delivery_ratio = 1 # for now
        bill["cbp"] = - sum(f[:cbp_price][m] * delivery_ratio *
                    cbp_bid[m] for m in 1:M)
        bill["unmet"] = sum(getvalue(sesi[:cbp_unmet]))*f[:cbp_unmet_penalty]
        bill["agg_dollar"] += bill["cbp"]
        bill["objective"] += bill["cbp"]
	    bill["objective"] += bill["unmet"]
    end


    if p[:sw]
        bill["swCost"] = f[:swPenalty] * (swHRC'swHRC + swChiller'swChiller
            + swHeater'swHeater)
        bill["objective"] += bill["swCost"]
    end

    if p[:ev]
        bill["ev"] = sum(evDischarge * p[:usageCostBatteryEV])
        bill["objective"] += bill["ev"]
    end

    elecRateInternal = (sum(f[:elecPrice] .* eGrid)
        + sum(peak .* f[:demandCharge]))/sum(eGrid)
    if p[:cbp]
        elecRateInternal += bill["cbp"]/sum(eGrid)
    end
    bill["elecRateInternal"] = elecRateInternal
    bill["CEP_dollar"] = (elecRateInternal * sum(elecCEP)
        + sum(gGrid .* f[:gasPrice]));

    # unmet loads
    bill["umLoads"] = p[:umHot]*umHot'umHot+p[:umCold]*umCold'umCold
    bill["objective"] += bill["umLoads"]



    # sanity
    if abs(bill["objective"]-getvalue(getobjective(sesi)))>1e-3
        warn("Objective is not properly reconstructed - Debugging this now")
        sw = p[:swPenalty] * (swHRC'swHRC + swChiller'swChiller
            + swHeater'swHeater)
        dc = sum(getvalue(sesi[:peak][m]) * f[:demandCharge][m] for m = 1:M)
        carbon = 0.
        if p[:carbon]
            carbon = f[:carbonPrice] * (
                sum(f[:carbonIntensityGrid][t] * getvalue(sesi[:eGrid][t])
                    for t = 1:T-1)
                + f[:carbonIntensityGas] * sum(getvalue(sesi[:gGrid][t])
                    for t = 1:T-1))
        end
        energy = sum(getvalue(sesi[:eGrid][t]) * f[:elecPrice][t]
            + getvalue(sesi[:gGrid][t]) * f[:gasPrice] for t = 1:T-1)
        cbp = 0.
        cbp_unmet = 0.
        if p[:cbp]
            deliv_ratio = 1.
            cbp = - sum(f[:cbp_price][m] * deliv_ratio
                * getvalue(sesi[:cbp_bid][m]) for m in 1:M)
            cbp_unmet = sum(getvalue(sesi[:cbp_unmet]))*p[:cbp_unmet_penalty]
        end

        umLoads = (p[:umHot]*getvalue(sesi[:umHot])'getvalue(sesi[:umHot])
            +p[:umCold]*getvalue(sesi[:umCold])'getvalue(sesi[:umCold]))
        obj = sw + dc + carbon + energy + cbp + cbp_unmet + umLoads

        println("Switching")
        println(abs(sw - bill["swCost"]))
        println("Demand Charge")
        println(abs(dc - bill["demandCharge"]))
        if p[:carbon]
            println("carbon cost")
            println(abs(carbon - f[:carbonPrice] * bill["agg_carbon"]))
        end
        println("energy bill")
        println(abs(energy - bill["eEnergyCost"] - bill["gEnergyCost"]))
        if haskey(sesi.objDict, :cbp_bid)
            println("cbp")
            println(abs(cbp - bill["cbp"]))
            println("cbp_unmet")
            println(abs(cbp_unmet - bill["unmet"]))
        end
        println("objective")
        println(abs(bill["objective"]-getvalue(getobjective(sesi))))
    end

    # verbose output
    if verb > 0
        @printf("Printing hourly equivalent rates\n")
        @printf("elec demand:\t\t%.4f \$/kWh\n",
            bill["demandCharge"]/sum(eGrid))
        @printf("electricity:\t\t%.4f \$/kWh\n",
            bill["eEnergyCost"]/sum(eGrid))
        if haskey(sesi.objDict, :cbp_bid)
            @printf("cbp:\t\t\t%.4f \$/kWh\n", bill["cbp"]/sum(eGrid))
        end
        @printf("elec internal:\t\t%.6f \$/kWh\n", bill["elecRateInternal"])

        @printf("gas:\t\t\t%.4f\$/mmbtu\n", bill["gEnergyCost"]/sum(gGrid))
    end
    if verb > 1
        @printf("Printing aggregate costs:\n")
        @printf("elec demand:\t\t%.4f \$\n",
            bill["demandCharge"])
        @printf("electricity:\t\t%.4f \$\n",
            bill["eEnergyCost"])
        if haskey(sesi.objDict, :cbp_bid)
            @printf("cbp:\t\t\t%.4f \$\n", bill["cbp"])
        end
        @printf("gas:\t\t\t%.4f\$\n", bill["gEnergyCost"])
        @printf("total:\t\t\t%.4f\$\n", bill["agg_dollar"])
        @printf("obj:\t\t\t%.4f\$\n", bill["objective"])
    end
    if verb > 2
        print("Energy Cost (M\$): ")
        println(bill["agg_dollar"]/1e6)
        print("Energy Cost CEP (M\$): ")
        println(bill["CEP_dollar"]/1e6)
        @printf("elec rate internal: %.2f\n", bill["elecRateInternal"])
        if haskey(bill, "agg_carbon")
            print("Carbon (1,000 tons): ")
            println(bill["agg_carbon"]/1e3)
            print("Carbon for CEP (1,000 tons): ")
            println(bill["CEP_carbon"]/1e3)
        end
        print("Internal rate for electricity(\$): ")
        println(elecRateInternal)
    end

    if verb > 3
        print("Peaks(MW): ")
        println(peak/1e3)
        print("Demand charge (M\$): ")
        println(sum(peak .* f[:demandCharge])/1e6)
        print("Electricity (M\$): ")
        println(sum(f[:elecPrice] .* eGrid)/1e6)
        print("Gas (1,000\$): ")
        println(sum(f[:gasPrice] .* gGrid)/1e3)
    end

    return bill
end

function compare_bills(bbill::Dict, nbill::Dict)
    comp = Dict()
    for it in unique(vcat(collect(keys(bbill)), collect(keys(nbill))))
        bb = 0.
        nb = 0.
        if haskey(bbill, it)
            bb = bbill[it]
        end
        if haskey(nbill, it)
            nb = nbill[it]
        end
        comp[it] = bb - nb
    end
    comp
end
