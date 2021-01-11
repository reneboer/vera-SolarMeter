# vera-SolarMeter
Plugin to read solar production data supporting several Solar systems.

As of version 1.7 the weekly, last 7 days, monthly total and/or year total values will be calculated if the converter does not supply them. Note it does this by summing the daily values or monthly, so it will take 7 days to build the weekly, monthly will be correct after the first new month and yearly from January on.

Supports:
- Enphase Envoy local API
- Enphase Cloud API
- Fronius JSON API V1
- Solar Edge Cloud API
- SolarMan Cloud API (thanks to Octoplayer)
- SUNGROW Power Cloud API
- PV Output Cloud API

In the Settings select the system you want to monitor. It will open up the parameters required for the specific API.
Parameters needed are:
- Enphase Envoy local API<br>
  The Envoy local IP address.

- Enphase Cloud API<br>
  API Key, System ID and User ID. You must generate your own API key by regestering for the Free plan. The instructions are at https://developer.enphase.com/docs/quickstart.html. The System IS and USer ID you can find in your Enphase Account settings under the API Access section.
  
- Fronius JSON API V1 API<br>
  The Fronius local IP address.
  The device ID between 1 and 9.  To check you can enter the URL http://[Fronius Local IP address]/solar_api/v1/GetInverterRealtimeData.cgi?Scope=System and see what is listed behind Values. If you see multiple you should have multiple converters and you need to install a copy of the plugin for each. If you have multiple inverters on a site and you want to report at site level, select device ID 0.

- Solar Edge Cloud API<br>
  API Key and System ID.
  
- SolarMan Cloud API<br>
  Device ID and 'remember me' value. To get these values, logon to the solarman portal. Nesxt follow these steps:
  - Log into the Solarman home.solarman.cn portal, I used Chrome, other browsers may do this differently... 
  - Select the Details Tab and then select the Logger. On the Dev panel select the Network tab
  - Press F5 or ctrl + R to refresh the page
  - On the left of the panel should appear the 'goDetailAjax' set.
  - Lookup and copy the deviceID and rememberMe values.
  
- SUNGROW Power Cloud API<br>
  User ID and password.
  
- PV Output Cloud API<br>
  API Key and System ID. Found in your PV Output Account settings.

You can install multiple instances of this plugin if you have multiple systems to monitor.

Anyone that has an other system feel free to contact me to have it added.
