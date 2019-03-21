"""
    Convenience function to build JuMP model.
"""
function build_model(fileNm::String; startT::Int=1, T::Int=-1, verb::Bool=true,
    cold_storage::Float64=90.e3, hot_storage::Float64=600.,
    carbonPrice::Float64=100., capCostTh::Bool=false, capCostMa::Bool=false,
    elecStorage::Bool=false, elec_storage::Float64=0.,nHRC::Float64=3.,
    nChiller::Float64=4., nHeater::Float64=3., dc_ratio::Float64=1.,
    startDate::Date=Date(), endDate::Date=Date(),
    umLoadsL2::Bool=true)

    if T != -1
        data = CSV.read(fileNm, datarow=1+startT, rows=T, allowmissing=:none)
    else
        data = CSV.read(fileNm, datarow=1+startT, allowmissing=:none)
    end

    data[:Date] = DateTime.(data[:Date])

    p = Sesi.design_base!()
    Sesi.design_water!(p)
    p[:coldTankMax] = cold_storage
    p[:cwTankInit] = 0.1 * cold_storage
    p[:hotTankMax] = hot_storage
    p[:hwTankInit] = 0.1 * hot_storage
    p[:HRCCAP] *= nHRC / 3.
    p[:chillerCAP] *= nChiller / 4.
    p[:heaterCAP] *= nHeater / 3.
    p[:umLoadsL2] = umLoadsL2

    Sesi.design_prices!(p)
    p[:demandCharge] = Dict(k => v*dc_ratio for (k,v) in p[:demandCharge])
    Sesi.design_carbon!(p)
    if elecStorage
        Sesi.design_storage!(p)
        p[:elecStorageMax] = elec_storage
        p[:elecStorageInit] = elec_storage
    end

    f = Sesi.forecast_base!(data, p; startT=startT, T=T, startDate=startDate,
        endDate=endDate)
    Sesi.forecast_water!(f, data, p)
    Sesi.forecast_prices!(f, data, p)
    Sesi.forecast_carbon!(f, data, p)
    f[:carbonPrice] = carbonPrice
    if elecStorage
        Sesi.forecast_storage!(f, data, p)
    end

    sesi = Sesi.model_base!(f, p)
    if capCostTh
        Sesi.model_cap_thstorage!(sesi, f, p)
    end
    if capCostMa
        Sesi.model_cap_machines!(sesi, f, p)
    end
    Sesi.model_water!(sesi, f, p)
    Sesi.model_water_switching!(sesi, f, p)
    if elecStorage
        Sesi.model_storage!(sesi, f, p)
    end
    Sesi.model_demand!(sesi, f, p)
    Sesi.model_energy_price!(sesi, f, p)
    Sesi.model_carbon!(sesi, f, p)
    Sesi.model_finalize!(sesi, f, p)

    return sesi, p, f
end

function carbon_cost(res, sc, base, curr)
    ((res[sc][curr]["agg_dollar"]-res[sc][base]["agg_dollar"])
        /(res[sc][base]["agg_carbon"]-res[sc][curr]["agg_carbon"]))
end

function carbon_reduction(res, sc, base, curr)
    100*(1-res[sc][curr]["CEP_carbon"]/res[sc][base]["CEP_carbon"])
end

function sanity(res, sc, base, curr)
    ((res[sc][curr]["CEP_carbon"]-res[sc][base]["CEP_carbon"])/
    (res[sc][curr]["agg_carbon"]-res[sc][base]["agg_carbon"]))
end
