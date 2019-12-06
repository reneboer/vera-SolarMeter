//# sourceURL=J_SolarMeter.js
// SmartMeter control UI for UI7 and ALTUI
// Written by R.Boer. 
// V1.11 6 December 2019
//
// V1.11 Changes:
//		Child device support for Fronius
//
// V1.9 Changes:
//		SolarMan support
//
// V1.5.4 Changes:
//		Fix for saving settings on ALTUI
//
// V1.5 Changes:
//		Only one poll interval as polling at night is suspended automatically.
//
// V1.1 Changes:
//		Fronius JSON API V1 support
//
// V1.0 Changes:
//		Initial release

var SolarMeter = (function (api) {

	// Constants. Keep in sync with LUA code.
    var uuid = '12021512-0000-a0a0-b0b0-c0c030303034';
	var SM_SID = 'urn:rboer-com:serviceId:SolarMeter1';
	var ERR_MSG = "Error : ";
	var DIV_PREFIX = "rbSolM_";		// Used in HTML div IDs to make them unique for this module
	var MOD_PREFIX = "SolarMeter";  // Must match module name above
	var bOnALTUI = false;

	// Forward declaration.
    var myModule = {};

    function onBeforeCpanelClose(args) {
		showBusy(false);
        // do some cleanup...
        console.log(MOD_PREFIX+', handler for before cpanel close');
    }

    function init() {
        // register to events...
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
		if (typeof ALTUI_revision=="string") {
			bOnALTUI = true;
		}
    }
	
	// Return HTML for settings tab
	function Settings() {
		init();
        try {
			var deviceID = api.getCpanelDeviceId();
			var deviceObj = api.getDeviceObject(deviceID);
			var dayInterval = [{'value':'10','label':'10 Seconds'},{'value':'30','label':'30 Seconds'},{'value':'60','label':'1 Minute'},{'value':'120','label':'2 Minutes'},{'value':'300','label':'5 Minutes'},{'value':'600','label':'10 Minutes'},{'value':'900','label':'15 Minutes'}];
			var solarSystem = [{'value':'0','label':'Please select...'},{'value':'1','label':'Enphase Envoy API'},{'value':'2','label':'Enphase Remote API'},{'value':'6','label':'Fronius API V1'},{'value':'4','label':'PV Output'},{'value':'3','label':'Solar Edge'},{'value':'7','label':'Solarman'},{'value':'5','label':'SUNGROW Power'}];
			var yesNo = [{'value':'0','label':'No'},{'value':'1','label':'Yes'}];
			var logLevel = [{'value':'1','label':'Error'},{'value':'2','label':'Warning'},{'value':'8','label':'Info'},{'value':'11','label':'Debug'}];
			var fronDev = [{'value':'0','label':'0'},{'value':'1','label':'1'},{'value':'2','label':'2'},{'value':'3','label':'3'},{'value':'4','label':'4'},{'value':'5','label':'5'},{'value':'6','label':'6'},{'value':'7','label':'7'},{'value':'8','label':'8'},{'value':'9','label':'9'}];
			var html = '<div class="deviceCpanelSettingsPage">'+
				'<h3>Device #'+deviceID+'&nbsp;&nbsp;&nbsp;'+api.getDisplayedDeviceName(deviceID)+'</h3>';
			if (deviceObj.disabled == 1) {
				html += '<br>Plugin is disabled in Attributes.</div>';
			} else {
				var curSystem = varGet(deviceID, 'System');
				html += htmlAddPulldown(deviceID, 'Poll interval', 'DayInterval', dayInterval)+
//				htmlAddPulldown(deviceID, 'Night time poll interval', 'NightInterval', nightInterval)+
				htmlAddPulldown(deviceID, 'Solar System type', 'System', solarSystem)+
				'<div id="'+DIV_PREFIX+deviceID+'div_system1" style="display: '+((curSystem === '1')?'block':'none')+';" >'+
				htmlAddInput(deviceID, 'Envoy IP Address', 50, 'EN_IPAddress')+
				'</div>'+
				'<div id="'+DIV_PREFIX+deviceID+'div_system2" style="display: '+((curSystem === '2')?'block':'none')+';" >'+
				htmlAddInput(deviceID, 'Enphase API Key', 50, 'EN_APIKey')+
				htmlAddInput(deviceID, 'Enphase User ID', 50, 'EN_UserID')+
				htmlAddInput(deviceID, 'Enphase System ID', 50, 'EN_SystemID')+
				'</div>'+
				'<div id="'+DIV_PREFIX+deviceID+'div_system3" style="display: '+((curSystem === '3')?'block':'none')+';" >'+
				htmlAddInput(deviceID, 'Solar Edge API Key', 50, 'SE_APIKey')+
				htmlAddInput(deviceID, 'Solar Edge System ID', 50, 'SE_SystemID')+
				'</div>'+
				'<div id="'+DIV_PREFIX+deviceID+'div_system4" style="display: '+((curSystem === '4')?'block':'none')+';" >'+
				htmlAddInput(deviceID, 'PV Output API Key', 50, 'PV_APIKey')+
				htmlAddInput(deviceID, 'PV Output System ID', 50, 'PV_SystemID')+
				'</div>'+
				'<div id="'+DIV_PREFIX+deviceID+'div_system5" style="display: '+((curSystem === '5')?'block':'none')+';" >'+
				htmlAddInput(deviceID, 'SUNGROW User ID', 50, 'SG_UserID')+
				htmlAddPwdInput(deviceID, 'SUNGROW Password', 50, 'SG_Password')+
				'</div>'+
				'<div id="'+DIV_PREFIX+deviceID+'div_system6" style="display: '+((curSystem === '6')?'block':'none')+';" >'+
				htmlAddInput(deviceID, 'Fronius IP Address', 50, 'FA_IPAddress')+
				htmlAddPulldown(deviceID, 'Fronius Device ID', 'FA_DeviceID', fronDev)+
				htmlAddPulldown(deviceID, 'Show House Power meter', 'ShowHouseChild', yesNo)+
				htmlAddPulldown(deviceID, 'Show Grid Power meters', 'ShowGridChild', yesNo)+
				htmlAddPulldown(deviceID, 'Show Battery Power meters', 'ShowBatteryChild', yesNo)+
				'</div>'+
				'<div id="'+DIV_PREFIX+deviceID+'div_system7" style="display: '+((curSystem === '7')?'block':'none')+';" >'+
				htmlAddInput(deviceID, 'Solarman Device ID', 20, 'SM_DeviceID')+
				htmlAddInput(deviceID, 'Solarman RememberMe Token', 80, 'SM_rememberMe')+
				htmlAddPulldown(deviceID, 'Show House Power meter', 'ShowHouseChild', yesNo)+
				htmlAddPulldown(deviceID, 'Show Grid Power meters', 'ShowGridChild', yesNo)+
				htmlAddPulldown(deviceID, 'Show Battery Power meters', 'ShowBatteryChild', yesNo)+
				'</div>'+
				htmlAddPulldown(deviceID, 'Log level', 'LogLevel', logLevel)+
				htmlAddButton(deviceID, 'UpdateSettings')+
				'</div>'+
				'<script>'+
				' $("#'+DIV_PREFIX+'System'+deviceID+'").change(function() {'+
				'   $("#'+DIV_PREFIX+deviceID+'div_system1").fadeOut(); '+
				'   $("#'+DIV_PREFIX+deviceID+'div_system2").fadeOut(); '+ 
				'   $("#'+DIV_PREFIX+deviceID+'div_system3").fadeOut(); '+
				'   $("#'+DIV_PREFIX+deviceID+'div_system4").fadeOut(); '+
				'   $("#'+DIV_PREFIX+deviceID+'div_system5").fadeOut(); '+
				'   $("#'+DIV_PREFIX+deviceID+'div_system6").fadeOut(); '+
				'   $("#'+DIV_PREFIX+deviceID+'div_system7").fadeOut(); '+
				'   if ($(this).val() == 1) { $("#'+DIV_PREFIX+deviceID+'div_system1").fadeIn(); }; '+
				'   if ($(this).val() == 2) { $("#'+DIV_PREFIX+deviceID+'div_system2").fadeIn(); }; '+
				'   if ($(this).val() == 3) { $("#'+DIV_PREFIX+deviceID+'div_system3").fadeIn(); }; '+
				'   if ($(this).val() == 4) { $("#'+DIV_PREFIX+deviceID+'div_system4").fadeIn(); }; '+
				'   if ($(this).val() == 5) { $("#'+DIV_PREFIX+deviceID+'div_system5").fadeIn(); }; '+
				'   if ($(this).val() == 6) { $("#'+DIV_PREFIX+deviceID+'div_system6").fadeIn(); }; '+
				'   if ($(this).val() == 7) { $("#'+DIV_PREFIX+deviceID+'div_system7").fadeIn(); }; '+
				' } );'+
				'</script>';
			}
			api.setCpanelContent(html);
        } catch (e) {
            Utils.logError('Error in '+MOD_PREFIX+'.Settings(): ' + e);
        }
	}

	// Update variable in user_data and lu_status
	function varSet(deviceID, varID, varVal, sid) {
		if (typeof(sid) == 'undefined') { sid = SM_SID; }
		api.setDeviceStateVariablePersistent(deviceID, sid, varID, varVal);
	}
	// Get variable value. When variable is not defined, this new api returns false not null.
	function varGet(deviceID, varID, sid) {
		try {
			if (typeof(sid) == 'undefined') { sid = SM_SID; }
			var res = api.getDeviceState(deviceID, sid, varID);
			if (res !== false && res !== null && res !== 'null' && typeof(res) !== 'undefined') {
				return res;
			} else {
				return '';
			}	
        } catch (e) {
            return '';
        }
	}
	function UpdateSettings(deviceID) {
		// Save variable values so we can access them in LUA without user needing to save
		showBusy(true);
		varSet(deviceID,'DayInterval',htmlGetPulldownSelection(deviceID, 'DayInterval'));
		varSet(deviceID,'System',htmlGetPulldownSelection(deviceID, 'System'));
		varSet(deviceID,'EN_IPAddress',htmlGetElemVal(deviceID, 'EN_IPAddress'));
		varSet(deviceID,'EN_APIKey',htmlGetElemVal(deviceID, 'EN_APIKey'));
		varSet(deviceID,'EN_UserID',htmlGetElemVal(deviceID, 'EN_UserID'));
		varSet(deviceID,'EN_SystemID',htmlGetElemVal(deviceID, 'EN_SystemID'));
		varSet(deviceID,'PV_APIKey',htmlGetElemVal(deviceID, 'PV_APIKey'));
		varSet(deviceID,'PV_SystemID',htmlGetElemVal(deviceID, 'PV_SystemID'));
		varSet(deviceID,'SE_APIKey',htmlGetElemVal(deviceID, 'SE_APIKey'));
		varSet(deviceID,'SE_SystemID',htmlGetElemVal(deviceID, 'SE_SystemID'));
		varSet(deviceID,'SG_UserID',htmlGetElemVal(deviceID, 'SG_UserID'));
		varSet(deviceID,'SG_Password',htmlGetElemVal(deviceID, 'SG_Password'));
		varSet(deviceID,'FA_IPAddress',htmlGetElemVal(deviceID, 'FA_IPAddress'));
		varSet(deviceID,'FA_DeviceID',htmlGetElemVal(deviceID, 'FA_DeviceID'));
		varSet(deviceID,'SM_rememberMe',htmlGetElemVal(deviceID, 'SM_rememberMe'));
		varSet(deviceID,'SM_DeviceID',htmlGetElemVal(deviceID, 'SM_DeviceID'));
		varSet(deviceID,'LogLevel',htmlGetPulldownSelection(deviceID, 'LogLevel'));
		varSet(deviceID,'ShowHouseChild',htmlGetPulldownSelection(deviceID, 'ShowHouseChild'));
		varSet(deviceID,'ShowGridChild',htmlGetPulldownSelection(deviceID, 'ShowGridChild'));
		varSet(deviceID,'ShowBatteryChild',htmlGetPulldownSelection(deviceID, 'ShowBatteryChild'));
		application.sendCommandSaveUserData(true);
		setTimeout(function() {
			doReload(deviceID);
			showBusy(false);
			try {
				api.ui.showMessagePopup(Utils.getLangString("ui7_device_cpanel_details_saved_success","Device details saved successfully."),0);
			}
			catch (e) {
				Utils.logError(MOD_PREFIX+': UpdateSettings(): ' + e);
			}
		}, 3000);	
	}
	// Standard update for plug-in pull down variable. We can handle multiple selections.
	function htmlGetPulldownSelection(di, vr) {
		var value = $('#'+DIV_PREFIX+vr+di).val() || [];
		return (typeof value === 'object')?value.join():value;
	}
	// Get the value of an HTML input field
	function htmlGetElemVal(di,elID) {
		var res;
		try {
			res=$('#'+DIV_PREFIX+elID+di).val();
		}
		catch (e) {	
			res = '';
		}
		return res;
	}
	// Add a label and pulldown selection
	function htmlAddPulldown(di, lb, vr, values) {
		try {
			var selVal = varGet(di, vr);
			var html = '<div id="'+DIV_PREFIX+vr+di+'_div" class="clearfix labelInputContainer">'+
				'<div class="pull-left inputLabel '+((bOnALTUI) ? 'form-control form-control-sm form-control-plaintext' : '')+'" style="width:280px;">'+lb+'</div>'+
				'<div class="pull-left customSelectBoxContainer">'+
				'<select id="'+DIV_PREFIX+vr+di+'" class="customSelectBox '+((bOnALTUI) ? 'form-control form-control-sm' : '')+'">';
			for(var i=0;i<values.length;i++){
				html += '<option value="'+values[i].value+'" '+((values[i].value==selVal)?'selected':'')+'>'+values[i].label+'</option>';
			}
			html += '</select>'+
				'</div>'+
				'</div>';
			return html;
		} catch (e) {
			Utils.logError(MOD_PREFIX+': htmlAddPulldown(): ' + e);
			return '';
		}
	}
	// Add a standard input for a plug-in variable.
	function htmlAddInput(di, lb, si, vr, sid, df) {
		var val = (typeof df != 'undefined') ? df : varGet(di,vr,sid);
		var html = '<div id="'+DIV_PREFIX+vr+di+'_div" class="clearfix labelInputContainer" >'+
					'<div class="pull-left inputLabel '+((bOnALTUI) ? 'form-control form-control-sm form-control-plaintext' : '')+'" style="width:280px;">'+lb+'</div>'+
					'<div class="pull-left">'+
						'<input class="customInput '+((bOnALTUI) ? 'altui-ui-input form-control form-control-sm' : '')+'" size="'+si+'" id="'+DIV_PREFIX+vr+di+'" type="text" value="'+val+'">'+
					'</div>'+
				'</div>';
		return html;
	}
	// Add a standard input for password a plug-in variable.
	function htmlAddPwdInput(di, lb, si, vr, sid, df) {
		var val = (typeof df != 'undefined') ? df : varGet(di,vr,sid);
		var html = '<div id="'+DIV_PREFIX+vr+di+'_div" class="clearfix labelInputContainer" >'+
					'<div class="pull-left inputLabel '+((bOnALTUI) ? 'form-control form-control-sm form-control-plaintext' : '')+'" style="width:280px;">'+lb+'</div>'+
					'<div class="pull-left">'+
						'<input class="customInput '+((bOnALTUI) ? 'altui-ui-input form-control form-control-sm' : '')+'" size="'+si+'" id="'+DIV_PREFIX+vr+di+'" type="text" value="'+val+'">'+
					'</div>'+
				'</div>';
		html += '<div class="clearfix labelInputContainer '+((bOnALTUI) ? 'form-control form-control-sm form-control-plaintext' : '')+'">'+
					'<div class="pull-left inputLabel" style="width:280px;">&nbsp; </div>'+
					'<div class="pull-left '+((bOnALTUI) ? 'form-check' : '')+'" style="width:200px;">'+
						'<input class="pull-left customCheckbox '+((bOnALTUI) ? 'form-check-input' : '')+'" type="checkbox" id="'+DIV_PREFIX+vr+di+'Checkbox">'+
						'<label class="labelForCustomCheckbox '+((bOnALTUI) ? 'form-check-label' : '')+'" for="'+DIV_PREFIX+vr+di+'Checkbox">Show Password</label>'+
					'</div>'+
				'</div>';
		html += '<script type="text/javascript">'+
					'$("#'+DIV_PREFIX+vr+di+'Checkbox").on("change", function() {'+
					' var typ = (this.checked) ? "text" : "password" ; '+
					' $("#'+DIV_PREFIX+vr+di+'").prop("type", typ);'+
					'});'+
				'</script>';
		return html;
	}
	// Add a Save Settings button
	function htmlAddButton(di, cb) {
		html = '<div class="cpanelSaveBtnContainer labelInputContainer clearfix">'+	
			'<input class="vBtn pull-right btn" type="button" value="Save Changes" onclick="'+MOD_PREFIX+'.'+cb+'(\''+di+'\');"></input>'+
			'</div>';
		return html;
	}

	// Show/hide the interface busy indication.
	function showBusy(busy) {
		if (busy === true) {
			try {
					api.ui.showStartupModalLoading(); // version v1.7.437 and up
				} catch (e) {
					api.ui.startupShowModalLoading(); // Prior versions.
				}
		} else {
			api.ui.hideModalLoading(true);
		}
	}
	function doReload(deviceID) {
		api.performLuActionOnDevice(0, "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", {});
	}

	// Expose interface functions
    myModule = {
		// Internal for panels
        uuid: uuid,
        init: init,
        onBeforeCpanelClose: onBeforeCpanelClose,
		UpdateSettings: UpdateSettings,

		// For JSON calls
        Settings: Settings
    };
    return myModule;
})(api);

