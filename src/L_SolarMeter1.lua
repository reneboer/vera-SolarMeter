--[==[
  Module L_SolarMeter1.lua
  Written by R.Boer. 

  V1.12 17 December 2019

  V1.12 Changes:
	- Icon file removed as that comes from github repository
	- Fix for all converters retuning zero values
  V1.11 Changes:
    - Fixes for Solarman monitoring 
	- Overall fixes.
	- Child device support for fronius
  V1.10 Changes:
    - Fixes for Solarman monitoring - Octoplayer & somersetdude
  V1.9 Changes:
    - Addition of Solarman monitoring - Octoplayer
  V1.8 Changes:
    - Fix for yearly calculations.
  V1.7 Changes:
	- Corrected logic for calculated weekly and monthly totals.
	- Polling for the day only stopping once current watts are zero, not right after sunset. Some systems are slow to report and where missing last values.
	- Added Yearly total.
  V1.6 Changes:
    - call_timer to type 2 (daily) needs to be rescheduled. It does not repeat when calling just once.
  V1.5.2 Changes:
    - Calculate running sums for weekly and monthy if not provided by converter.
  V1.5.1 Changes:
    - Better pcall return error handling.
    - Bug fixes
  V1.5 Changes:
    - Optimized polling to only poll during day time.
    - Handling of non-numerical return values when numbers are expected.
  V1.4.3 Changes:
    - Added fields for PV output.
  V1.4.2 Changes:
    - Changed PV output to be able to use http instead of https.
  V1.4.1 Changes:
    - Added some fields for Fronius on request.
  V1.4 Changes:
    - Better error handling
  V1.3 Changes:
    - Fix for Fronius support
  V1.2 Changes:
    - Corrected Dispay on latest version of ALTUI
  V1.1 Changes:
    - Fronius JSON API V1 support
    - Some big fixes
  
   V1.0 First release

  Get data from several Solar systems
--]==]

local socketLib = require("socket")  -- Required for logAPI module.
local json = require("dkjson")
local http = require("socket.http")
local ltn12 = require("ltn12")

local PlugIn = {
  Version = "1.12",
  DESCRIPTION = "Solar Meter", 
  SM_SID = "urn:rboer-com:serviceId:SolarMeter1", 
  EM_SID = "urn:micasaverde-com:serviceId:EnergyMetering1", 
  ALTUI_SID = "urn:upnp-org:serviceId:altui1",
  THIS_DEVICE = 0,
  HouseDevice = nil,
  GridInDevice = nil,
  GridOutDevice = nil,
  BatteryInDevice = nil,
  BatteryOutDevice = nil,
  Disabled = false,
  StartingUp = true,
  System = 0,
  DInterval = 30,
  NInterval = 1800,
  lastWeekDaily = nil,
  thisMonthDaily = nil,
  thisYearMonthy = nil
}

-- To map solar systems. Must be in sync with var solarSystem in J_SolarMeter1.js
local SolarSystems = {}
local function addSolarSystem(k, i, r)
  SolarSystems[k] = {init = i, refresh = r}
end  

---------------------------------------------------------------------------------------------
-- Utility functions
---------------------------------------------------------------------------------------------
local log
local var
local utils


-- API getting and setting variables and attributes from Vera more efficient.
local function varAPI()
  local def_sid, def_dev = '', 0
  
  local function _init(sid,dev)
    def_sid = sid
    def_dev = dev
  end
  
  -- Get variable value
  local function _get(name, sid, device)
    local value = luup.variable_get(sid or def_sid, name, tonumber(device or def_dev))
    return (value or '')
  end

  -- Get variable value as number type
  local function _getnum(name, sid, device)
    local value = luup.variable_get(sid or def_sid, name, tonumber(device or def_dev))
    local num = tonumber(value,10)
    return (num or 0)
  end
  
  -- Set variable value
  local function _set(name, value, sid, device)
    local sid = sid or def_sid
    local device = tonumber(device or def_dev)
    local old = luup.variable_get(sid, name, device)
    if (tostring(value) ~= tostring(old or '')) then 
      luup.variable_set(sid, name, value, device)
    end
  end

  -- create missing variable with default value or return existing
  local function _default(name, default, sid, device)
    local sid = sid or def_sid
    local device = tonumber(device or def_dev)
    local value = luup.variable_get(sid, name, device) 
    if (not value) then
      value = default  or ''
      luup.variable_set(sid, name, value, device)  
    end
    return value
  end
  
  -- Get an attribute value, try to return as number value if applicable
  local function _getattr(name, device)
    local value = luup.attr_get(name, tonumber(device or def_dev))
    local nv = tonumber(value,10)
    return (nv or value)
  end

  -- Set an attribute
  local function _setattr(name, value, device)
    luup.attr_set(name, value, tonumber(device or def_dev))
  end
  
  return {
    Get = _get,
    Set = _set,
    GetNumber = _getnum,
    Default = _default,
    GetAttribute = _getattr,
    SetAttribute = _setattr,
    Initialize = _init
  }
end

-- API to handle basic logging and debug messaging
local function logAPI()
local def_level = 1
local def_prefix = ''
local def_debug = false
local def_file = false
local max_length = 100
local onOpenLuup = false
local taskHandle = -1

	local function _update(level)
		if level > 100 then
			def_file = true
			def_debug = true
			def_level = 10
		elseif level > 10 then
			def_debug = true
			def_file = false
			def_level = 10
		else
			def_file = false
			def_debug = false
			def_level = level
		end
	end	

	local function _init(prefix, level,onol)
		_update(level)
		def_prefix = prefix
		onOpenLuup = onol
	end	
	
	-- Build loggin string safely up to given lenght. If only one string given, then do not format because of length limitations.
	local function prot_format(ln,str,...)
		local msg = ""
		if arg[1] then 
			_, msg = pcall(string.format, str, unpack(arg))
		else 
			msg = str or "no text"
		end 
		if ln > 0 then
			return msg:sub(1,ln)
		else
			return msg
		end	
	end	
	local function _log(...) 
		if (def_level >= 10) then
			luup.log(def_prefix .. ": " .. prot_format(max_length,...), 50) 
		end	
	end	
	
	local function _info(...) 
		if (def_level >= 8) then
			luup.log(def_prefix .. "_info: " .. prot_format(max_length,...), 8) 
		end	
	end	

	local function _warning(...) 
		if (def_level >= 2) then
			luup.log(def_prefix .. "_warning: " .. prot_format(max_length,...), 2) 
		end	
	end	

	local function _error(...) 
		if (def_level >= 1) then
			luup.log(def_prefix .. "_error: " .. prot_format(max_length,...), 1) 
		end	
	end	

	local function _debug(...)
		if def_debug then
			luup.log(def_prefix .. "_debug: " .. prot_format(-1,...), 50) 
		end	
	end
	
	-- Write to file for detailed analisys
	local function _logfile(...)
		if def_file then
			local fh = io.open("/tmp/harmony.log","a")
			local msg = os.date("%d/%m/%Y %X") .. ": " .. prot_format(-1,...)
			fh:write(msg)
			fh:write("\n")
			fh:close()
		end	
	end
	
	local function _devmessage(devID, isError, timeout, ...)
		local message =  prot_format(60,...)
		local status = isError and 2 or 4
		-- Standard device message cannot be erased. Need to do a reload if message w/o timeout need to be removed. Rely on caller to trigger that.
		if onOpenLuup then
			taskHandle = luup.task(message, status, def_prefix, taskHandle)
			if timeout ~= 0 then
				luup.call_delay("logAPI_clearTask", timeout, "", false)
			else
				taskHandle = -1
			end
		else
			luup.device_message(devID, status, message, timeout, def_prefix)
		end	
	end
	
	local function logAPI_clearTask()
		luup.task("", 4, def_prefix, taskHandle)
		taskHandle = -1
	end
	_G.logAPI_clearTask = logAPI_clearTask
	
	
	return {
		Initialize = _init,
		Error = _error,
		Warning = _warning,
		Info = _info,
		Log = _log,
		Debug = _debug,
		Update = _update,
		LogFile = _logfile,
		DeviceMessage = _devmessage
	}
end 

-- API to handle some Util functions
local function utilsAPI()
local _UI5 = 5
local _UI6 = 6
local _UI7 = 7
local _UI8 = 8
local _OpenLuup = 99

  local function _init()
  end  

  -- See what system we are running on, some Vera or OpenLuup
  local function _getui()
    if (luup.attr_get("openLuup",0) ~= nil) then
      return _OpenLuup
    else
      return luup.version_major
    end
    return _UI7
  end
  
  local function _getmemoryused()
    return math.floor(collectgarbage "count")         -- app's own memory usage in kB
  end
  
  local function _setluupfailure(status,devID)
    if (luup.version_major < 7) then status = status ~= 0 end        -- fix UI5 status type
    luup.set_failure(status,devID)
  end

  -- Luup Reload function for UI5,6 and 7
  local function _luup_reload()
    if (luup.version_major < 6) then 
      luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", {}, 0)
    else
      luup.reload()
    end
  end
  
  function _split(source, delimiters)
    local del = delimiters or ","
    local elements = {}
    local pattern = '([^'..del..']+)'
    string.gsub(source, pattern, function(value) elements[#elements + 1] = value end)
    return elements
  end
  
  function _join(tab, delimeters)
    local del = delimiters or ","
    return table.concat(tab, del)
  end
  
  return {
    Initialize = _init,
    ReloadLuup = _luup_reload,
    GetMemoryUsed = _getmemoryused,
    SetLuupFailure = _setluupfailure,
    Split = _split,
    Join = _join,
    GetUI = _getui,
    IsUI5 = _UI5,
    IsUI6 = _UI6,
    IsUI7 = _UI7,
    IsUI8 = _UI8,
    IsOpenLuup = _OpenLuup
  }
end 

-- Get an attribute value, try to return as number value if applicable
local function GetAsNumber(value)
	local nv = tonumber(value,10)
	return (nv or 0)
end

-- Initialize calculation array
local function InitWeekTotal()
	local arrV = var.Default("WeeklyDaily", "0,0,0,0,0,0,0")
	lastWeekDaily = utils.Split(arrV)
	-- See if we have too many entries due to errors in version 1.6
	if #lastWeekDaily > 7 then
		-- Drop what we have too many
        while #lastWeekDaily > 7 do 
            table.remove(lastWeekDaily,1)
        end    
	end
end
local function InitMonthTotal()
	local arrV = var.Default("MonthlyDaily", "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0")
	thisMonthDaily = utils.Split(arrV)
	-- See if we have too many entries due to errors in version 1.6
	if #thisMonthDaily > 31 then
		-- Drop what we have too many
		local numDays = tonumber(os.date("%d"))
        while #thisMonthDaily > numDays do 
            table.remove(thisMonthDaily,1)
        end    
	end
end
local function InitYearTotal()
	local arrV = var.Default("YearlyMonthly", "0,0,0,0,0,0,0,0,0,0,0,0")
	thisYearMonthly = utils.Split(arrV)
end

-- Calculate new weekly value, needs todays daily as input.
local function GetWeekTotal(daily)
	if daily == -1 then return -1 end
	-- See if we have a new daily value, if so recalculate
	local numDays = tonumber(os.date("%w")) + 1
	if daily ~= tonumber(lastWeekDaily[numDays]) then
		local total = 0
		lastWeekDaily[numDays] = daily
		-- Add up seven days total
		for i = 1, 7 do
			total = total + lastWeekDaily[i]
		end
		var.Set("WeeklyDaily", utils.Join(lastWeekDaily))
		return total
    else
		-- No change
		return -1
    end
end

-- Calculate new current month value, needs todays daily as input.
local function GetMonthTotal(daily)
	if daily == -1 then return -1 end
	-- See if we have a new daily value, if so recalculate
	local numDays = tonumber(os.date("%d"))
	if numDays ~= 1 then
		if daily ~= tonumber(thisMonthDaily[numDays]) then
			local total = 0
			thisMonthDaily[numDays] = daily
			for i = 1, numDays do
				total = total + thisMonthDaily[i]
			end
			var.Set("MonthlyDaily", utils.Join(thisMonthDaily))
			return total
		else
			-- No change
			return -1
		end
	else
		-- Set first value in array
		if daily ~= tonumber(thisMonthDaily[1]) then
			thisMonthDaily[1] = daily
			var.Set("MonthlyDaily", utils.Join(thisMonthDaily))
			return daily
		else
			-- No change
			return -1
		end
	end  
end

-- Calculate new current month value, needs current monthly as input.
local function GetYearTotal(monthly)
	if monthly == -1 then return -1 end
	-- See if we have a new daily value, if so recalculate
	local month = tonumber(os.date("%m"))
	if month ~= 1 then
		if monthly ~= tonumber(thisYearMonthly[month]) then
			local total = 0
			thisYearMonthly[month] = monthly
			for i = 1, month do
				total = total + thisYearMonthly[i]
			end
			var.Set("YearlyMonthly", utils.Join(thisYearMonthly))
			return total
		else
			-- No change
			return -1
		end
	else
		-- Set first value in array
		if monthly ~= tonumber(thisYearMonthly[1]) then
			thisYearMonthly[1] = monthly
			var.Set("YearlyMonthly", utils.Join(thisYearMonthly))
			return monthly
		else
			-- No change
			return -1
		end
	end  
end

-- Find child based on having THIS_DEVICE as parent and the expected altID
local function addMeterDevice(childDevices, meterType)
	local meterName = "SMTR_"..meterType
	local childName = "Solar Meter "..meterType
	local init = ""
	local sid = PlugIn.EM_SID

	-- For Power meters, set initial values
	init=sid .. ",ActualUsage=1\n" .. 
		 sid .. ",Watts=0\n" .. 
		 sid .. ",KWH=0\n" ..
		 sid .. ",DayKWH=0\n" ..
		 sid .. ",WeekKWH=0\n" ..
		 sid .. ",MonthKWH=0\n" ..
		 sid .. ",LifeKWH=0\n"
	-- For whole house set WholeHouse flag
	if (meterType == "House") then
		init=init .. sid ..",WholeHouse=1\n"
	end	
	init=init .. "urn:micasaverde-com:serviceId:HaDevice1,HideDeleteButton=1"

	-- Now add the new device to the tree
	log.Log("Creating child device id %s (%s)", meterName, childName)
	luup.chdev.append(
		    	PlugIn.THIS_DEVICE, -- parent (this device)
		    	childDevices, 		-- pointer from above "start" call
		    	meterName,			-- child Alt ID
		    	childName,			-- child device description 
		    	"", 				-- serviceId (keep blank for UI7 restart avoidance)
		    	"D_PowerMeter1.xml",-- device file for given device
		    	"",					-- Implementation file
		    	init,				-- parameters to set 
		    	true)				-- not embedded child devices can go in any room
end

-- Create any child devices we may have
local function SolarMeter_CreateChildren()
	local childDevices = luup.chdev.start(PlugIn.THIS_DEVICE);  

	if var.GetNumber("ShowBatteryChild") == 1 then
		addMeterDevice(childDevices, "BatteryIn")
		addMeterDevice(childDevices, "BatteryOut")
	end
	if var.GetNumber("ShowGridChild") == 1 then
		addMeterDevice(childDevices, "GridIn")
		addMeterDevice(childDevices, "GridOut")
	end
	if var.GetNumber("ShowHouseChild") == 1 then
		addMeterDevice(childDevices, "House")
	end
	-- Vera will reload here when there are new devices or changes to a child
	luup.chdev.sync(PlugIn.THIS_DEVICE, childDevices)
end

------------------------------------------------------------------------------------------
-- Init and Refresh functions for supported systems.                  --
-- Init and Refresh to return true on success, false on faiure
-- Refresh on success also returns timestamp of sample, Watts, DayKWH, WeekKWH, MonthKWH, LifetimeKWH
------------------------------------------------------------------------------------------
-- Enphase reading from Envoy on local network
function SS_EnphaseLocal_Init()
	local ipa = var.Get("EN_IPAddress")
	local ipAddress = string.match(ipa, '^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')
	if (ipAddress == nil) then 
		log.Error("Enphase Local, missing IP address.")
		return false
	end
	InitMonthTotal()
	InitYearTotal()
	return true
end

function SS_EnphaseLocal_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = -1,-1,-1,-1,-1,-1,-1
	local ipa = var.Get("EN_IPAddress")
	local URL = "http://%s/api/v1/production"
	URL = URL:format(ipa)
	log.Debug("Envoy Local URL " .. URL)
	ts = os.time()
	local retCode, dataRaw, HttpCode  = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)
		local retData = json.decode(dataRaw)
		-- Set values in PowerMeter
		watts = GetAsNumber(retData.wattsNow)
		DayKWH = GetAsNumber(retData.wattHoursToday)/1000
		WeekKWH = GetAsNumber(retData.wattHoursSevenDays)/1000
		LifeKWH = GetAsNumber(retData.wattHoursLifetime)/1000
		MonthKWH = GetMonthTotal(DayKWH)
		YearKWH = GetYearTotal(MonthKWH)
		retData = nil 
		-- Only update time stamp if watts or DayKWH are changed.
		if watts == var.GetNumber("Watts", PlugIn.EM_SID) and DayKWH == var.GetNumber("DayKWH", PlugIn.EM_SID) then
			ts = var.GetNumber("LastRefresh", PlugIn.EM_SID)
			if ts == 0 then ts = os.time() end  -- First readout.
		end
		return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
	else
		return false, (HttpCode or -99), "HTTP Get to "..URL.." failed."
	end
end

-- Enphase reading from Enphase API
function SS_EnphaseRemote_Init()
	local key = var.Get("EN_APIKey")
	local user = var.Get("EN_UserID")
	local sys = var.Get("EN_SystemID")

	if key == "" or user == "" or sys == "" then
		log.Error("Enphase Remote, missing configuration details.")
		return false
	end
	InitWeekTotal()
	InitMonthTotal()
	InitYearTotal()
	return true
end

function SS_EnphaseRemote_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = -1,-1,-1,-1,-1,-1,-1
	local key = var.Get("EN_APIKey")
	local user = var.Get("EN_UserID")
	local sys = var.Get("EN_SystemID")
	local URL = "https://api.enphaseenergy.com/api/v2/systems/%s/summary?key=%s&user_id=%s"
	URL = URL:format(sys,key,user)
	log.Debug("Envoy Remote URL " .. URL)
	local retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)
		local retData = json.decode(dataRaw)
		-- Get standard values
		watts = GetAsNumber(retData.current_power)
		DayKWH = GetAsNumber(retData.energy_today)/1000
		LifeKWH = GetAsNumber(retData.energy_lifetime)/1000
		WeekKWH = GetWeekTotal(DayKWH)
		MonthKWH = GetMonthTotal(DayKWH)
		YearKWH = GetYearTotal(MonthKWH)

		-- Get additional data
		var.Set("Enphase_ModuleCount", retData.modules)
		var.Set("Enphase_MaxPower", retData.size_w)
		var.Set("Enphase_Status", retData.status)
		var.Set("Enphase_InstallDate", retData.operational_at)
		var.Set("Enphase_LastReport", retData.last_report_at)
		ts = retData.last_interval_end_at
		retData = nil 
		return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
	else
		return false, HttpCode, "HTTP Get to "..URL.." failed."
	end  
end

-- For Fronius Solar API V1
-- See http://www.fronius.com/en/photovoltaics/products/commercial/system-monitoring/open-interfaces/fronius-solar-api-json-
function SS_FroniusAPI_Init()
	local ipa = var.Get("FA_IPAddress")
	local dev = var.Get("FA_DeviceID")
	local ipAddress = string.match(ipa, '^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')
	if (ipAddress == nil or dev == "") then 
		log.Error("Fronius API, missing configuration details.")
		return false
	end
	InitWeekTotal()
	InitMonthTotal()
	return true
end

function SS_FroniusAPI_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = -1,-1,-1,-1,-1,-1,-1
	local ipa = var.Get("FA_IPAddress")
	local dev = var.Get("FA_DeviceID")

	local URL = "http://%s/solar_api/v1/GetInverterRealtimeData.cgi?Scope=Device&DeviceId=%s&DataCollection=CommonInverterData"
	URL = URL:format(ipa,dev)
	log.Debug("Fronius URL " .. URL)
	ts = os.time()
	local retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)

		-- Get standard values
		local retData = json.decode(dataRaw)
    
		-- Get standard values
		retData = retData.Body.Data
		if retData then
			watts = GetAsNumber(retData.PAC.Value)
			DayKWH = GetAsNumber(retData.DAY_ENERGY.Value) / 1000
			YearKWH = GetAsNumber(retData.YEAR_ENERGY.Value) / 1000
			LifeKWH = GetAsNumber(retData.TOTAL_ENERGY.Value) / 1000
			WeekKWH = GetWeekTotal(DayKWH)
			MonthKWH = GetMonthTotal(DayKWH)
			var.Set("Fronius_Status", retData.DeviceStatus.StatusCode)
			var.Set("Fronius_IAC", retData.IAC.Value)
			var.Set("Fronius_IDC", retData.IDC.Value)
			var.Set("Fronius_UAC", retData.UAC.Value)
			var.Set("Fronius_UDC", retData.UDC.Value)
			-- Only update time stamp if watts or DayKWH are changed.
			if watts == var.GetNumber("Watts", PlugIn.EM_SID) and DayKWH == var.GetNumber("DayKWH", PlugIn.EM_SID) then
				ts = var.GetNumber("LastRefresh", PlugIn.EM_SID)
			end

			-- Addition to read Power Meter values from Fronius  -- Octoplayer July 2019
			URL = "http://%s//solar_api/v1/GetPowerFlowRealtimeData.fcgi"
			URL = URL:format(ipa)
			log.Debug("Fronius Power URL " .. URL)
			retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
			if (retCode == 0 and HttpCode == 200) then
				log.Debug("Retrieve HTTP Get Power Complete...")
				log.Debug(dataRaw)

				-- Get Power values
				local retData = json.decode(dataRaw)
				retData = retData.Body.Data
				if retData then
					if retData.Site then
						local value = retData.Site.P_Grid
						if type(value) == "number" then
							if value == 0 then
								var.Set("GridWatts",0)
								var.Set("GridStatus","Static")
							elseif value < 0 then
								var.Set("GridWatts",math.abs(value))
								var.Set("GridStatus","Sell")
							else
								var.Set("GridWatts",value)
								var.Set("GridStatus","Buy")
							end
						end	
						local value = retData.Site.P_Akku
						if type(value) == "number" then
							if value == 0 then
								var.Set("BatteryWatts",0)
								var.Set("BatteryStatus","Static")
							elseif value < 0 then
								var.Set("BatteryWatts",math.abs(value))
								var.Set("BatteryStatus","Charge")
							else
								var.Set("BatteryWatts",value)
								var.Set("BatteryStatus","Discharge")
							end
						end	
						local value = retData.Site.P_Akku
						if type(value) == "number" then
							if value == 0 then
								var.Set("BatteryWatts",0)
								var.Set("BatteryStatus","Static")
							elseif value < 0 then
								var.Set("BatteryWatts",math.abs(value))
								var.Set("BatteryStatus","Charge")
							else
								var.Set("BatteryWatts",value)
								var.Set("BatteryStatus","Discharge")
							end
						end	
						local value = retData.Site.P_Load
						if type(value) == "number" then
							var.Set("HouseWatts",math.abs(value))
						else	
							var.Set("HouseWatts",0)
						end	
					end	
					var.Set("BatterySOC", retData.Invertors[1].SOC)  -- may need different index, 
				end
			end
			retData = nil 
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return false, HttpCode, "No data received."
		end
	else
		return false, HttpCode, "HTTP Get to "..URL.." failed."
	end 

 end

-- Solar Edge. thanks to cmille34. http://forum.micasaverde.com/index.php/topic,39157.msg355189.html#msg355189
function SS_SolarEdge_Init()
	local key = var.Get("SE_APIKey")
	local sys = var.Get("SE_SystemID")

	if key == "" or sys == "" then
		log.Error("Solar Edge, missing configuration details.")
		return false
	end
	InitWeekTotal()
	return true
end

function SS_SolarEdge_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = -1,-1,-1,-1,-1,-1,-1
	local key = var.Get("SE_APIKey")
	local sys = var.Get("SE_SystemID")

	local URL = "https://monitoringapi.solaredge.com/site/%s/overview.json?api_key=%s"
	URL = URL:format(sys,key)
	log.Debug("Solar Edge URL " .. URL)
	local retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)
		local retData = json.decode(dataRaw)
    
		-- Get standard values
		retData = retData.overview
		if retData then
			watts = GetAsNumber(retData.currentPower.power)
			DayKWH = GetAsNumber(retData.lastDayData.energy)/1000
			WeekKWH = GetWeekTotal(DayKWH)
			MonthKWH = GetAsNumber(retData.lastMonthData.energy)/1000
			YearKWH = GetAsNumber(retData.lastYearData.energy)/1000
			LifeKWH = GetAsNumber(retData.lifeTimeData.energy)/1000
			local timefmt = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
			local yyyy,mm,dd,h,m,s = retData.lastUpdateTime:match(timefmt)
			ts = os.time({day=dd,month=mm,year=yyyy,hour=h,min=m,sec=s})
			retData = nil 
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return false, HttpCode, "No data received."
		end
	else
		return false, HttpCode, "HTTP Get to "..URL.." failed."
	end  
end

-- For SunGrow. Note clear text password over non-secure connection to China!
-- Not tested.
-- Thanks to Homey SolarPanels app. https://github.com/DiedB/SolarPanels/blob/master/drivers/sungrow/device.js
function SS_SunGrow_Init()
	local uid = var.Get("SG_UserID")
	local pwd = var.Get("SG_Password")

	if uid == "" or pwd == "" then
		log.Error("SUNGROW, missing configuration details.")
		return false
	end
	InitWeekTotal()
	InitMonthTotal()
	InitYearTotal()
	return true
end

function SS_SunGrow_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = -1,-1,-1,-1,-1,-1,-1
	local uid = var.Get("SG_UserID")
	local pwd = var.Get("SG_Password")

	local URL = "http://www.solarinfobank.com/openapi/loginvalidV2?username=%s&password=%s"
	URL = URL:format(uid,pwd)
	log.Debug("SUNGROW URL " .. URL)
	ts = os.time()
	local retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)

		-- Get standard values
		local retData = json.decode(dataRaw)
    
		-- Get standard values
		if retData then
			watts = math.floor(GetAsNumber(retData.power) * 1000)
			DayKWH = GetAsNumber(retData.todayEnergy)
			WeekKWH = GetWeekTotal(DayKWH)
			MonthKWH = GetMonthTotal(DayKWH)
			YearKWH = GetYearTotal(MonthKWH)
			-- Only update time stamp if watts are updated.
			if watts == var.GetNumber("Watts", PlugIn.EM_SID) then
				ts = var.GetNumber("LastRefresh", PlugIn.EM_SID)
				if ts == 0 then ts = os.time() end
			end
			retData = nil 
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return false, HttpCode, "No data received."
		end
	else
		return false, HttpCode, "HTTP Get to "..URL.." failed."
	end  
end

-- For PV Output. Useful when this plugin does not support your system
function SS_PVOutput_Init()
	local key = var.Get("PV_APIKey")
	local sys = var.Get("PV_SystemID")
	var.Default("PV_HTTPS",0)

	if key == "" or sys == "" then
		log.Error("PV Output, missing configuration details.")
		return false
	end
	InitWeekTotal()
	InitMonthTotal()
	InitYearTotal()
	return true
end

function SS_PVOutput_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = -1,-1,-1,-1,-1,-1,-1
	local key = var.Get("PV_APIKey")
	local sys = var.Get("PV_SystemID")
	local sec = (((var.GetNumber("PV_HTTPS") == 1) and "s") or "")

	local URL = "http%s://pvoutput.org/service/r2/getstatus.jsp?key=%s&sid=%s"
	URL = URL:format(sec,key,sys)
	log.Debug("PV Output URL " .. URL)
	local retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)

		-- Get standard values
		local d_t = {}
		string.gsub(dataRaw,"(.-),", function(c) d_t[#d_t+1] = c end)
		if #d_t > 3 then
			watts = GetAsNumber(d_t[4])
			DayKWH = GetAsNumber(d_t[3])/1000
			WeekKWH = GetWeekTotal(DayKWH)
			MonthKWH = GetMonthTotal(DayKWH)
			YearKWH = GetYearTotal(MonthKWH)
			local timefmt = "(%d%d%d%d)(%d%d)(%d%d) (%d+):(%d+)"
			local yyyy,mm,dd,h,m = string.match(d_t[1].." "..d_t[2],timefmt)
			ts = os.time({day=dd,month=mm,year=yyyy,hour=h,min=m,sec=0})
			retData = nil 
			if #d_t > 4 then var.Set("PV_EnergyConsumption", d_t[5]) end
			if #d_t > 5 then var.Set("PV_PowerConsumption", d_t[6]) end
			if #d_t > 6 then var.Set("PV_NormalisedOutput", d_t[7]) end
			if #d_t > 7 then var.Set("PV_Temperature", d_t[8]) end
			if #d_t > 8 then var.Set("PV_Voltage", d_t[9]) end
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return false, HttpCode, "No data received."
		end
	else
		return false, HttpCode, "HTTP Get to "..URL.." failed."
	end  
end

------------------------------------------------------------------------------------------
-- For Solarman  --Octoplayer. Thanks to David H for advice on extracting the URLs

-- As the Solarman open API is not well documented and there are no examples or support, 
-- this is a workaround pulling the data direct from the portal page (screen scrape).
-- It uses a long URL entered in the Control panel, to get this is a one-off process. 

-- Log into the Solarman home.solarman.cn portal, I used Chrome, other browsers may do this differently... 
-- Select the Details Tab and then select the Logger. On the Dev panel select the Network tab
-- Press F5 or ctrl + R to refresh the page
-- On the left of the panel should appear the 'goDetailAjax' set.
-- right click on this - and select "copy as cURL for Bash"
-- Paste this into the URL config box on Solar Meter.

function SS_Solarman_Init()
	local SMD= var.Get("SM_DeviceID")
	local SMS= var.Get("SM_rememberMe")
	if SMS== "" or SMD == "" then 
		log.Error("Solarman, missing configuration details.")
		return false
	end
	InitWeekTotal()
	return true
end

function SS_Solarman_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = -1,-1,-1,-1,-1,-1,-1

	local SMD= var.Get("SM_DeviceID")
	local SMS= var.Get("SM_rememberMe")

	
	URL = "http://home.solarman.cn/cpro/device/inverter/goDetailAjax.json"
	log.Debug("Solarman URL " .. URL)

	local result = {}
	local headers = {
		['origin'] = 'http://home.solarman.cn',
		['referer'] = 'http://home.solarman.cn/device/inverter/view.html?v=2.1.28&deviceId='..SMD,
		['accept'] = 'application/json',
		['accept-encoding'] = 'identity',
		['content-type'] = 'application/x-www-form-urlencoded',
		['connection'] = 'keep-alive',
		['cookie'] = 'language=2; autoLogin=on; Language=en_US; rememberMe='..SMS
	}	

	local request_body = "deviceId=" .. SMD
	headers["content-length"] = string.len(request_body)

	local retCode,HttpCode = http.request{
		url=URL, 
		method='POST',
		sink=ltn12.sink.table(result),
		source = ltn12.source.string(request_body),
		headers = headers
	}
	if (retCode ~= nil and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		local dataRaw = table.concat(result)
		log.Debug(dataRaw)
		local js_res = nil
		if string.len(dataRaw) > 100 then
			js_res = json.decode(dataRaw)
			if js_res ~= nil then
			  	local retData = js_res.result.deviceWapper
				-- Solar Inverter Data
				local volts, amps = 0,0
				for key, value in pairs(retData.dataJSON) do
					if key == "dt" then
						ts = GetAsNumber(value) / 1000
					elseif key == "1ab" then 		-- DC Output Total Power (Active)
						watts = GetAsNumber(value)
					elseif key == "1bd" then 		-- Daily Generation (Active)
						DayKWH = GetAsNumber(value)
						WeekKWH = GetWeekTotal(DayKWH)
					elseif key == "1be" then 	-- Monthly Generation (Active)
						MonthKWH = GetAsNumber(value)
					elseif key == "1bf" then 	-- Annual Generation (Active)
						YearKWH = GetAsNumber(value)
					elseif key == "1bc" then 	-- Total Generation (Active)
						LifeKWH = GetAsNumber(value)
					elseif key == "1df" then 	-- Inverter Temperature
						var.Set("InverterTemperature",GetAsNumber(value))
					elseif key == "1ez" then 	-- Inverter Status
						var.Set("InverterStatus", value)
					-- Battery data
					elseif key == "1ff" then
						local stat = GetAsNumber(value)
						if stat == 0 then
							var.Set("BatteryStatus","Static")
						elseif stat == 1 then
							var.Set("BatteryStatus","Charge")
						elseif stat == 2 then
							var.Set("BatteryStatus","Discharge")
						end
					elseif key == "1cr" then 	
						var.Set("BatteryVoltage",GetAsNumber(value))
					elseif key == "1cv" then 	
						var.Set("BatteryRemainingCapacity",GetAsNumber(value))
					elseif key == "1cs" then 	
						var.Set("BatteryCurrent",GetAsNumber(value))
					elseif key == "1ct" then 	
						var.Set("BatteryWatts",GetAsNumber(value))
					elseif key == "1cz" then 	
						var.Set("BatteryDayChargedKWH",GetAsNumber(value))
					elseif key == "1da" then 	
						var.Set("BatteryDayDischargedKWH",GetAsNumber(value))
					elseif key == "xxx" then 	
						var.Set("BatteryWeekChargedKWH",GetAsNumber(value))
					elseif key == "xxx" then 	
						var.Set("BatteryWeekDischargedKWH",GetAsNumber(value))
					elseif key == "1db" then 	
						var.Set("BatteryMonthChargedKWH",GetAsNumber(value))
					elseif key == "1dc" then 	
						var.Set("BatteryMonthDischargedKWH",GetAsNumber(value))
					elseif key == "1dd" then 	
						var.Set("BatteryYearChargedKWH",GetAsNumber(value))
					elseif key == "1de" then 	
						var.Set("BatteryYearDischargedKWH",GetAsNumber(value))
					elseif key == "1cx" then 	
						var.Set("BatteryLifeChargedKWH",GetAsNumber(value))
					elseif key == "1cy" then 	
						var.Set("BatteryLifeDischargedKWH",GetAsNumber(value))
					-- Grid data  
					elseif key == "1fe" then
						local stat = GetAsNumber(value)
						if stat == 0 then
							var.Set("GridStatus","Static")
						elseif stat == 1 then
							var.Set("GridStatus","Sell")
						elseif stat == 2 then
							var.Set("GridStatus","Buy")
						end
					elseif key == "1bq" then 
						var.Set("GridWatts",GetAsNumber(value))
					elseif key == "1bx" then 	
						var.Set("GridDayPurchasedKWH",GetAsNumber(value))
					elseif key == "1bw" then 	
						var.Set("GridDayDeliveredKWH",GetAsNumber(value))
					elseif key == "xxx" then 	
						var.Set("GridWeekDeliveredKWH",GetAsNumber(value))
					elseif key == "xxx" then 	
						var.Set("GridWeekPurchasedKWH",GetAsNumber(value))
					elseif key == "1by" then 	
						var.Set("GridMonthDeliveredKWH",GetAsNumber(value))
					elseif key == "1bz" then 	
						var.Set("GridMonthPurchasedKWH",GetAsNumber(value))
					elseif key == "1cb" then 	
						var.Set("GridYearPurchasedKWH",GetAsNumber(value))
					elseif key == "1ca" then 	
						var.Set("GridYearDeliveredKWH",GetAsNumber(value))
					elseif key == "1bv" then 	
						var.Set("GridLifePurchasedKWH",GetAsNumber(value))
					elseif key == "1bu" then 	
						var.Set("GridLifeDeliveredKWH",GetAsNumber(value))
					-- House total data  
					elseif key == "1cj" then 
						var.Set("HouseWatts",GetAsNumber(value))
					elseif key == "1co" then 	
						var.Set("HouseDayKWH",GetAsNumber(value))
					elseif key == "xxx" then 	
						var.Set("HouseWeekKWH",GetAsNumber(value))
					elseif key == "1cp" then 	
						var.Set("HouseMonthKWH",GetAsNumber(value))
					elseif key == "1cq" then 	
						var.Set("HouseYearKWH",GetAsNumber(value))
					elseif key == "1cn" then 	
						var.Set("HouseLifeKWH",GetAsNumber(value))
					end
				end
				retData = nil 
				if watts == -1 then watts = 0 end	-- Not sure where to get it from, return zero rather than -1
				return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
			else
				return false, HttpCode, "No valid data received."
			end
		else
			return false, HttpCode, "No valid data received."
		end
	else
		return false, HttpCode, "HTTP Get to "..URL.." failed."
	end  
end

------------------------------------------------------------------------------------------
-- Start up plug in
function SolarMeter_Init(lul_device)
	PlugIn.THIS_DEVICE = lul_device
	-- start Utility API's
	log = logAPI()
	var = varAPI()
	utils = utilsAPI()
	var.Initialize(PlugIn.SM_SID, PlugIn.THIS_DEVICE)
  
	var.Default("LogLevel", log.LLError)
	log.Initialize(PlugIn.DESCRIPTION, var.GetNumber("LogLevel"))
	utils.Initialize()
  
	log.Info("Starting version %s device: %s", PlugIn.Version, tostring(PlugIn.THIS_DEVICE))
	var.Set("Version", PlugIn.Version)

	-- Create variables if needed.
	var.Default("ActualUsage", 1, PlugIn.EM_SID)
	var.Default("System", PlugIn.System)
	var.Default("DayInterval", PlugIn.DInterval)
	var.Default("ShowGridChild", 0)
	var.Default("ShowHouseChild", 0)
	var.Default("ShowBatteryChild", 0)
	var.Default("Watts", 0, PlugIn.EM_SID)
	var.Default("KWH", 0, PlugIn.EM_SID)
	var.Default("DayKWH", 0, PlugIn.EM_SID)
	var.Default("WeekKWH", 0, PlugIn.EM_SID)
	var.Default("MonthKWH", 0, PlugIn.EM_SID)
	var.Default("YearKWH", 0, PlugIn.EM_SID)
	var.Default("LifeKWH", 0, PlugIn.EM_SID)
  
	-- Create any child devices
	SolarMeter_CreateChildren()

	-- See if user disabled plug-in 
	local isDisabled = luup.attr_get("disabled", PlugIn.THIS_DEVICE)
	if ((isDisabled == 1) or (isDisabled == "1")) then
		log.Log("Init: Plug-in version "..PlugIn.Version.." - DISABLED",2)
		PlugIn.Disabled = true
		var.Set("DisplayLine2", "Disabled. ", PlugIn.ALTUI_SID)
		-- Still create any child devices so we do not loose configurations.
		utils.SetLuupFailure(0, PlugIn.THIS_DEVICE)
		return true, "Plug-in disabled attribute set", PlugIn.DESCRIPTION
	end

	-- Put known systems routines in map, keep in sync with J_SolarMeter.js var solarSystem
	addSolarSystem(1, SS_EnphaseLocal_Init, SS_EnphaseLocal_Refresh)
	addSolarSystem(2, SS_EnphaseRemote_Init, SS_EnphaseRemote_Refresh)
	addSolarSystem(3, SS_SolarEdge_Init, SS_SolarEdge_Refresh)
	addSolarSystem(4, SS_PVOutput_Init, SS_PVOutput_Refresh)
	addSolarSystem(5, SS_SunGrow_Init, SS_SunGrow_Refresh)
	addSolarSystem(6, SS_FroniusAPI_Init, SS_FroniusAPI_Refresh)
 	addSolarSystem(7, SS_Solarman_Init, SS_Solarman_Refresh)
  
	-- Run Init function for specific solar system
	local solSystem = var.GetNumber("System")
	local my_sys = nil
	if solSystem ~= 0 then
		my_sys = SolarSystems[solSystem]
	end
	if my_sys then
		local ret, res = pcall(my_sys.init)
		if not ret then
			log.Error("Init failed "..(res or "unknown"))
			utils.SetLuupFailure(1, PlugIn.THIS_DEVICE)
			return false, "Init routing failed.", PlugIn.DESCRIPTION
		else
			if res ~= true then
				log.Error("Init failed")
				utils.SetLuupFailure(1, PlugIn.THIS_DEVICE)
				return false, "Configure system parameters via Settings.", PlugIn.DESCRIPTION
			end
		end
	else  
		log.Error("No solar system selected ")
		utils.SetLuupFailure(1, PlugIn.THIS_DEVICE)
		return false, "Configure solar system via Settings.", PlugIn.DESCRIPTION
	end
	
	-- Find any child devices and get device ID's for updating
  	for k, v in pairs(luup.devices) do
		if tonumber(v.device_num_parent) == tonumber(PlugIn.THIS_DEVICE) then
			if v.id == "SMTR_House" then
				PlugIn.HouseDevice = k
				log.Debug("House Child Device ID : %d", k)
			elseif v.id == "SMTR_GridIn" then
				PlugIn.GridInDevice = k
				log.Debug("Grid In Child Device ID : %d", k)
			elseif v.id == "SMTR_GridOut" then
				PlugIn.GridOutDevice = k
				log.Debug("Grid Out Child Device ID : %d", k)
			elseif v.id == "SMTR_BatteryIn" then
				PlugIn.BatteryInDevice = k
				log.Debug("Battery In Child Device ID : %d", k)
			elseif v.id == "SMTR_BatteryOut" then
				PlugIn.BatteryOutDevice = k
				log.Debug("Battery Out Child Device ID : %d", k)
			end
		end
	end

	luup.call_delay("SolarMeter_Refresh", 30)
	log.Debug("SolarMeter has started...")
	utils.SetLuupFailure(0, PlugIn.THIS_DEVICE)
	return true, "Start up complete", PlugIn.DESCRIPTION
end

-- Get values from solar system
function SolarMeter_Refresh()
	-- app's own memory usage in kB
	local AppMemoryUsed =  math.floor(collectgarbage "count")
	var.Set("AppMemoryUsed", AppMemoryUsed) 

	-- Get system configured
	local solSystem = var.GetNumber("System")
	local my_sys = nil
	if solSystem ~= 0 then
		my_sys = SolarSystems[solSystem]
	end
	if my_sys then
		local ret, res, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = pcall(my_sys.refresh)
		if ret == true then 
			if res == true then
				log.Debug("Current Power --> "..watts.." W")
				log.Debug("KWH Today     --> "..DayKWH.." kWh")
				log.Debug("KWH Week      --> "..WeekKWH.." kWh")
				log.Debug("KWH Month     --> "..MonthKWH.." kWh")
				log.Debug("KWH Year      --> "..YearKWH.." kWh")
				log.Debug("KWH Lifetime  --> "..LifeKWH.." kWh")
				-- Set values in PowerMeter
				if watts ~= -1 then var.Set("Watts", watts, PlugIn.EM_SID) end
				if DayKWH ~= -1 then 
					var.Set("KWH", math.floor(DayKWH), PlugIn.EM_SID)
					var.Set("DayKWH", DayKWH, PlugIn.EM_SID) 
				end
				if WeekKWH ~= -1 then var.Set("WeekKWH", WeekKWH, PlugIn.EM_SID) end
				if MonthKWH ~= -1 then var.Set("MonthKWH", MonthKWH, PlugIn.EM_SID) end
				if YearKWH ~= -1 then var.Set("YearKWH", YearKWH, PlugIn.EM_SID) end
				if LifeKWH ~= -1 then var.Set("LifeKWH", LifeKWH, PlugIn.EM_SID) end
				var.Set("LastRefresh", ts,  PlugIn.EM_SID)
				var.Set("LastUpdate", os.date("%H:%M:%S %d", ts))
				var.Set("HttpCode", "Ok")
				local dl1 ="%d Watts"
				var.Set("DisplayLine1", dl1:format(watts), PlugIn.ALTUI_SID)
				local dl2 ="Day: %.3f  Last Upd: %s"
				var.Set("DisplayLine2", dl2:format(DayKWH, os.date("%H:%M", ts)), PlugIn.ALTUI_SID)
				-- Update child devices
				if PlugIn.HouseDevice then
					var.Set("Watts", var.Get("HouseWatts"), PlugIn.EM_SID, PlugIn.HouseDevice)
					var.Set("KWH", var.Get("HouseDayKWH"), PlugIn.EM_SID, PlugIn.HouseDevice)
					var.Set("DayKWH", var.Get("HouseDayKWH"), PlugIn.EM_SID, PlugIn.HouseDevice)
					var.Set("WeekKWH", var.Get("HouseWeekKWH"), PlugIn.EM_SID, PlugIn.HouseDevice)
					var.Set("MonthKWH", var.Get("HouseMonthKWH"), PlugIn.EM_SID, PlugIn.HouseDevice)
					var.Set("YearKWH", var.Get("HouseYearKWH"), PlugIn.EM_SID, PlugIn.HouseDevice)
					var.Set("LifeKWH", var.Get("HouseLifeKWH"), PlugIn.EM_SID, PlugIn.HouseDevice)
				end
				if PlugIn.GridInDevice then
					if var.Get("GridStatus") == "Buy" then
						var.Set("Watts", math.abs(var.GetNumber("GridWatts")), PlugIn.EM_SID, PlugIn.GridInDevice)
					else
						var.Set("Watts", 0, PlugIn.EM_SID, PlugIn.GridInDevice)
					end
					var.Set("KWH", var.Get("GridDayPurchasedKWH"), PlugIn.EM_SID, PlugIn.GridInDevice)
					var.Set("DayKWH", var.Get("GridDayPurchasedKWH"), PlugIn.EM_SID, PlugIn.GridInDevice)
					var.Set("WeekKWH", var.Get("GridWeekPurchasedKWH"), PlugIn.EM_SID, PlugIn.GridInDevice)
					var.Set("MonthKWH", var.Get("GridMonthPurchasedKWH"), PlugIn.EM_SID, PlugIn.GridInDevice)
					var.Set("YearKWH", var.Get("GridYearPurchasedKWH"), PlugIn.EM_SID, PlugIn.GridInDevice)
					var.Set("LifeKWH", var.Get("GridLifePurchasedKWH"), PlugIn.EM_SID, PlugIn.GridInDevice)
				end
				if PlugIn.GridOutDevice then
					if var.Get("GridStatus") == "Sell" then
						var.Set("Watts", math.abs(var.GetNumber("GridWatts")), PlugIn.EM_SID, PlugIn.GridOutDevice)
					else
						var.Set("Watts", 0, PlugIn.EM_SID, PlugIn.GridOutDevice)
					end  
					var.Set("KWH", var.Get("GridDayDeliveredKWH"), PlugIn.EM_SID, PlugIn.GridOutDevice)
					var.Set("DayKWH", var.Get("GridDayDeliverdKWH"), PlugIn.EM_SID, PlugIn.GridOutDevice)
					var.Set("WeekKWH", var.Get("GridWeekDeliveredKWH"), PlugIn.EM_SID, PlugIn.GridOutDevice)
					var.Set("MonthKWH", var.Get("GridMonthDeliveredKWH"), PlugIn.EM_SID, PlugIn.GridOutDevice)
					var.Set("YearKWH", var.Get("GridYearDeliveredKWH"), PlugIn.EM_SID, PlugIn.GridOutDevice)
					var.Set("LifeKWH", var.Get("GridLifeDeliveredKWH"), PlugIn.EM_SID, PlugIn.GridOutDevice)
				end
				if PlugIn.BatteryInDevice then
					if var.Get("BatteryStatus") == "Charge" then
						var.Set("Watts", math.abs(var.Get("BatteryWatts")), PlugIn.EM_SID, PlugIn.BatteryInDevice)
					else
						var.Set("Watts", 0, PlugIn.EM_SID, PlugIn.BatteryInDevice)
					end
					var.Set("KWH", var.Get("BatteryDayChargedKWH"), PlugIn.EM_SID, PlugIn.BatteryInDevice)
					var.Set("DayKWH", var.Get("BatteryDayChargedKWH"), PlugIn.EM_SID, PlugIn.BatteryInDevice)
					var.Set("WeekKWH", var.Get("BatteryWeekChargedKWH"), PlugIn.EM_SID, PlugIn.BatteryInDevice)
					var.Set("MonthKWH", var.Get("BatteryMonthChargedKWH"), PlugIn.EM_SID, PlugIn.BatteryInDevice)
					var.Set("YearKWH", var.Get("BatteryYearChargedKWH"), PlugIn.EM_SID, PlugIn.BatteryInDevice)
					var.Set("LifeKWH", var.Get("BatteryLifeChargedKWH"), PlugIn.EM_SID, PlugIn.BatteryInDevice)
				end
				if PlugIn.BatteryOutDevice then
					if var.Get("BatteryStatus") == "Discharge" then
						var.Set("Watts", math.abs(var.Get("BatteryWatts")), PlugIn.EM_SID, PlugIn.BatteryOutDevice)
					else
						var.Set("Watts", 0, PlugIn.EM_SID, PlugIn.BatteryOutDevice)
					end
					var.Set("KWH", var.Get("BatteryDayDischargedKWH"), PlugIn.EM_SID, PlugIn.BatteryOutDevice)
					var.Set("DayKWH", var.Get("BatteryDayDischargedKWH"), PlugIn.EM_SID, PlugIn.BatteryOutDevice)
					var.Set("WeekKWH", var.Get("BatteryWeekDischargedKWH"), PlugIn.EM_SID, PlugIn.BatteryOutDevice)
					var.Set("MonthKWH", var.Get("BatteryMonthDischargedKWH"), PlugIn.EM_SID, PlugIn.BatteryOutDevice)
					var.Set("YearKWH", var.Get("BatteryYearDischargedKWH"), PlugIn.EM_SID, PlugIn.BatteryOutDevice)
					var.Set("LifeKWH", var.Get("BatteryLifeDischargedKWH"), PlugIn.EM_SID, PlugIn.BatteryOutDevice)
				end
			else
				log.Log("Refresh failed "..(watts or "unknown"),2)
				var.Set("HttpCode", ts)
				log.Debug(watts)
			end
		else
			log.Log("Refresh pcall error " ..(res or "unknown"),2)
			var.Set("HttpCode", 0)
		end
	end

	-- Schedule next refresh  (moved to after data refresh so that next call can be scheduled depending on success of this one - Octoplayer)
	local interval = var.GetNumber("DayInterval")
	-- Offset now so we poll once after sunset and current watts is zero.
	local watts = var.GetNumber("Watts", PlugIn.EM_SID)
	local now = os.time() 

	--if (watts == 0) and luup.is_night() then  -- replace with below
	if (watts == 0) and luup.is_night() and solSystem ~= 7 then  -- Let Solarman query run through night for battery status etc.
		interval = os.difftime(luup.sunrise() + 10, now)
		log.Debug("Is Night, restart polling just after sunrise in "..interval.." seconds.")
		log.Debug("Sun set is at : %s", os.date('%c', luup.sunset()))
		log.Debug("Sun rise is at : %s", os.date('%c', luup.sunrise()))  
	else 
		interval = os.difftime(var.GetNumber("LastRefresh", PlugIn.EM_SID) + interval + 30, now) -- Line added to sync with updates, note that Solarman seems to update at 3-6min intervals. Octoplayer
		log.Debug("It's Daytime or Solarman: use modified Day delay Interval SolarMeter_Refresh --> ".. interval)
	end
	if interval <= 30 then -- update was late so dont try again too soon
		interval = 60
		log.Debug("Update was late, try again in " .. interval)
	end
	log.Debug("Interval to SolarMeter_Refresh --> "..interval)
	luup.call_delay("SolarMeter_Refresh", interval) 
	log.Debug("Last Refresh was : " .. os.date('%c', var.GetNumber("LastRefresh", PlugIn.EM_SID)))
	log.Debug("Next poll is at : "..os.date('%c', now + interval))


end
