# Note: in the future, these functions will check that the appropriate fields
# are defined in the parameter dictionary, but there will no longer be default
# values, to make sure the user is supplying them.

# At present, all numerical values should be here. No hard-coded values
# elsewhere in the Sesi module

# The design_ functions create the parameter dictionary. This contains
# design parameters that do not change in time.

function design_base!()
    p = Dict()
    p[:utc_offset] = -7
    # These will be toggled on as they are added to the model
    p[:cbp] = false
    p[:carbon] = false
    p[:peak] = false
    p[:sw] = false
    p[:cap_thstorage] = false
    p[:cap_machines] = false
    p[:ev] = false

    return p
end

function design_water!(p::Dict)
    # chilled water storage capacity
    p[:coldTankMax] = 90.e3 # ton-hr # 90
    p[:coldTankSafety] = 0.05 # safety zone (%)
    p[:cwTankInit] = 0.1*p[:coldTankMax] # ton-hr
    p[:S_c_dot_max] = 18.e3 # ton

    # hot water storage capacity
    p[:hotTankMax] = 600. # mmbtu
    p[:hotTankSafety] = 0.05 # safety zone (%)
    p[:hwTankInit] = 0.1*p[:hotTankMax] # mmbtu
    p[:S_h_dot_max] = 120. # mmbtu/hr

    # machines
    # there are 3 HRCs, 4 chillers and 3 heaters. For now we assume one of each and scale accordingly
    # When data does not vary, we use a scalar instead of a vector
    p[:HRCCAP] = 2500.*3# data[:HRC1CAP]*3 # tons
    p[:chillerCAP] = 3000.*4 # data[:C6CAP]*4 # tons
    p[:heaterCAP] = 60.55*3 # data[:H1CAP]*3 # mmbtu
    p[:HRCPE] = 1.32703695050335 #data[:HRC1PE] # kWh/ton-hr
    p[:heaterPE] = 0.85 # data[:H1PE] # %HHV
    p[:heaterEPE] = 2.0 # data[:H1ePE] # kWh/mmbtu
    p[:chillerPE] = 0.45566 # kW/ton - mean value in 2016 - will be used if efficiency is not supplied in the timeseries data
    p[:HRCHotToColdRatio] = 41. / 2500. # mmbtu/ton-hr - my assumption based on CEPOM

    p[:swPenalty] = 1e-8 # $/kW

    # capital costs
    # 7.4e6 for the three tanks - assume equal split -> 2.46e6 per tank
    # Assume a lifetime of 20 years
    p[:capCostCold] = 2.46666666e6 / p[:coldTankMax] / (20*365*24) # $/ton/hr
    p[:capCostHot] = 2 * 2.46666666e6 / p[:hotTankMax] / (20*365*24) # $/mmbtu/hr

    # unmet load cost
    p[:umCold] = 1.32 * 10 # kWh/ton-hr * $/kWh
    p[:umHot] = 1.32 * 10 * 2500. / 41. # kWh/ton-hr * $/kWh * ton-hr/mmbtu

    return p
end

function design_storage!(p::Dict)
    # battery
    p[:capitalCostBattery] = 400 # $/kWh # 400
    p[:elecStorageMax] = 10.e3 # kWh
    p[:elecTransferMax] = p[:elecStorageMax]/2
    p[:elecTransferEta] = 1-0.064500
    p[:elecStorageInit] = p[:elecStorageMax] # kWh
    p[:lifetimeBattery] = 3000 #[number of cycles]
    # this is intentionnally left very small and is needed numerically to avoid overusing the battery
    p[:usageCostBattery] = p[:capitalCostBattery] / p[:lifetimeBattery] # $/kWh
    return p
end

function design_prices!(p::Dict)
    p[:gasPrice] = 5.40 # $/mmbtu
    #p[:demandCharge] = 4.56# $/kW

    # data from SESI Performance Review (recieved 2017-09-15)
    prices = [3.38,3.38,3.76,3.76,3.76,3.76,3.76,3.76,3.55,3.55,3.55,3.55,2.63,
	      2.63,3.18,3.18,3.18,3.18,3.18,3.18,3.18,3.18,2.98,2.98,2.71,2.71,
	      3.03,3.03,3.03,3.03,3.03,3.03,3.03,3.03,3.03,3.03,3.25,3.25,3.67,
	      3.67,3.67,3.67,3.67,3.67,3.67,3.67,3.67,3.67,3.44,3.44,4.28,4.28,
	      4.28,3.97,3.97,3.97,3.97,3.97,3.97,3.97,4.22,4.22,4.79,4.79,4.79,
	      4.79,4.79,4.79,4.79,4.79,4.79,4.79,4.06,4.06,4.06,4.06,4.06,4.06,
	      4.06,4.06,4.06,4.06,4.06,4.06,4.05,4.05,4.05,4.05,4.75,4.75,4.75,
	      4.75,4.75,4.64,4.64,4.64,4.61,4.61,4.61,4.61,4.77,4.77,4.77,4.77,
	      4.77,4.66,4.66,4.66,4.64,4.64,6.08,6.08,6.08,6.08,6.08,6.08,5.37,
	      5.37,5.37,5.37,5.95,5.95,7.4,7.4,7.4,7.4,7.4,7.39,7.39,6.59,6.59,
	      6.59,6.54,6.54,8.31,8.31,8.31,8.31,8.31,8.31,8.31, 8.31, 8.31, 8.31,
          8.32, 8.32, 8.79, 8.79, 8.79, 8.79, 8.79, 8.79, 8.79, 8.31, 8.31, 8.31,
          8.31]
    dates = [Dates.DateTime("2006-01-01") + Dates.Month(ii) for ii in 0:157]
    p[:demandCharge] = Dict(zip(dates, prices))
    return p
end

function design_carbon!(p::Dict)
    # kg/MW -> ton/kW
    p[:carbon_units] = 1e-6
    # ton/mmbtu
    p[:carbonIntensityGas] = 14.46*44/12*1e-3;
    # carbon intenstiy gas - according to this
    # https://www.epa.gov/energy/greenhouse-gases-equivalencies-calculator-calculations-and-references

     # $/ton
    p[:carbonPrice] = 100;
end
