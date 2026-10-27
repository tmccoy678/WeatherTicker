THREE-SOURCE WEATHER TICKER
===========================

Purpose
-------
A small personal Windows desktop ticker that is restricted to three weather
sources:

  1. NOAA / National Weather Service
  2. Weather Underground personal weather stations
  3. AccuWeather

It has no advertising, analytics, telemetry, or background service. It runs
only while its window is open.

Install
-------
1. Open "Weather-Ticker-One-Click-Installer.zip".
2. Double-click "1 - DOUBLE-CLICK TO INSTALL WEATHER TICKER.cmd". The installer
   is self-contained and can run directly from the ZIP. If Windows refuses,
   choose Extract All and double-click it from the extracted folder.
3. Windows will place a "Weather Ticker" shortcut on the Desktop and open the
   ticker immediately. Administrator access is not required.
4. Bassfield, Mississippi 39421 is already installed as the home preset using
   the NWS point at 31.4973, -89.7425. Setup can change the fallback location.

Re-running the installer updates the program while preserving saved settings,
the location/spotter roster, and optional API keys.

If Windows asks whether you want to run the file, confirm only if this folder
came directly from Taylor. No administrator permission is required.

Provider access
---------------
NOAA works immediately and does not require an API key.

Weather Underground live PWS readings require BOTH:
  - a Weather Underground personal weather station ID; and
  - a Weather Company API key that is authorized for PWS observations.

AccuWeather live readings require BOTH:
  - an AccuWeather location key; and
  - an AccuWeather developer API key.

Without those optional credentials, the WU and AccuWeather buttons still open
their official sites. The app does not scrape either website.

Privacy and network boundary
----------------------------
The programmatic network allowlist contains only:
  - api.weather.gov
  - api.weather.com
  - dataservice.accuweather.com

The clickable source buttons are restricted to official NOAA/NWS,
Weather Underground, and AccuWeather HTTPS hosts.

Settings and encrypted API keys are stored under:
  %LOCALAPPDATA%\ThreeSourceWeatherTicker

API keys are protected with Windows Data Protection API (DPAPI) for the
current Windows user and computer. They are not stored in this app folder.

Use
---
- Refresh: request fresh data now.
- Location list: choose one enabled GPS point. Only the selected point is
  refreshed, which avoids hammering provider APIs even with 43 spotters.
- NOAA, Weather Underground, AccuWeather: open the official source page.
- My locations: open the roster in Excel. Save and close Excel, then click
  Reload list in the ticker.
- Reload list: validate the roster and reload enabled locations.
- Save to Excel: append the visible, source-labeled snapshot to
  Documents\Weather Ticker\weather-snapshots.csv for Excel.
- Setup: change the location, update interval, links, station, or keys.
- On top: toggle whether the ticker stays above other windows.
- Exit: close the ticker. It does not continue running after Exit.

The automatic refresh interval can be set from 2 to 120 minutes. Ten minutes
is a considerate default for personal use.

GPS, elevations, and spotters
-----------------------------
The local roster is:
  %LOCALAPPDATA%\ThreeSourceWeatherTicker\locations.csv

It supports any practical number of rows, including a 43-person spotter
roster. The columns are:

  Enabled
  Name
  Latitude
  Longitude
  ElevationFeet
  Spotter
  CallSign
  WuStationId
  WuPageUrl
  AccuWeatherLocationKey
  AccuWeatherPageUrl

Use decimal GPS coordinates. The roster and exported snapshots retain the
coordinates you enter. NOAA API requests use up to four decimal places, as
required by the NWS API. ElevationFeet is locally supplied survey metadata;
the app labels it as "survey elev" and never presents it as a provider
measurement or uses it to alter official observations.

Each distinct GPS row owns its optional Weather Underground and AccuWeather
fields. Leave those fields blank to keep the row unlinked; the ticker shows
that provider's setup prompt. The row matching the Setup fallback coordinates
can use the provider identifiers saved in Setup.

Use the source-labeled ticker for situational awareness. Receive warnings
through NWS and local emergency-alert channels, and use established local
channels for spotter communication. NWS alerts remain visibly identified as
NWS alerts.

Move to another PC
------------------
Copy the original folder and run the installer on the other PC. API keys must
be entered again because DPAPI-encrypted values do not transfer between Windows
users or computers.

Support note
------------
This version targets Windows PowerShell 5.1 on Windows 10 or Windows 11. It
does not require Python, Node.js, a browser extension, or administrator access.

License
-------
MIT. See LICENSE in the installed application folder.
