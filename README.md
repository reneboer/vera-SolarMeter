# vera-SolarMeter
Plugin to read solar production data supporting several Solar systems.

Supports:
- Enphase Envoy local API
- Enphase Cloud API
- Fronius JSON API V1
- Solar Edge Cloud API
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
  The device ID between 0 and 9.  to check you can enter the URL http://[Fronius Local IP address]/solar_api/v1/GetInverterRealtimeData.cgi?Scope=System and see what is listed behind Values. If you see multiple you should have multiple converters and you need to install a copy of the plugin for each.

- Solar Edge Cloud API<br>
  API Key and System ID.
  
- SUNGROW Power Cloud API<br>
  User ID and password.
  
- PV Output Cloud API<br>
  API Key and System ID. Found in your PV Output Account settings.

You can install multiple instances of this plugin if you have multiple systems to monitor.

Anyone that has an other system feel free to contact me to have it added.
