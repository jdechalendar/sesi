"""
    The model_ functions modify the JuMP model.
    They take in a forecast dictionary called f and a params dictionary called p.
"""

function model_base!(f::Dict, p::Dict)
    """
        Create base model.
        Only variable so far are variables eGrid and gGrid to contain electricity/gas imports.
    """
    T = f[:T]
    sesi = Model(solver = GurobiSolver(OutputFlag = 0))

    @variable(sesi, eGrid[1:T-1] >= 0)
    @variable(sesi, gGrid[1:T-1] >= 0)
    return sesi
end

function model_cap_thstorage!(sesi::JuMP.Model, f::Dict, p::Dict)
    """
        Choose how much thermal storage to build
    """
    p[:cap_thstorage] = true
    @variable(sesi, hotTankMax >= 0)
    @variable(sesi, coldTankMax >= 0)

    @objective(sesi, Min, getobjective(sesi) + hotTankMax*p[:capCostHot]*f[:T]
        + coldTankMax*p[:capCostCold]*f[:T])
    return sesi
end

function model_cap_machines!(sesi::JuMP.Model, f::Dict, p::Dict)
    """
        Choose how many machines to build
    """
    p[:cap_machines] = true
    @variables sesi begin
        nHRC, Int
        nHeater, Int
        nChiller, Int
        HRCCAP >= 0
        chillerCAP >= 0
        heaterCAP >= 0
    end

    @constraints sesi begin
        # TODO: take hard-coded numbers out of here
        HRCCAP == nHRC * p[:HRCCAP]/3
        chillerCAP == nChiller * p[:chillerCAP]/4
        heaterCAP == nHeater * p[:heaterCAP]/3
    end

    @objective(sesi, Min, getobjective(sesi)+ nHRC*p[:capCostHRC] +
        nHeater*p[:capCostHeater] + nChiller*p[:capCostChiller])
    return sesi
end

function model_water!(sesi::JuMP.Model, f::Dict, p::Dict)
    """
        Add water to the model. These are hot and cold water streams.
    """
    T = f[:T];
    @variables sesi begin
        # HRC
        eHRC[1:T-1] >= 0
        hwHRC[1:T-1] >= 0
        cwHRC[1:T-1] >= 0

        # Chiller
        eChiller[1:T-1] >= 0
        cwChiller[1:T-1] >= 0

        # Heater
        eHeater[1:T-1]>=0
        gHeater[1:T-1]>=0
        hwHeater[1:T-1]>=0

        # Storage tanks
        hwTank[1:T]>=0
        cwTank[1:T]>=0

        # unmet loads
        umHot[1:T-1]>=0
        umCold[1:T-1]>=0
    end


    @constraints sesi begin

        # Definition constraints
        [t=1:T-1], eHRC[t] == p[:HRCPE] * cwHRC[t]
        [t=1:T-1], hwHRC[t] == p[:HRCHotToColdRatio] * cwHRC[t]
        [t=1:T-1], eChiller[t] == f[:chillerPE][t] * cwChiller[t]
        [t=1:T-1], eHeater[t] == p[:heaterEPE] * hwHeater[t]
        [t=1:T-1], gHeater[t] == 1/p[:heaterPE] * hwHeater[t]

        # Dynamics
        [t=1:T-1], (hwTank[t+1] == hwTank[t] + hwHRC[t] + hwHeater[t]
            - f[:loadHW][t] + umHot[t])
        [t=1:T-1], (cwTank[t+1] == cwTank[t] + cwHRC[t] + cwChiller[t]
            - f[:loadCW][t] + umCold[t])
        [t=1:T-1], umCold[t] <= f[:loadCW][t]
        [t=1:T-1], umHot[t] <= f[:loadHW][t]
        [t=1:T-1], hwTank[t+1] - hwTank[t] <= p[:S_h_dot_max]
        [t=1:T-1], hwTank[t] - hwTank[t+1] <= p[:S_h_dot_max]
        [t=1:T-1], cwTank[t+1] - cwTank[t] <= p[:S_c_dot_max]
        [t=1:T-1], cwTank[t] - cwTank[t+1] <= p[:S_c_dot_max]
    end

    # Water tank constraints
    if p[:cap_thstorage]
        @constraints sesi begin
            hotTankConstraint[t=1:T-1],( hwTank[t] <=
                sesi[:hotTankMax]*(1-p[:hotTankSafety]))
            coldTankConstraint[t=1:T-1],(cwTank[t] <=
                sesi[:coldTankMax]*(1-p[:coldTankSafety]))
            [t=1:T], hwTank[t] >= sesi[:hotTankMax]*p[:hotTankSafety]
            [t=1:T], cwTank[t] >= sesi[:coldTankMax]*p[:coldTankSafety]
        end
    else
        @constraints sesi begin
            hotTankConstraint[t=1:T],( hwTank[t] <=
                p[:hotTankMax]*(1-p[:hotTankSafety]))
            coldTankConstraint[t=1:T],(cwTank[t] <=
                p[:coldTankMax]*(1-p[:coldTankSafety]))
            [t=1:T], hwTank[t] >= p[:hotTankMax]*p[:hotTankSafety]
            [t=1:T], cwTank[t] >= p[:coldTankMax]*p[:coldTankSafety]
            # Boundary conditions - remove if we are doing capital costs,
            # in that case the horizons are long so it does not matter
            hwTank[1] == f[:hwTankInit]
            cwTank[1] == f[:cwTankInit]
            hwTank[T] >= f[:hwTankEnd]
            cwTank[T] >= f[:cwTankEnd]
        end
    end


    # Capacity constraints
    if p[:cap_machines]
        @constraints sesi begin
            [t=1:T-1], cwHRC[t] <= HRCCAP
            [t=1:T-1], cwChiller[t] <= chillerCAP
            [t=1:T-1], hwHeater[t] <= heaterCAP
        end
    else
        @constraints sesi begin
            [t=1:T-1], cwHRC[t] <= p[:HRCCAP]
            [t=1:T-1], cwChiller[t] <= p[:chillerCAP]
            [t=1:T-1], hwHeater[t] <= p[:heaterCAP]
        end
    end

    if p[:umLoadsL2]  # use L2 penalty
        @objective(sesi, Min, getobjective(sesi) + p[:umHot] * umHot'umHot
            + p[:umCold] * umCold'umCold)
    else  # use L1 penalty
        @objective(sesi, Min, getobjective(sesi) + p[:umHot] * sum(umHot)
            + p[:umCold] * sum(umCold))
    end

    return sesi
end

function model_water_switching!(sesi::JuMP.Model, f::Dict, p::Dict)
    """ Model switching constraints for heating/cooling machines.
    """
    T = f[:T]
    p[:sw] = true
    @variables sesi begin
        swHRC[1:T-2] >= 0
        swHeater[1:T-2] >= 0
        swChiller[1:T-2] >= 0
    end

     for t=1:T-2
         @constraints sesi begin
             swHRC[t] >= sesi[:eHRC][t] - sesi[:eHRC][t+1]
             swHRC[t] >= sesi[:eHRC][t+1] - sesi[:eHRC][t]
             swHeater[t] >= sesi[:eHeater][t] - sesi[:eHeater][t+1]
             swHeater[t] >= sesi[:eHeater][t+1] - sesi[:eHeater][t]
             swChiller[t] >= sesi[:eChiller][t] - sesi[:eChiller][t+1]
             swChiller[t] >= sesi[:eChiller][t+1] - sesi[:eChiller][t]
         end
     end

    # norm 2 penalty makes more sense
    @objective(sesi, Min, getobjective(sesi) + p[:swPenalty] * (swHRC'swHRC +
        swChiller'swChiller + swHeater'swHeater))

    f[:swPenalty] = p[:swPenalty]

    return sesi
end

function model_storage!(sesi::JuMP.Model, f::Dict, p::Dict)
    """
        Add electrical storage to the model.
    """
    T = f[:T]

    # Electrical storage
    @variable(sesi, elecTransfer_in[1:T-1]>=0)
    @variable(sesi, elecTransfer_out[1:T-1]>=0)

    # Amount in electrical storage
    @variable(sesi, elecStored[1:T] >= 0)

    # Boundary conditions
    @constraint(sesi,elecStored[1] == f[:elecStorageInit])
    @constraint(sesi, elecStored[T] == p[:elecStorageInit])

    for t = 1:T-1
        # Operating constraints
        @constraint(sesi, elecTransfer_in[t] <= p[:elecTransferMax])
        @constraint(sesi, elecTransfer_out[t] <= p[:elecTransferMax])

        # Max storage constraint
        @constraint(sesi, elecStored[t] <= p[:elecStorageMax])

        # Dynamics
        @constraint(sesi, elecStored[t+1] == elecStored[t]
            + p[:elecTransferEta] * elecTransfer_in[t]
            - elecTransfer_out[t] / p[:elecTransferEta])
    end

    @objective(sesi, Min, getobjective(sesi) + p[:usageCostBattery]
        * sum(elecTransfer_out[t] for t=1:T-1))
    return sesi
end

function model_demand!(sesi::JuMP.Model, f::Dict, p::Dict)
    """
        Add demand-related variables to the model.
        Create a monthly indexed variable to contain peak demand.
        Add constraint that peak is greater then eGrid at all hours of the month.
        Add cost of demand charge in objective function
    """
    T, M = f[:T], f[:M]
    p[:peak] = true
    @variable(sesi, peak[1:M] >= 0)
    for t = 1:T-1
        # m = getMonth(t - 1 + f["startInd"]) - getMonth(f["startInd"]) + 1
        @constraint(sesi, peak[getMonthNum(t, f)] >= sesi[:eGrid][t])
    end
    @objective(sesi, Min, getobjective(sesi)
               + sum(peak[m] * f[:demandCharge][m] for m = 1:M))

    return sesi
end

function model_carbon!(sesi::JuMP.Model, f::Dict, p::Dict)

    T = f[:T]
    p[:carbon]=true
    @objective(sesi, Min, getobjective(sesi)
        + f[:carbonPrice] * (sum(f[:carbonIntensityGrid][t]
            * sesi[:eGrid][t] for t = 1:T-1) + f[:carbonIntensityGas]
            * sum(sesi[:gGrid][t] for t = 1:T-1)))

    return sesi
end

function model_energy_price!(sesi::JuMP.Model, f::Dict, p::Dict)
    """
        Add variable energy price to the model.
    """
    T = f[:T]
    @objective(sesi, Min, getobjective(sesi) + sum(sesi[:eGrid][t] * f[:elecPrice][t]
        + sesi[:gGrid][t] * f[:gasPrice] for t = 1:T-1))
    return sesi
end

function model_finalize!(sesi::JuMP.Model, f::Dict, p::Dict)
    """
        Add aggregate constraints to the model.
    """
    T = f[:T]
    for t = 1:T-1
        @expression(sesi, eGridExpr, f[:loadKWH][t])
        for var in [:eChiller, :eHeater, :eHRC, :elecTransfer_in, :elecEV_in]
            if haskey(sesi.objDict, var)
                @expression(sesi, eGridExpr, eGridExpr + sesi[var][t])
            end
        end
        if haskey(sesi.objDict, :elecTransfer_out)
            @expression(sesi, eGridExpr, eGridExpr -
			sesi[:elecTransfer_out][t])
        end
        @constraint(sesi, sesi[:eGrid][t] == eGridExpr)
    end
    for t = 1:T-1
        @expression(sesi, gGridExpr, 0)
        for var in [:gHeater]
            if haskey(sesi.objDict, var)
                @expression(sesi, gGridExpr, gGridExpr + sesi[var][t])
            end
        end
        @constraint(sesi, sesi[:gGrid][t] == gGridExpr)
    end
    return sesi
end
