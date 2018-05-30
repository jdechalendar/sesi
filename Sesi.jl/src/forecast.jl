#     The forecast_ functions create the forecast dictionary, which contains time-
#     varying parameters.

"""
    forecast_base!(fileNm, p; f, startDate=startDate, endDate=endDate,
        startT=startT, T=T, history=history)

    forecast_base!(data, p; f=f, startDate=startDate, endDate=endDate,
        startT=startT, T=T, history=history)

All keyword arguments are optional. If startDate or endDate are specified, they
will have precedence over startT and T.

# Required arguments
fileNm::String      file name from which to read the data
OR data::Dataframe  data that was pre-read
p::Dict parameter   dictionary

# Optional keyword arguments
f::Dict             forecast dictionary
startDate::Date     start date for reading data
endDate::Date       end date for reading data
startT::Int         start index for reading data
T::Int              number of timesteps for reading data
history::Dict       history dictionary

# Examples
Todo
"""
function forecast_base! end

"""
    forecast_water!(f, fileNm, p; history=history)

    forecast_water!(f, data, p; history=history)

Doc: todo

# Required arguments
f::Dict             forecast dictionary
fileNm::String      file name from which to read the data
OR data::Dataframe  data that was pre-read
p::Dict parameter   dictionary

# Optional keyword arguments
history::Dict       history dictionary

# Examples

"""
function forecast_water! end

"""
    forecast_storage!(f, fileNm, p; history=history)

    forecast_storage!(f, data, p; history=history)

Doc: todo

# Required arguments
f::Dict             forecast dictionary
fileNm::String      file name from which to read the data
OR data::Dataframe  data that was pre-read
p::Dict parameter   dictionary

# Optional keyword arguments
history::Dict       history dictionary

# Examples

"""
function forecast_storage! end

"""
    forecast_prices!(f, fileNm, p; history=history)

    forecast_prices!(f, data, p; history=history)

Doc: todo

# Required arguments
f::Dict             forecast dictionary
fileNm::String      file name from which to read the data
OR data::Dataframe  data that was pre-read
p::Dict parameter   dictionary

# Optional keyword arguments
history::Dict       history dictionary

# Examples

"""
function forecast_prices! end

"""
    forecast_carbon!(f, fileNm, p; history=history)

    forecast_carbon!(f, data, p; history=history)

Doc: todo

# Required arguments
f::Dict             forecast dictionary
fileNm::String      file name from which to read the data
OR data::Dataframe  data that was pre-read
p::Dict parameter   dictionary

# Optional keyword arguments
history::Dict       history dictionary

# Examples

"""
function forecast_carbon! end

function forecast_base!(fileNm::String, p::Dict; f::Dict=Dict(),
    startDate::Date=Date(), endDate::Date=Date(), startT::Int=1,
    T::Int=-1, history::Dict=Dict())
    return forecast_base!(CSV.read(fileNm), p; f=f, startDate=startDate,
        endDate=endDate, startT=startT, T=T, history=history)
end

function forecast_base!(data::DataFrame, p::Dict; f::Dict=Dict(),
    startDate::Date=Date(), endDate::Date=Date(), startT::Int=1,
    T::Int=-1, history::Dict=Dict())
    # in the optimization, we are in local time
    data[:Date] += Dates.Hour(p[:utc_offset])

    if startDate != Date()
        startT = findDate(startDate, Date.(data[:Date]))
    end

    if endDate != Date()
        endT = findDate(endDate, Date.(data[:Date]))
        T = endT - startT + 2;
    end

    # Time
    if T == -1
        T = 1 + size(data)[1] - startT+1;
    end
    endT = startT + T - 2;
    f[:startT] = startT; # remember where I started reading from.
    f[:endT] = endT; # remember where I stopped reading from.
    f[:T] = T;
    f[:timestamp] = data[:Date][startT:endT]

    # number of months
    f[:M] = getMonthNum(T-1, f);
    f[:loadKWH] = data[:Campus_KWH][startT:endT]; # kWh

    f[:hourCA] = mod.(Dates.hour.(f[:timestamp])-7, 24)
    return f;
end

function forecast_water!(f::Dict, fileNm::String, p::Dict; history::Dict=Dict())
    return forecast_water!(f, readtable(fileNm), p; history)
end

function forecast_water!(f::Dict, data::DataFrame, p::Dict;
    history::Dict=Dict())

    startT = f[:startT]
    endT = f[:endT]

    if haskey(data, :chillerPE)
        f[:chillerPE] = data[:chillerPE][startT:endT] # kW/ton
    else
        f[:chillerPE] = ones(endT-startT+1) * p[:chillerPE]
    end
    f[:loadHW] = data[:HW_loads][startT:endT] # tons
    f[:loadCW] = data[:CW_loads][startT:endT] # mmbtu
    if haskey(history, :hwTank)
        f[:hwTankInit] = history[:hwTank][end]
    else
        f[:hwTankInit] = p[:hwTankInit]
    end
    if haskey(history, :cwTank)
        f[:cwTankInit] = history[:cwTank][end]
    else
        f[:cwTankInit] = p[:cwTankInit]
    end
    f[:cwTankEnd] = f[:cwTankInit]/2
    f[:hwTankEnd] = f[:hwTankInit]/2
    return f;
end

function forecast_storage!(f::Dict, fileNm::String, p::Dict;
    history::Dict=Dict())
    return forecast_storage!(f, readtable(fileNm), p; history=history)
end

function forecast_storage!(f::Dict, data::DataFrame, p::Dict;
    history::Dict=Dict())

    startT = f[:startT]
    endT = f[:endT]

    if haskey(history, :elecStorageInit)
        f[:elecStorageInit] = history[:elecStorageInit][end]
    else
        f[:elecStorageInit] = p[:elecStorageInit]
    end
    return f;
end

function forecast_prices!(f::Dict, fileNm::String, p::Dict;
    history::Dict=Dict())
    return forecast_prices!(f, readtable(fileNm), p; history=history)
end

function forecast_prices!(f::Dict, data::DataFrame, p::Dict;
    history::Dict=Dict())

    startT = f[:startT]
    endT = f[:endT]
    # add a fixed cost here?
    f[:elecPrice] = data[:Electricity_prices][startT:endT] # $/kW
    f[:gasPrice] = p[:gasPrice]
    #f[:demandCharge] = p[:demandCharge] * ones(f[:M])
    # use demandCharge data to populate f[:demandCharge]
    simMonths = unique(DateTime.(Dates.Year.(f[:timestamp]),
                                 Dates.Month.(f[:timestamp])))
    f[:demandCharge] = [p[:demandCharge][m] for m in simMonths]
    return f
end

function forecast_carbon!(f::Dict, fileNm::String, p::Dict;
    history::Dict=Dict())
    return forecast_carbon!(f, readtable(fileNm), p, history)
end

function forecast_carbon!(f::Dict, data::DataFrame, p::Dict;
    history::Dict=Dict())

    startT = f[:startT]
    endT = f[:endT]

    f[:carbonIntensityGrid] = data[:carbon][startT:endT]*p[:carbon_units]
    f[:carbonIntensityGas] = p[:carbonIntensityGas]
    f[:carbonPrice] = p[:carbonPrice]
    return f
end

function forecast_CBP!(f::Dict, fileNm::String, p::Dict; history::Dict=Dict())
    if !haskey(f, :eGrid)
        error("There should be :eGrid in f")
    end
    f[:event_ts] # contains a list of timestamps at which we are doing demand response

    f[:ts_to_index] #maps ts->integer index
    return f;
end
