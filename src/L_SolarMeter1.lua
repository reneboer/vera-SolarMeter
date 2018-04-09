--[==[
	Module L_SolarMeter1.lua
	Written by R.Boer. 
	V1.1 7 April 2018

	V1.1 Changes:
		- Fronius JSON API V1 support
		- Some big fixes
	
 	V1.0 First release

	Get data from several Solar systems
--]==]

local socketLib = require("socket")  -- Required for logAPI module.
local json = require("dkjson")

local PlugIn = {
	Version = "1.1",
	DESCRIPTION = "Solar Meter", 
	SM_SID = "urn:rboer-com:serviceId:SolarMeter1", 
	EM_SID = "urn:micasaverde-com:serviceId:EnergyMetering1", 
	ALTUI_SID = "urn:upnp-org:serviceId:altui1",
	THIS_DEVICE = 0,
	Disabled = false,
	StartingUp = true,
	System = 0,
	DInterval = 30,
	NInterval = 1800

}
local PluginImages = { 'SolarMeter1' }

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
			value = default	or ''
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

-- API to handle basic logging and debug messaging. V2.0, requires socketlib
local function logAPI()
local _LLError = 1
local _LLWarning = 2
local _LLInfo = 8
local _LLDebug = 11
local def_level = _LLError
local def_prefix = ''
local def_debug = false
local syslog

	-- Syslog server support. From Netatmo plugin by akbooer
	local function _init_syslog_server(ip_and_port, tag, hostname)
		local sock = socketLib.udp()
		local facility = 1    -- 'user'
--		local emergency, alert, critical, error, warning, notice, info, debug = 0,1,2,3,4,5,6,7
		local ip, port = ip_and_port:match "^(%d+%.%d+%.%d+%.%d+):(%d+)$"
		if not ip or not port then return nil, "invalid IP or PORT" end
		local serialNo = luup.pk_accesspoint
		hostname = ("Vera-"..serialNo) or "Vera"
		if not tag or tag == '' then tag = def_prefix end
		tag = tag:gsub("[^%w]","") or "No TAG"  -- only alphanumeric, no spaces or other
		local function send (self, content, severity)
			content  = tostring (content)
			severity = tonumber (severity) or 6
			local priority = facility*8 + (severity%8)
			local msg = ("<%d>%s %s %s: %s\n"):format (priority, os.date "%b %d %H:%M:%S", hostname, tag, content)
			sock:send(msg) 
		end
		local ok, err = sock:setpeername(ip, port)
		if ok then ok = {send = send} end
		return ok, err
	end

	local function _update(level)
		if level > 10 then
			def_debug = true
			def_level = 10
		else
			def_debug = false
			def_level = level
		end
	end	

	local function _init(prefix, level)
		_update(level)
		def_prefix = prefix
	end	

	local function _set_syslog(sever)
		if (sever ~= '') then
			_log('Starting UDP syslog service...',7) 
			local err
			syslog, err = _init_syslog_server(server, def_prefix)
			if (not syslog) then _log('UDP syslog service error: '..err,2) end
		else
			syslog = nil
		end	
	end

	local function _log(text, level) 
		local level = (level or 10)
		local msg = (text or "no text")
		if (def_level >= level) then
			if (syslog) then
				local slvl
				if (level == 1) then slvl = 2 
				elseif (level == 2) then slvl = 4 
				elseif (level == 3) then slvl = 5 
				elseif (level == 4) then slvl = 5 
				elseif (level == 7) then slvl = 6 
				elseif (level == 8) then slvl = 6 
				else slvl = 7
				end
				syslog:send(msg,slvl) 
			else
				if (level == 10) then level = 50 end
				luup.log(def_prefix .. ": " .. msg:sub(1,80), (level or 50)) 
			end	
		end	
	end	
	
	local function _debug(text)
		if def_debug then
			luup.log(def_prefix .. "_debug: " .. (text or "no text"), 50) 
		end	
	end
	
	return {
		Initialize = _init,
		LLError = _LLError,
		LLWarning = _LLWarning,
		LLInfo = _LLInfo,
		LLDebug = _LLDebug,
		Update = _update,
		SetSyslog = _set_syslog,
		Log = _log,
		Debug = _debug
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
	
	-- Create links for UI6 or UI7 image locations if missing.
	local function _check_images(imageTable)
		local imagePath =""
		local sourcePath = "/www/cmh/skins/default/icons/"
		if (luup.version_major >= 7) then
			imagePath = "/www/cmh/skins/default/img/devices/device_states/"
		elseif (luup.version_major == 6) then
			imagePath = "/www/cmh_ui6/skins/default/icons/"
		else
			-- Default if for UI5, no idea what applies to older versions
			imagePath = "/www/cmh/skins/default/icons/"
		end
		if (imagePath ~= sourcePath) then
			for i = 1, #imageTable do
				local source = sourcePath..imageTable[i]..".png"
				local target = imagePath..imageTable[i]..".png"
				os.execute(("[ ! -e %s ] && ln -s %s %s"):format(target, source, target))
			end
		end	
	end
	
	return {
		Initialize = _init,
		ReloadLuup = _luup_reload,
		CheckImages = _check_images,
		GetMemoryUsed = _getmemoryused,
		SetLuupFailure = _setluupfailure,
		GetUI = _getui,
		IsUI5 = _UI5,
		IsUI6 = _UI6,
		IsUI7 = _UI7,
		IsUI8 = _UI8,
		IsOpenLuup = _OpenLuup
	}
end 


function SolarMeter_registerWithAltUI()
	-- Register with ALTUI once it is ready
	local ALTUI_SID = "urn:upnp-org:serviceId:altui1"
	for k, v in pairs(luup.devices) do
		if (v.device_type == "urn:schemas-upnp-org:device:altui:1") then
			if luup.is_ready(k) then
				log.Debug("Found ALTUI device "..k.." registering devices.")
				local arguments = {}
				arguments["newDeviceType"] = "urn:schemas-rboer-com:device:SolarMeter:1"
				arguments["newScriptFile"] = "J_ALTUI_SolarMeter.js"	
				arguments["newDeviceDrawFunc"] = "ALTUI_SolarMeterDisplays.drawSolarMeter"	
				arguments["newStyleFunc"] = ""	
				arguments["newDeviceIconFunc"] = ""	
				arguments["newControlPanelFunc"] = ""	
				luup.call_action(ALTUI_SID, "RegisterPlugin", arguments, k)
			else
				log.Debug("ALTUI plugin is not yet ready, retry in a bit..")
				luup.call_delay("SolarMeter_registerWithAltUI", 10, "", false)
			end
			break
		end
	end
end


------------------------------------------------------------------------------------------
-- Init and Refresh functions for supported systems.									--
-- Init and Refresh to return true on success, false on faiure
-- Refresh on success also returns timestamp of sample, Watts, DayKWH, WeekKWH, MonthKWH, LifetimeKWH
------------------------------------------------------------------------------------------
-- Enphase reading from Envoy on local network
function SS_EnphaseLocal_Init()
	local ipa = var.Get("EN_IPAddress")
	local ipAddress = string.match(ipa, '^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')
	if (ipAddress == nil) then 
		log.Log("Enphase Local, missing IP address.",3)
		return false
	end
	return true
end

function SS_EnphaseLocal_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = 0,0,0,0,0,0
	local ipa = var.Get("EN_IPAddress")
	local URL = "http://%s/api/v1/production"
	URL = URL:format(ipa)
	log.Debug("Envoy Local URL " .. URL)
	ts = os.time()
	local retCode, dataRaw, HttpCode  = luup.inet.wget(URL,5)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)
		local retData = json.decode(dataRaw)
		-- Set values in PowerMeter
		watts = tonumber(retData.wattsNow)
		DayKWH = retData.wattHoursToday/1000
		WeekKWH = retData.wattHoursSevenDays/1000
		LifeKWH = retData.wattHoursLifetime/1000
		retData = nil 
		-- Only update time stamp if watts or DayKWH are changed.
		if watts == var.GetNumber("Watts", PlugIn.EM_SID) and DayKWH == var.GetNumber("DayKWH", PlugIn.EM_SID) then
			ts = vat.GetNumber("LastRefresh", PlugIn.EM_SID)
		end
		return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
	else
		return "HTTP Get to "..URL.." failed. Error :"..HttpCode
	end
end

-- Enphase reading from Enphase API
function SS_EnphaseRemote_Init()
	local key = var.Get("EN_APIKey")
	local user = var.Get("EN_UserID")
	local sys = var.Get("EN_SystemID")

	if key == "" or user == "" or sys == "" then
		log.Log("Enphase Remote, missing configuration details.",3)
		return false
	end
	return true
end

function SS_EnphaseRemote_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = 0,0,0,0,0,0,0
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
		watts = tonumber(retData.current_power)
		DayKWH = retData.energy_today/1000
		LifeKWH = retData.energy_lifetime/1000

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
		return "HTTP Get to "..URL.." failed. Error :"..HttpCode
	end	
end

-- For Fronius Solar API V1
-- Not tested.
-- See http://www.fronius.com/en/photovoltaics/products/commercial/system-monitoring/open-interfaces/fronius-solar-api-json-
function SS_FroniusAPI_Init()
	local ipa = var.Get("FA_IPAddress")
	local dev = var.Get("FA_DeviceID")
	local ipAddress = string.match(ipa, '^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')
	if (ipAddress == nil or dev == "") then 
		log.Log("Fronius API, missing IP address.",3)
		return false
	end
	return true
end

function SS_FroniusAPI_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = 0,0,0,0,0,0,0
	local ipa = var.Get("FA_IPAddress")
	local dev = var.Get("FA_DeviceID")

	local URL = "http://%s/solar_api/v1/GetInverterRealtimeData.cgi?Scope=Device&DeviceId=%s&DataCollection=CommonInverterData"
	URL = URL:format(ipa,dev)
	log.Debug("Florius URL " .. URL)
	ts = os.time()
	local retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)

		-- Get standard values
		local retData = json.decode(dataRaw)
		
		-- Get standard values
		retData = retData.Data
		if retData then
			watts = tonumber(retData.PAC.Value)
			DayKWH = retData.DAY_ENERGY.Value / 1000
			YearKWH = retData.YEAR_ENERGY.Value / 1000
			LifeKWH = retData.TOTAL_ENERGY.Value / 1000
			var.Set("Fronius_Status", retData.DeviceStatus.StatusCode)
			-- Only update time stamp if watts or DayKWH are changed.
			if watts == var.GetNumber("Watts", PlugIn.EM_SID) and DayKWH == var.GetNumber("DayKWH", PlugIn.EM_SID) then
				ts = vat.GetNumber("LastRefresh", PlugIn.EM_SID)
			end
			retData = nil 
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return "No data received."
		end
	else
		return "HTTP Get to "..URL.." failed. Error :"..HttpCode
	end	
end

-- Solar Edge. thanks to cmille34. http://forum.micasaverde.com/index.php/topic,39157.msg355189.html#msg355189
function SS_SolarEdge_Init()
	local key = var.Get("SE_APIKey")
	local sys = var.Get("SE_SystemID")

	if key == "" or sys == "" then
		log.Log("Solar Edge, missing configuration details.",3)
		return false
	end
	return true
end

function SS_SolarEdge_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = 0,0,0,0,0,0,0
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
			watts = tonumber(retData.currentPower.power)
			DayKWH = retData.lastDayData.energy/1000
			MonthKWH = retData.lastMonthData.energy/1000
			YearKWH = retData.lastYearData.energy/1000
			LifeKWH = retData.lifeTimeData.energy/1000
			local timefmt = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
			local yyyy,mm,dd,h,m,s = retData.lastUpdateTime:match(timefmt)
			ts = os.time({day=dd,month=mm,year=yyyy,hour=h,min=m,sec=s})
			retData = nil 
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return "No data received."
		end
	else
		return "HTTP Get to "..URL.." failed. Error :"..HttpCode
	end	
end

-- For SunGrow. Note clear text password over non-secure connection to China!
-- Not tested.
-- Thanks to Homey SolarPanels app. https://github.com/DiedB/SolarPanels/blob/master/drivers/sungrow/device.js
function SS_SunGrow_Init()
	local uid = var.Get("SG_UserID")
	local pwd = var.Get("SG_Password")

	if uid == "" or pwd == "" then
		log.Log("SUNGROW, missing configuration details.",3)
		return false
	end
	return true
end

function SS_SunGrow_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = 0,0,0,0,0,0,0
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
			watts = math.floor(retData.power * 1000)
			DayKWH = tonumber(retData.todayEnergy)
			-- Only update time stamp if watts are updated.
			if watts == var.GetNumber("Watts", PlugIn.EM_SID) then
				ts = vat.GetNumber("LastRefresh", PlugIn.EM_SID)
			end
			retData = nil 
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return "No data received."
		end
	else
		return "HTTP Get to "..URL.." failed. Error :"..HttpCode
	end	
end

-- For PV Output. Usefull when this plugin does not support your system
function SS_PVOutput_Init()
	local key = var.Get("PV_APIKey")
	local sys = var.Get("PV_SystemID")

	if key == "" or sys == "" then
		log.Log("PV Output, missing configuration details.",3)
		return false
	end
	return true
end

function SS_PVOutput_Refresh()
	local ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = 0,0,0,0,0,0,0
	local key = var.Get("PV_APIKey")
	local sys = var.Get("PV_SystemID")

	local URL = "https://pvoutput.org/service/r2/getstatus.jsp?key=%s&sid=%s"
	URL = URL:format(key,sys)
	log.Debug("PV Output URL " .. URL)
	local retCode, dataRaw, HttpCode = luup.inet.wget(URL,15)
	if (retCode == 0 and HttpCode == 200) then
		log.Debug("Retrieve HTTP Get Complete...")
		log.Debug(dataRaw)

		-- Get standard values
		local d_t = {}
		string.gsub(dataRaw,"(.-),", function(c) d_t[#d_t+1] = c end)
		if #d_t > 2 then
			watts = d_t[4]
			DayKWH = d_t[3]/1000
			local timefmt = "(%d%d%d%d)(%d%d)(%d%d) (%d+):(%d+)"
			local yyyy,mm,dd,h,m = string.match(d_t[1].." "..d_t[2],timefmt)
			ts = os.time({day=dd,month=mm,year=yyyy,hour=h,min=m,sec=0})
			retData = nil 
			return true, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH
		else
			return "No data received."
		end
	else
		return "HTTP Get to "..URL.." failed. Error :"..HttpCode
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
	
	log.Log("Starting version "..PlugIn.Version.." device: " .. tostring(PlugIn.THIS_DEVICE),3)
	var.Set("Version", PlugIn.Version)

	var.Default("ActualUsage", 1, PlugIn.EM_SID)

	-- See if user disabled plug-in 
	local isDisabled = luup.attr_get("disabled", PlugIn.THIS_DEVICE)
	if ((isDisabled == 1) or (isDisabled == "1")) then
		log.Log("Init: Plug-in version "..PlugIn.Version.." - DISABLED",2)
		PlugIn.Disabled = true
		var.Set("DisplayLine2", "Disabled. ", PlugIn.ALTUI_SID)
		utils.SetLuupFailure(0, PlugIn.THIS_DEVICE)
		return true
	end
	-- Read settings.
	var.Default("System", PlugIn.System)
	var.Default("DayInterval", PlugIn.DInterval)
	var.Default("NightInterval", PlugIn.NInterval)
	
	-- Make sure icons are accessible when they should be. 
	utils.CheckImages(PluginImages)

	-- set up logging to syslog	
	log.SetSyslog(var.Default("Syslog")) -- send to syslog if IP address and Port 'XXX.XX.XX.XXX:YYY' (default port 514)

	-- Put known systems routines in map, keep in sync with J_SolarMeter.js var solarSystem
	addSolarSystem(1, SS_EnphaseLocal_Init, SS_EnphaseLocal_Refresh)
	addSolarSystem(2, SS_EnphaseRemote_Init, SS_EnphaseRemote_Refresh)
	addSolarSystem(3, SS_SolarEdge_Init, SS_SolarEdge_Refresh)
	addSolarSystem(4, SS_PVOutput_Init, SS_PVOutput_Refresh)
	addSolarSystem(5, SS_SunGrow_Init, SS_SunGrow_Refresh)
	
	-- Run Init function for specific solar system
	local solSystem = var.GetNumber("System")
	local my_sys = nil
	if solSystem ~= 0 then
		my_sys = SolarSystems[solSystem]
	end
	if my_sys then
		local ret, res = pcall(my_sys.init)
		if not ret then
			log.Log("Init failed "..(res or "unknown"),2)
			utils.SetLuupFailure(1, PlugIn.THIS_DEVICE)
			return false, "Init routing failed.", PlugIn.DESCRIPTION
		else
			if res ~= true then
				log.Log("Init failed",2)
				utils.SetLuupFailure(1, PlugIn.THIS_DEVICE)
				return false, "Configure system parameters via Settings.", PlugIn.DESCRIPTION
			end
		end
	else	
		log.Log("No solar system selected ",2)
		utils.SetLuupFailure(1, PlugIn.THIS_DEVICE)
		return false, "Configure solar system via Settings.", PlugIn.DESCRIPTION
	end
	
	luup.call_delay("SolarMeter_Refresh", 30)
--	luup.call_delay("SolarMeter_registerWithAltUI", 40, "", false)
	log.Debug("SolarMeter has started...")
	utils.SetLuupFailure(0, PlugIn.THIS_DEVICE)
	return true
end

-- Get values from solar system
function SolarMeter_Refresh()
	-- app's own memory usage in kB
	local AppMemoryUsed =  math.floor(collectgarbage "count")
	var.Set("AppMemoryUsed", AppMemoryUsed) 
	-- Schedule next refresh
	local interval 
	if(luup.is_night()) then
		interval = var.GetNumber("NightInterval")
		log.Debug("Is Night use Night delayInterval SolarMeter_Retrieve --> "..interval)
	else 
		interval = var.GetNumber("DayInterval")
		log.Debug("Is Day use Day delay Interval SolarMeter_Retrieve --> "..interval)
	end
	luup.call_delay("SolarMeter_Refresh",interval)	

	-- Get system configured
	local solSystem = var.GetNumber("System")
	local my_sys = nil
	if solSystem ~= 0 then
		my_sys = SolarSystems[solSystem]
	end
	if my_sys then
		local ret, res, ts, watts, DayKWH, WeekKWH, MonthKWH, YearKWH, LifeKWH = pcall(my_sys.refresh)
		if ret and (res == true) then
			log.Debug("Current Power --> "..watts.." W")
			log.Debug("KWH Today     --> "..DayKWH.." KWh")
			log.Debug("KWH Week      --> "..WeekKWH.." KWh")
			log.Debug("KWH Month     --> "..MonthKWH.." KWh")
			log.Debug("KWH Year      --> "..YearKWH.." KWh")
			log.Debug("KWH Lifetime  --> "..LifeKWH.." KWh")
			-- Set values in PowerMeter
			var.Set("Watts", watts, PlugIn.EM_SID)
			var.Set("KWH", math.floor(DayKWH), PlugIn.EM_SID)
			var.Set("DayKWH", DayKWH, PlugIn.EM_SID)
			var.Set("WeekKWH", WeekKWH, PlugIn.EM_SID)
			var.Set("MonthKWH", MonthKWH, PlugIn.EM_SID)
			var.Set("YearKWH", YearKWH, PlugIn.EM_SID)
			var.Set("LifeKWH", LifeKWH, PlugIn.EM_SID)
			var.Set("LastRefresh", ts,  PlugIn.EM_SID)
			var.Set("LastUpdate", os.date("%H:%M %d %b", ts))
			local fmt ="Day: %.3f  Last Upd: %s"
			var.Set("DisplayLine2", fmt:format(DayKWH ,os.date("%H:%M", ts)), PlugIn.ALTUI_SID)
		else
			log.Log("Refresh failed "..(res or "unknown"),2)
		end
	end
end
