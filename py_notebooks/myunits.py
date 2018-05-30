def units():
	u = {
	    "GJ_per_mmbtu": 1.055, # src: Google
	    "kwh_per_mmbtu": 293.07,
	    "kWh_per_tonhr": 3.5, # src: Google
	    "GJ_per_kwh": 0.0036
	}
	u["GJ_per_ton"] = u["kWh_per_tonhr"] * u["GJ_per_kwh"]
	return u