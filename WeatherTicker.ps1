#Requires -Version 5.1

param(
    [switch]$Configure,
    [switch]$OpenLocations
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$script:AppName = "Three-Source Weather Ticker"
$script:AppVersion = "1.0.1"
$script:DataDirectory = Join-Path $env:LOCALAPPDATA "ThreeSourceWeatherTicker"
$script:SettingsPath = Join-Path $script:DataDirectory "settings.json"
$script:SecretsPath = Join-Path $script:DataDirectory "secrets.json"
$script:LocationsPath = Join-Path $script:DataDirectory "locations.csv"
$script:AllowedApiHosts = @(
    "api.weather.gov",
    "api.weather.com",
    "dataservice.accuweather.com"
)
$script:AllowedWebHosts = @(
    "api.weather.gov",
    "forecast.weather.gov",
    "www.weather.gov",
    "weather.gov",
    "radar.weather.gov",
    "www.wunderground.com",
    "wunderground.com",
    "www.accuweather.com",
    "accuweather.com"
)

function New-DefaultSettings {
    return [ordered]@{
        Version                    = 1
        DisplayName                = "Bassfield, MS 39421"
        Latitude                   = 31.4973
        Longitude                  = -89.7425
        Units                      = "imperial"
        RefreshMinutes             = 10
        NwsContact                 = ""
        WuStationId                = ""
        WuPageUrl                  = "https://www.wunderground.com/weather/us/ms/bassfield"
        AccuWeatherLocationKey     = ""
        AccuWeatherPageUrl         = "https://www.accuweather.com/en/us/bassfield/39421/weather-forecast/2159243"
        AlwaysOnTop                = $true
    }
}

function New-DefaultLocation {
    return [pscustomobject][ordered]@{
        Enabled                = "true"
        Name                   = "Bassfield, MS 39421"
        Latitude               = "31.4973"
        Longitude              = "-89.7425"
        ElevationFeet          = ""
        Spotter                = ""
        CallSign               = ""
        WuStationId            = ""
        WuPageUrl              = "https://www.wunderground.com/weather/us/ms/bassfield"
        AccuWeatherLocationKey = ""
        AccuWeatherPageUrl     = "https://www.accuweather.com/en/us/bassfield/39421/weather-forecast/2159243"
    }
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function Get-NestedValue {
    param(
        [object]$Object,
        [string[]]$Path,
        [object]$Default = $null
    )

    $current = $Object
    foreach ($part in $Path) {
        $current = Get-PropertyValue -Object $current -Name $part -Default $null
        if ($null -eq $current) {
            return $Default
        }
    }
    return $current
}

function Get-Settings {
    $defaults = New-DefaultSettings
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return [pscustomobject]$defaults
    }

    try {
        $saved = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) {
            $defaults[$key] = Get-PropertyValue -Object $saved -Name $key -Default $defaults[$key]
        }
        return [pscustomobject]$defaults
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "The saved settings could not be read. Setup will open again.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return [pscustomobject]$defaults
    }
}

function Save-Settings {
    param([object]$Settings)

    if (-not (Test-Path -LiteralPath $script:DataDirectory)) {
        New-Item -ItemType Directory -Path $script:DataDirectory -Force | Out-Null
    }
    $Settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

function Protect-LocalText {
    param([string]$PlainText)

    if ([string]::IsNullOrWhiteSpace($PlainText)) {
        return ""
    }

    $plainBytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $entropy = [Text.Encoding]::UTF8.GetBytes("ThreeSourceWeatherTicker/v1")
    try {
        $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Convert]::ToBase64String($protectedBytes)
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}

function Unprotect-LocalText {
    param([string]$ProtectedText)

    if ([string]::IsNullOrWhiteSpace($ProtectedText)) {
        return ""
    }

    $protectedBytes = [Convert]::FromBase64String($ProtectedText)
    $entropy = [Text.Encoding]::UTF8.GetBytes("ThreeSourceWeatherTicker/v1")
    $plainBytes = $null
    try {
        $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Text.Encoding]::UTF8.GetString($plainBytes)
    }
    finally {
        [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
        if ($null -ne $plainBytes) {
            [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
    }
}

function Get-Secrets {
    $result = [ordered]@{
        WuApiKey          = ""
        AccuWeatherApiKey = ""
    }

    if (-not (Test-Path -LiteralPath $script:SecretsPath)) {
        return [pscustomobject]$result
    }

    try {
        $saved = Get-Content -LiteralPath $script:SecretsPath -Raw | ConvertFrom-Json
        $result.WuApiKey = Unprotect-LocalText (Get-PropertyValue $saved "WuApiKey" "")
        $result.AccuWeatherApiKey = Unprotect-LocalText (Get-PropertyValue $saved "AccuWeatherApiKey" "")
    }
    catch {
        # A DPAPI secret belongs to one Windows user on one PC. If the folder was
        # copied elsewhere, setup simply asks for the keys again.
        $result.WuApiKey = ""
        $result.AccuWeatherApiKey = ""
    }

    return [pscustomobject]$result
}

function Save-Secrets {
    param(
        [string]$WuApiKey,
        [string]$AccuWeatherApiKey
    )

    if (-not (Test-Path -LiteralPath $script:DataDirectory)) {
        New-Item -ItemType Directory -Path $script:DataDirectory -Force | Out-Null
    }

    $protected = [ordered]@{
        WuApiKey          = Protect-LocalText $WuApiKey
        AccuWeatherApiKey = Protect-LocalText $AccuWeatherApiKey
    }
    $protected | ConvertTo-Json | Set-Content -LiteralPath $script:SecretsPath -Encoding UTF8
}

function Ensure-LocationRoster {
    if (-not (Test-Path -LiteralPath $script:DataDirectory)) {
        New-Item -ItemType Directory -Path $script:DataDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $script:LocationsPath) {
        return
    }

    $templatePath = Join-Path $PSScriptRoot "locations-template.csv"
    if (Test-Path -LiteralPath $templatePath) {
        Copy-Item -LiteralPath $templatePath -Destination $script:LocationsPath
        return
    }

    @(New-DefaultLocation) | Export-Csv -LiteralPath $script:LocationsPath -NoTypeInformation -Encoding UTF8
}

function Test-EnabledValue {
    param([object]$Value)
    if ($null -eq $Value) { return $true }
    return @("1", "true", "yes", "y", "on") -contains ([string]$Value).Trim().ToLowerInvariant()
}

function Get-LocationRoster {
    Ensure-LocationRoster
    $locations = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $rows = @(Import-Csv -LiteralPath $script:LocationsPath)
    $rowNumber = 1

    foreach ($row in $rows) {
        $rowNumber += 1
        if (-not (Test-EnabledValue (Get-PropertyValue $row "Enabled" "true"))) {
            continue
        }

        $latitude = 0.0
        $longitude = 0.0
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $style = [Globalization.NumberStyles]::Float
        $latitudeText = [string](Get-PropertyValue $row "Latitude" "")
        $longitudeText = [string](Get-PropertyValue $row "Longitude" "")
        $name = [string](Get-PropertyValue $row "Name" "")

        $validLatitude = [double]::TryParse($latitudeText.Trim(), $style, $culture, [ref]$latitude)
        $validLongitude = [double]::TryParse($longitudeText.Trim(), $style, $culture, [ref]$longitude)
        if (-not $validLatitude -or $latitude -lt -90 -or $latitude -gt 90 -or -not $validLongitude -or $longitude -lt -180 -or $longitude -gt 180) {
            $warnings.Add("Row $rowNumber was skipped because its GPS coordinates are invalid.")
            continue
        }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "GPS $latitudeText,$longitudeText"
        }

        $locations.Add([pscustomobject][ordered]@{
            Name                   = $name.Trim()
            Latitude               = $latitude
            Longitude              = $longitude
            ElevationFeet          = ([string](Get-PropertyValue $row "ElevationFeet" "")).Trim()
            Spotter                = ([string](Get-PropertyValue $row "Spotter" "")).Trim()
            CallSign               = ([string](Get-PropertyValue $row "CallSign" "")).Trim()
            WuStationId            = ([string](Get-PropertyValue $row "WuStationId" "")).Trim().ToUpperInvariant()
            WuPageUrl              = ([string](Get-PropertyValue $row "WuPageUrl" "")).Trim()
            AccuWeatherLocationKey = ([string](Get-PropertyValue $row "AccuWeatherLocationKey" "")).Trim()
            AccuWeatherPageUrl     = ([string](Get-PropertyValue $row "AccuWeatherPageUrl" "")).Trim()
        })
    }

    if ($locations.Count -eq 0) {
        throw "No enabled rows with valid GPS coordinates were found in $($script:LocationsPath)."
    }

    return [pscustomobject]@{
        Locations = $locations.ToArray()
        Warnings  = $warnings.ToArray()
    }
}

function ConvertTo-LocationSettings {
    param(
        [object]$BaseSettings,
        [object]$Location
    )

    $values = New-DefaultSettings
    foreach ($key in @($values.Keys)) {
        $values[$key] = Get-PropertyValue $BaseSettings $key $values[$key]
    }

    $labelDetails = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace([string]$Location.CallSign)) {
        $labelDetails.Add("call $($Location.CallSign)")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Location.Spotter)) {
        $labelDetails.Add("spotter $($Location.Spotter)")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Location.ElevationFeet)) {
        $labelDetails.Add("survey elev $($Location.ElevationFeet) ft")
    }

    $displayName = [string]$Location.Name
    if ($labelDetails.Count -gt 0) {
        $displayName += " (" + ($labelDetails -join "; ") + ")"
    }

    $values.DisplayName = $displayName
    $values.Latitude = [double]$Location.Latitude
    $values.Longitude = [double]$Location.Longitude
    if (-not [string]::IsNullOrWhiteSpace([string]$Location.WuStationId)) {
        $values.WuStationId = [string]$Location.WuStationId
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Location.WuPageUrl)) {
        $values.WuPageUrl = [string]$Location.WuPageUrl
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Location.AccuWeatherLocationKey)) {
        $values.AccuWeatherLocationKey = [string]$Location.AccuWeatherLocationKey
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Location.AccuWeatherPageUrl)) {
        $values.AccuWeatherPageUrl = [string]$Location.AccuWeatherPageUrl
    }
    return [pscustomobject]$values
}

function Open-LocationRoster {
    Ensure-LocationRoster
    Start-Process -FilePath $script:LocationsPath
}

function Test-SourceUrl {
    param(
        [string]$Value,
        [string[]]$AllowedHosts
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) {
        return $false
    }
    return ($uri.Scheme -eq "https" -and $AllowedHosts -contains $uri.DnsSafeHost.ToLowerInvariant())
}

function Show-SettingsDialog {
    param(
        [object]$Settings,
        [object]$Secrets
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$($script:AppName) - Setup"
    $form.StartPosition = "CenterScreen"
    $form.ClientSize = New-Object System.Drawing.Size(650, 690)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Location and sources"
    $title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(22, 18)
    $form.Controls.Add($title)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = "NOAA works without a key. These GPS fields are the fallback location; use Locations CSV in the ticker for the full Excel-editable roster. Optional provider keys add live readings."
    $intro.Location = New-Object System.Drawing.Point(25, 55)
    $intro.Size = New-Object System.Drawing.Size(600, 42)
    $form.Controls.Add($intro)

    $controls = @{}

    function Add-Field {
        param(
            [string]$Key,
            [string]$Label,
            [int]$Y,
            [string]$Value,
            [bool]$Password = $false
        )

        $caption = New-Object System.Windows.Forms.Label
        $caption.Text = $Label
        $caption.Location = New-Object System.Drawing.Point(25, $Y)
        $caption.Size = New-Object System.Drawing.Size(205, 24)
        $form.Controls.Add($caption)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Text = $Value
        $box.Location = New-Object System.Drawing.Point(235, ($Y - 2))
        $box.Size = New-Object System.Drawing.Size(390, 24)
        $box.UseSystemPasswordChar = $Password
        $form.Controls.Add($box)
        $controls[$Key] = $box
    }

    Add-Field "DisplayName" "Fallback location label" 112 ([string]$Settings.DisplayName)
    Add-Field "Latitude" "Fallback latitude" 146 ([string]$Settings.Latitude)
    Add-Field "Longitude" "Fallback longitude" 180 ([string]$Settings.Longitude)

    $unitsLabel = New-Object System.Windows.Forms.Label
    $unitsLabel.Text = "Units"
    $unitsLabel.Location = New-Object System.Drawing.Point(25, 214)
    $unitsLabel.Size = New-Object System.Drawing.Size(205, 24)
    $form.Controls.Add($unitsLabel)

    $units = New-Object System.Windows.Forms.ComboBox
    $units.DropDownStyle = "DropDownList"
    [void]$units.Items.Add("imperial")
    [void]$units.Items.Add("metric")
    $units.SelectedItem = [string]$Settings.Units
    if ($units.SelectedIndex -lt 0) { $units.SelectedIndex = 0 }
    $units.Location = New-Object System.Drawing.Point(235, 212)
    $units.Size = New-Object System.Drawing.Size(150, 24)
    $form.Controls.Add($units)

    Add-Field "RefreshMinutes" "Refresh interval (minutes)" 248 ([string]$Settings.RefreshMinutes)
    Add-Field "NwsContact" "NOAA User-Agent contact (optional)" 282 ([string]$Settings.NwsContact)

    $lineOne = New-Object System.Windows.Forms.Label
    $lineOne.BorderStyle = "Fixed3D"
    $lineOne.Location = New-Object System.Drawing.Point(25, 318)
    $lineOne.Size = New-Object System.Drawing.Size(600, 2)
    $form.Controls.Add($lineOne)

    Add-Field "WuStationId" "WU personal station ID (optional)" 336 ([string]$Settings.WuStationId)
    Add-Field "WuPageUrl" "WU page URL (optional)" 370 ([string]$Settings.WuPageUrl)
    Add-Field "WuApiKey" "WU / Weather Company API key" 404 ([string]$Secrets.WuApiKey) $true

    $lineTwo = New-Object System.Windows.Forms.Label
    $lineTwo.BorderStyle = "Fixed3D"
    $lineTwo.Location = New-Object System.Drawing.Point(25, 440)
    $lineTwo.Size = New-Object System.Drawing.Size(600, 2)
    $form.Controls.Add($lineTwo)

    Add-Field "AccuLocationKey" "AccuWeather location key (optional)" 458 ([string]$Settings.AccuWeatherLocationKey)
    Add-Field "AccuPageUrl" "AccuWeather page URL (optional)" 492 ([string]$Settings.AccuWeatherPageUrl)
    Add-Field "AccuApiKey" "AccuWeather API key" 526 ([string]$Secrets.AccuWeatherApiKey) $true

    $topMost = New-Object System.Windows.Forms.CheckBox
    $topMost.Text = "Keep ticker above other windows"
    $topMost.Checked = [bool]$Settings.AlwaysOnTop
    $topMost.Location = New-Object System.Drawing.Point(235, 562)
    $topMost.Size = New-Object System.Drawing.Size(280, 24)
    $form.Controls.Add($topMost)

    $security = New-Object System.Windows.Forms.Label
    $security.Text = "API keys are encrypted for this Windows account with Windows DPAPI. They are never written into the app folder or displayed in the ticker."
    $security.Location = New-Object System.Drawing.Point(25, 596)
    $security.Size = New-Object System.Drawing.Size(600, 38)
    $security.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($security)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(445, 646)
    $cancel.Size = New-Object System.Drawing.Size(85, 30)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)

    $save = New-Object System.Windows.Forms.Button
    $save.Text = "Save"
    $save.Location = New-Object System.Drawing.Point(540, 646)
    $save.Size = New-Object System.Drawing.Size(85, 30)
    $form.Controls.Add($save)

    $form.AcceptButton = $save
    $form.CancelButton = $cancel

    $save.Add_Click({
        $latitude = 0.0
        $longitude = 0.0
        $refresh = 0
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $style = [Globalization.NumberStyles]::Float

        if (-not [double]::TryParse($controls.Latitude.Text.Trim(), $style, $culture, [ref]$latitude) -or $latitude -lt -90 -or $latitude -gt 90) {
            [System.Windows.Forms.MessageBox]::Show("Enter a latitude from -90 to 90.", $script:AppName, "OK", "Warning") | Out-Null
            return
        }
        if (-not [double]::TryParse($controls.Longitude.Text.Trim(), $style, $culture, [ref]$longitude) -or $longitude -lt -180 -or $longitude -gt 180) {
            [System.Windows.Forms.MessageBox]::Show("Enter a longitude from -180 to 180.", $script:AppName, "OK", "Warning") | Out-Null
            return
        }
        if (-not [int]::TryParse($controls.RefreshMinutes.Text.Trim(), [ref]$refresh) -or $refresh -lt 2 -or $refresh -gt 120) {
            [System.Windows.Forms.MessageBox]::Show("Enter a refresh interval from 2 to 120 minutes.", $script:AppName, "OK", "Warning") | Out-Null
            return
        }
        if (-not (Test-SourceUrl $controls.WuPageUrl.Text.Trim() @("wunderground.com", "www.wunderground.com"))) {
            [System.Windows.Forms.MessageBox]::Show("The Weather Underground page must be a valid https://wunderground.com URL.", $script:AppName, "OK", "Warning") | Out-Null
            return
        }
        if (-not (Test-SourceUrl $controls.AccuPageUrl.Text.Trim() @("accuweather.com", "www.accuweather.com"))) {
            [System.Windows.Forms.MessageBox]::Show("The AccuWeather page must be a valid https://accuweather.com URL.", $script:AppName, "OK", "Warning") | Out-Null
            return
        }

        $newSettings = [pscustomobject][ordered]@{
            Version                    = 1
            DisplayName                = $controls.DisplayName.Text.Trim()
            Latitude                   = $latitude
            Longitude                  = $longitude
            Units                      = [string]$units.SelectedItem
            RefreshMinutes             = $refresh
            NwsContact                 = $controls.NwsContact.Text.Trim()
            WuStationId                = $controls.WuStationId.Text.Trim().ToUpperInvariant()
            WuPageUrl                  = $controls.WuPageUrl.Text.Trim()
            AccuWeatherLocationKey     = $controls.AccuLocationKey.Text.Trim()
            AccuWeatherPageUrl         = $controls.AccuPageUrl.Text.Trim()
            AlwaysOnTop                = $topMost.Checked
        }

        Save-Settings $newSettings
        Save-Secrets $controls.WuApiKey.Text.Trim() $controls.AccuApiKey.Text.Trim()
        $form.Tag = $newSettings
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $form.Tag
    }
    return $null
}

function Assert-AllowedApiUri {
    param([string]$Uri)

    $parsed = [Uri]$Uri
    $hostName = $parsed.DnsSafeHost.ToLowerInvariant()
    if ($parsed.Scheme -ne "https" -or $script:AllowedApiHosts -notcontains $hostName) {
        throw "Blocked non-approved API destination: $hostName"
    }
}

function Invoke-ApprovedJsonRequest {
    param(
        [string]$Uri,
        [hashtable]$Headers = @{},
        [string]$UserAgent = "$($script:AppName)/$($script:AppVersion)"
    )

    Assert-AllowedApiUri $Uri
    return Invoke-RestMethod -Uri $Uri -Method Get -Headers $Headers -UserAgent $UserAgent -TimeoutSec 15
}

function Format-Number {
    param(
        [object]$Value,
        [int]$Decimals = 0,
        [string]$Fallback = "--"
    )

    if ($null -eq $Value) { return $Fallback }
    try {
        return ([double]$Value).ToString("F$Decimals", [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $Fallback
    }
}

function Get-SafeErrorMessage {
    param([object]$ErrorRecord)

    $message = "Unexpected provider error"
    if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception) {
        $message = [string]$ErrorRecord.Exception.Message
    }
    $message = $message -replace '(?i)(apiKey=)[^&\s\"]+', '$1[redacted]'
    $message = $message -replace '(?i)(Authorization:\s*Bearer\s+)[^\s\"]+', '$1[redacted]'
    return $message
}

function Convert-TemperatureFromCelsius {
    param([object]$Value, [string]$Units)
    if ($null -eq $Value) { return $null }
    $number = [double]$Value
    if ($Units -eq "imperial") {
        return (($number * 9.0 / 5.0) + 32.0)
    }
    return $number
}

function Convert-WindFromMetersPerSecond {
    param([object]$Value, [string]$Units)
    if ($null -eq $Value) { return $null }
    $number = [double]$Value
    if ($Units -eq "imperial") {
        return ($number * 2.2369362921)
    }
    return ($number * 3.6)
}

function Convert-PressureFromPascals {
    param([object]$Value, [string]$Units)
    if ($null -eq $Value) { return $null }
    $number = [double]$Value
    if ($Units -eq "imperial") {
        return ($number * 0.000295299830714)
    }
    return ($number / 100.0)
}

function Convert-DegreesToCardinal {
    param([object]$Degrees)
    if ($null -eq $Degrees) { return "VRB" }
    $directions = @("N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW")
    $index = [int][Math]::Floor((([double]$Degrees + 11.25) % 360) / 22.5)
    return $directions[$index]
}

function Get-NoaaSegment {
    param([object]$Settings)

    $lat = ([double]$Settings.Latitude).ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)
    $lon = ([double]$Settings.Longitude).ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)
    $contact = [string]$Settings.NwsContact
    $userAgent = "$($script:AppName)/$($script:AppVersion)"
    if (-not [string]::IsNullOrWhiteSpace($contact)) {
        $userAgent = "$userAgent ($contact)"
    }
    $headers = @{ Accept = "application/geo+json" }

    $point = Invoke-ApprovedJsonRequest "https://api.weather.gov/points/$lat,$lon" $headers $userAgent
    $forecastUrl = [string](Get-NestedValue $point @("properties", "forecast") "")
    $stationsUrl = [string](Get-NestedValue $point @("properties", "observationStations") "")
    if ([string]::IsNullOrWhiteSpace($forecastUrl) -or [string]::IsNullOrWhiteSpace($stationsUrl)) {
        throw "NOAA did not return forecast or observation links for this point."
    }

    $forecastUnits = if ($Settings.Units -eq "metric") { "si" } else { "us" }
    $forecastSeparator = if ($forecastUrl.Contains("?")) { "&" } else { "?" }
    $forecastRequestUrl = "$forecastUrl${forecastSeparator}units=$forecastUnits"
    $forecast = Invoke-ApprovedJsonRequest $forecastRequestUrl $headers $userAgent
    $stations = Invoke-ApprovedJsonRequest $stationsUrl $headers $userAgent
    $stationFeatures = @(Get-PropertyValue $stations "features" @())
    if ($stationFeatures.Count -eq 0) {
        throw "NOAA did not return a nearby observation station."
    }

    $stationIdUrl = [string](Get-PropertyValue $stationFeatures[0] "id" "")
    $observation = Invoke-ApprovedJsonRequest "$stationIdUrl/observations/latest" $headers $userAgent
    $alerts = Invoke-ApprovedJsonRequest "https://api.weather.gov/alerts/active?point=$lat,$lon" $headers $userAgent

    $observationProperties = Get-PropertyValue $observation "properties" $null
    $temperatureC = Get-NestedValue $observationProperties @("temperature", "value") $null
    $dewPointC = Get-NestedValue $observationProperties @("dewpoint", "value") $null
    $humidity = Get-NestedValue $observationProperties @("relativeHumidity", "value") $null
    $windSpeedMps = Get-NestedValue $observationProperties @("windSpeed", "value") $null
    $windGustMps = Get-NestedValue $observationProperties @("windGust", "value") $null
    $windDirection = Get-NestedValue $observationProperties @("windDirection", "value") $null
    $pressurePa = Get-NestedValue $observationProperties @("barometricPressure", "value") $null
    $condition = [string](Get-PropertyValue $observationProperties "textDescription" "Observed conditions unavailable")

    $temperature = Convert-TemperatureFromCelsius $temperatureC $Settings.Units
    $dewPoint = Convert-TemperatureFromCelsius $dewPointC $Settings.Units
    $windSpeed = Convert-WindFromMetersPerSecond $windSpeedMps $Settings.Units
    $windGust = Convert-WindFromMetersPerSecond $windGustMps $Settings.Units
    $pressure = Convert-PressureFromPascals $pressurePa $Settings.Units

    if ($Settings.Units -eq "imperial") {
        $temperatureSuffix = "F"
        $windSuffix = "mph"
        $pressureSuffix = "inHg"
    }
    else {
        $temperatureSuffix = "C"
        $windSuffix = "km/h"
        $pressureSuffix = "hPa"
    }

    $windText = "$(Convert-DegreesToCardinal $windDirection) $(Format-Number $windSpeed 0) $windSuffix"
    if ($null -ne $windGustMps) {
        $windText += " gust $(Format-Number $windGust 0) $windSuffix"
    }

    $periods = @(Get-NestedValue $forecast @("properties", "periods") @())
    $forecastText = "Forecast unavailable"
    if ($periods.Count -gt 0) {
        $period = $periods[0]
        $periodTemperature = Get-PropertyValue $period "temperature" $null
        $periodUnit = [string](Get-PropertyValue $period "temperatureUnit" "")
        if ($null -ne $periodTemperature) {
            if ($Settings.Units -eq "metric" -and $periodUnit -eq "F") {
                $periodTemperature = (([double]$periodTemperature - 32.0) * 5.0 / 9.0)
                $periodUnit = "C"
            }
            elseif ($Settings.Units -eq "imperial" -and $periodUnit -eq "C") {
                $periodTemperature = (([double]$periodTemperature * 9.0 / 5.0) + 32.0)
                $periodUnit = "F"
            }
        }
        $forecastText = "$(Get-PropertyValue $period 'name' 'Next period'): $(Format-Number $periodTemperature 0)$periodUnit, $(Get-PropertyValue $period 'shortForecast' 'forecast unavailable'), wind $(Get-PropertyValue $period 'windSpeed' '--') $(Get-PropertyValue $period 'windDirection' '')"
    }

    $alertFeatures = @(Get-PropertyValue $alerts "features" @())
    if ($alertFeatures.Count -eq 0) {
        $alertText = "No active NWS alerts"
    }
    else {
        $events = @($alertFeatures | ForEach-Object { Get-NestedValue $_ @("properties", "event") "Alert" } | Select-Object -Unique)
        $alertText = "NWS ALERT: $($events -join ', ')"
    }

    $location = [string]$Settings.DisplayName
    if ([string]::IsNullOrWhiteSpace($location)) { $location = "$lat,$lon" }

    return "NOAA/NWS [$location]: $(Format-Number $temperature 1)$temperatureSuffix; dew $(Format-Number $dewPoint 1)$temperatureSuffix; RH $(Format-Number $humidity 0)%; wind $windText; pressure $(Format-Number $pressure 2) $pressureSuffix; $condition; $forecastText; $alertText"
}

function Get-WuSegment {
    param(
        [object]$Settings,
        [object]$Secrets
    )

    $stationId = [string]$Settings.WuStationId
    $apiKey = [string]$Secrets.WuApiKey
    if ([string]::IsNullOrWhiteSpace($stationId) -or [string]::IsNullOrWhiteSpace($apiKey)) {
        return "Weather Underground: add a PWS station ID and API key for live readings; click WU to open the source"
    }

    if ($Settings.Units -eq "imperial") {
        $unitCode = "e"
        $measurementName = "imperial"
        $temperatureSuffix = "F"
        $windSuffix = "mph"
        $pressureSuffix = "inHg"
        $precipRateSuffix = "in/hr"
        $precipTotalSuffix = "in"
    }
    else {
        $unitCode = "m"
        $measurementName = "metric"
        $temperatureSuffix = "C"
        $windSuffix = "km/h"
        $pressureSuffix = "hPa"
        $precipRateSuffix = "mm/hr"
        $precipTotalSuffix = "mm"
    }

    $encodedStation = [Uri]::EscapeDataString($stationId)
    $encodedKey = [Uri]::EscapeDataString($apiKey)
    $uri = "https://api.weather.com/v2/pws/observations/current?stationId=$encodedStation&format=json&units=$unitCode&numericPrecision=decimal&apiKey=$encodedKey"
    $data = Invoke-ApprovedJsonRequest $uri
    $observations = @(Get-PropertyValue $data "observations" @())
    if ($observations.Count -eq 0) {
        throw "Weather Underground returned no recent observation for $stationId."
    }

    $observation = $observations[0]
    $measurement = Get-PropertyValue $observation $measurementName $null
    $temperature = Get-PropertyValue $measurement "temp" $null
    $humidity = Get-PropertyValue $observation "humidity" $null
    $windDirection = Get-PropertyValue $observation "winddir" $null
    $windSpeed = Get-PropertyValue $measurement "windSpeed" $null
    $windGust = Get-PropertyValue $measurement "windGust" $null
    $pressure = Get-PropertyValue $measurement "pressure" $null
    $precipRate = Get-PropertyValue $measurement "precipRate" $null
    $precipTotal = Get-PropertyValue $measurement "precipTotal" $null

    return "Weather Underground PWS [$stationId]: $(Format-Number $temperature 1)$temperatureSuffix; RH $(Format-Number $humidity 0)%; wind $(Convert-DegreesToCardinal $windDirection) $(Format-Number $windSpeed 1) $windSuffix gust $(Format-Number $windGust 1) $windSuffix; pressure $(Format-Number $pressure 2) $pressureSuffix; precip rate $(Format-Number $precipRate 2) $precipRateSuffix; daily precip $(Format-Number $precipTotal 2) $precipTotalSuffix"
}

function Get-AccuWeatherSegment {
    param(
        [object]$Settings,
        [object]$Secrets
    )

    $locationKey = [string]$Settings.AccuWeatherLocationKey
    $apiKey = [string]$Secrets.AccuWeatherApiKey
    if ([string]::IsNullOrWhiteSpace($locationKey) -or [string]::IsNullOrWhiteSpace($apiKey)) {
        return "AccuWeather: add a location key and API key for live readings; click AccuWeather to open the source"
    }

    $encodedLocation = [Uri]::EscapeDataString($locationKey)
    $headers = @{
        Authorization     = "Bearer $apiKey"
        "Accept-Encoding" = "gzip,deflate"
        Accept            = "application/json"
    }
    $uri = "https://dataservice.accuweather.com/currentconditions/v1/{0}?details=true" -f $encodedLocation
    $data = Invoke-ApprovedJsonRequest $uri $headers
    $items = @($data)
    if ($items.Count -eq 0) {
        throw "AccuWeather returned no current condition."
    }
    $current = $items[0]

    if ($Settings.Units -eq "imperial") {
        $unitName = "Imperial"
        $temperatureSuffix = "F"
        $windSuffix = "mph"
        $pressureSuffix = "inHg"
        $precipSuffix = "in"
    }
    else {
        $unitName = "Metric"
        $temperatureSuffix = "C"
        $windSuffix = "km/h"
        $pressureSuffix = "mb"
        $precipSuffix = "mm"
    }

    $condition = [string](Get-PropertyValue $current "WeatherText" "Current conditions")
    $temperature = Get-NestedValue $current @("Temperature", $unitName, "Value") $null
    $realFeel = Get-NestedValue $current @("RealFeelTemperature", $unitName, "Value") $null
    $humidity = Get-PropertyValue $current "RelativeHumidity" $null
    $windDirection = Get-NestedValue $current @("Wind", "Direction", "English") "VRB"
    $windSpeed = Get-NestedValue $current @("Wind", "Speed", $unitName, "Value") $null
    $windGust = Get-NestedValue $current @("WindGust", "Speed", $unitName, "Value") $null
    $pressure = Get-NestedValue $current @("Pressure", $unitName, "Value") $null
    $precip = Get-NestedValue $current @("Precip1hr", $unitName, "Value") $null

    return "AccuWeather: $condition; $(Format-Number $temperature 1)$temperatureSuffix; feels $(Format-Number $realFeel 1)$temperatureSuffix; RH $(Format-Number $humidity 0)%; wind $windDirection $(Format-Number $windSpeed 1) $windSuffix gust $(Format-Number $windGust 1) $windSuffix; pressure $(Format-Number $pressure 2) $pressureSuffix; precip 1h $(Format-Number $precip 2) $precipSuffix"
}

function Get-TickerResult {
    param(
        [object]$Settings,
        [object]$Secrets
    )

    $segments = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]

    $noaaText = ""
    $wuText = ""
    $accuText = ""

    try {
        $noaaText = Get-NoaaSegment $Settings
        $segments.Add($noaaText)
    }
    catch {
        $noaaText = "NOAA/NWS: temporarily unavailable"
        $segments.Add($noaaText)
        $errors.Add("NOAA: $(Get-SafeErrorMessage $_)")
    }

    try {
        $wuText = Get-WuSegment $Settings $Secrets
        $segments.Add($wuText)
    }
    catch {
        $wuText = "Weather Underground: temporarily unavailable; click WU to open the source"
        $segments.Add($wuText)
        $errors.Add("WU: $(Get-SafeErrorMessage $_)")
    }

    try {
        $accuText = Get-AccuWeatherSegment $Settings $Secrets
        $segments.Add($accuText)
    }
    catch {
        $accuText = "AccuWeather: temporarily unavailable; click AccuWeather to open the source"
        $segments.Add($accuText)
        $errors.Add("AccuWeather: $(Get-SafeErrorMessage $_)")
    }

    $status = "Updated $(Get-Date -Format 'h:mm:ss tt')"
    if ($errors.Count -gt 0) {
        $status += " | " + ($errors -join " | ")
    }

    return [pscustomobject]@{
        Text                = ($segments -join "     |     ")
        Status              = $status
        Noaa                = $noaaText
        WeatherUnderground  = $wuText
        AccuWeather         = $accuText
    }
}

function Export-TickerSnapshot {
    param(
        [object]$Result,
        [object]$Location
    )

    if ($null -eq $Result -or $null -eq $Location) {
        throw "Refresh the ticker before exporting a snapshot."
    }

    $documents = [Environment]::GetFolderPath("MyDocuments")
    $exportDirectory = Join-Path $documents "Weather Ticker"
    $exportPath = Join-Path $exportDirectory "weather-snapshots.csv"
    if (-not (Test-Path -LiteralPath $exportDirectory)) {
        New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null
    }

    $row = [pscustomobject][ordered]@{
        TimestampLocal          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
        TimestampUtc            = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")
        Name                    = [string]$Location.Name
        Latitude                = [double]$Location.Latitude
        Longitude               = [double]$Location.Longitude
        SurveyElevationFeet     = [string]$Location.ElevationFeet
        Spotter                 = [string]$Location.Spotter
        CallSign                = [string]$Location.CallSign
        NOAA_NWS                = [string]$Result.Noaa
        WeatherUnderground      = [string]$Result.WeatherUnderground
        AccuWeather             = [string]$Result.AccuWeather
        RefreshStatus           = [string]$Result.Status
    }

    if (Test-Path -LiteralPath $exportPath) {
        $row | Export-Csv -LiteralPath $exportPath -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $row | Export-Csv -LiteralPath $exportPath -NoTypeInformation -Encoding UTF8
    }
    return $exportPath
}

function Get-NoaaWebUrl {
    param([object]$Settings)
    $lat = ([double]$Settings.Latitude).ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)
    $lon = ([double]$Settings.Longitude).ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)
    return "https://forecast.weather.gov/MapClick.php?lat=$lat&lon=$lon"
}

function Get-WuWebUrl {
    param([object]$Settings)
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.WuPageUrl)) {
        return [string]$Settings.WuPageUrl
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.WuStationId)) {
        return "https://www.wunderground.com/dashboard/pws/$([Uri]::EscapeDataString([string]$Settings.WuStationId))"
    }
    return "https://www.wunderground.com/"
}

function Get-AccuWeatherWebUrl {
    param([object]$Settings)
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.AccuWeatherPageUrl)) {
        return [string]$Settings.AccuWeatherPageUrl
    }
    return "https://www.accuweather.com/"
}

function Open-ApprovedWebUrl {
    param([string]$Uri)
    $parsed = [Uri]$Uri
    $hostName = $parsed.DnsSafeHost.ToLowerInvariant()
    if ($parsed.Scheme -ne "https" -or $script:AllowedWebHosts -notcontains $hostName) {
        [System.Windows.Forms.MessageBox]::Show("This link is outside the three approved weather sources and was blocked.", $script:AppName, "OK", "Warning") | Out-Null
        return
    }
    Start-Process $parsed.AbsoluteUri
}

$script:CurrentSettings = Get-Settings
$script:CurrentSecrets = Get-Secrets
Ensure-LocationRoster

if ($OpenLocations) {
    Open-LocationRoster
    exit 0
}

if ($Configure) {
    $updated = Show-SettingsDialog $script:CurrentSettings $script:CurrentSecrets
    if ($null -ne $updated) {
        $script:CurrentSettings = $updated
        $script:CurrentSecrets = Get-Secrets
    }
    exit 0
}

try {
    $initialRoster = Get-LocationRoster
    $script:Locations = @($initialRoster.Locations)
    $script:RosterWarnings = @($initialRoster.Warnings)
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        "$($_.Exception.Message)`r`n`r`nThe Bassfield home preset will be used until the locations CSV is corrected.",
        $script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    $script:Locations = @(New-DefaultLocation)
    $script:RosterWarnings = @()
}

$script:ActiveLocation = $script:Locations[0]
$script:ActiveSettings = ConvertTo-LocationSettings $script:CurrentSettings $script:ActiveLocation
$script:LastTickerResult = $null
$script:LoadingLocations = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(1260, 142)
$form.MinimumSize = New-Object System.Drawing.Size(1150, 180)
$form.BackColor = [System.Drawing.Color]::FromArgb(12, 23, 38)
$form.ForeColor = [System.Drawing.Color]::White
$form.TopMost = [bool]$script:CurrentSettings.AlwaysOnTop
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = "Fill"
$layout.ColumnCount = 1
$layout.RowCount = 3
$layout.Margin = New-Object System.Windows.Forms.Padding(0)
$columnStyle = New-Object System.Windows.Forms.ColumnStyle
$columnStyle.SizeType = [System.Windows.Forms.SizeType]::Percent
$columnStyle.Width = 100
[void]$layout.ColumnStyles.Add($columnStyle)
$tickerRowStyle = New-Object System.Windows.Forms.RowStyle
$tickerRowStyle.SizeType = [System.Windows.Forms.SizeType]::Absolute
$tickerRowStyle.Height = 66
[void]$layout.RowStyles.Add($tickerRowStyle)
$buttonRowStyle = New-Object System.Windows.Forms.RowStyle
$buttonRowStyle.SizeType = [System.Windows.Forms.SizeType]::Absolute
$buttonRowStyle.Height = 42
[void]$layout.RowStyles.Add($buttonRowStyle)
$statusRowStyle = New-Object System.Windows.Forms.RowStyle
$statusRowStyle.SizeType = [System.Windows.Forms.SizeType]::Percent
$statusRowStyle.Height = 100
[void]$layout.RowStyles.Add($statusRowStyle)
$form.Controls.Add($layout)

$tickerPanel = New-Object System.Windows.Forms.Panel
$tickerPanel.Dock = "Fill"
$tickerPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$tickerPanel.BackColor = [System.Drawing.Color]::FromArgb(8, 17, 30)
[void]$layout.Controls.Add($tickerPanel, 0, 0)

$tickerLabel = New-Object System.Windows.Forms.Label
$tickerLabel.AutoSize = $true
$tickerLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
$tickerLabel.ForeColor = [System.Drawing.Color]::FromArgb(98, 210, 255)
$tickerLabel.Text = "Loading the three approved weather sources..."
$tickerLabel.Location = New-Object System.Drawing.Point($tickerPanel.Width, 18)
$tickerPanel.Controls.Add($tickerLabel)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock = "Fill"
$buttonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$buttonPanel.WrapContents = $false
$buttonPanel.Padding = New-Object System.Windows.Forms.Padding(8, 6, 0, 0)
$buttonPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 35, 52)
[void]$layout.Controls.Add($buttonPanel, 0, 1)

function New-ActionButton {
    param([string]$Text, [int]$Width = 105)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 28
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(78, 110, 140)
    $button.BackColor = [System.Drawing.Color]::FromArgb(28, 50, 71)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

$refreshButton = New-ActionButton "Refresh" 75
$locationPicker = New-Object System.Windows.Forms.ComboBox
$locationPicker.DropDownStyle = "DropDownList"
$locationPicker.Width = 215
$locationPicker.Height = 28
$locationPicker.Margin = New-Object System.Windows.Forms.Padding(4, 2, 4, 0)
$noaaButton = New-ActionButton "NOAA" 65
$wuButton = New-ActionButton "WU" 55
$accuButton = New-ActionButton "AccuWeather" 95
$locationsButton = New-ActionButton "My locations" 100
$reloadButton = New-ActionButton "Reload list" 80
$exportButton = New-ActionButton "Save to Excel" 100
$settingsButton = New-ActionButton "Setup" 70
$topButton = New-ActionButton "Always on top" 105
$exitButton = New-ActionButton "Exit" 55

@($refreshButton, $locationPicker, $noaaButton, $wuButton, $accuButton, $locationsButton, $reloadButton, $exportButton, $settingsButton, $topButton, $exitButton) | ForEach-Object {
    [void]$buttonPanel.Controls.Add($_)
}

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = "Fill"
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(10, 7, 10, 0)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(182, 197, 211)
$statusLabel.Text = "Starting..."
$statusLabel.AutoEllipsis = $true
[void]$layout.Controls.Add($statusLabel, 0, 2)

$scrollTimer = New-Object System.Windows.Forms.Timer
$scrollTimer.Interval = 35
$scrollTimer.Add_Tick({
    $tickerLabel.Left -= 2
    if ($tickerLabel.Right -lt 0) {
        $tickerLabel.Left = $tickerPanel.ClientSize.Width
    }
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = ([int]$script:CurrentSettings.RefreshMinutes * 60 * 1000)

function Update-LocationPicker {
    param([string]$PreferredName = "")

    $script:LoadingLocations = $true
    try {
        $locationPicker.Items.Clear()
        foreach ($location in $script:Locations) {
            [void]$locationPicker.Items.Add([string]$location.Name)
        }

        $selectedIndex = 0
        if (-not [string]::IsNullOrWhiteSpace($PreferredName)) {
            for ($i = 0; $i -lt $script:Locations.Count; $i++) {
                if ([string]$script:Locations[$i].Name -eq $PreferredName) {
                    $selectedIndex = $i
                    break
                }
            }
        }
        $locationPicker.SelectedIndex = $selectedIndex
        $script:ActiveLocation = $script:Locations[$selectedIndex]
        $script:ActiveSettings = ConvertTo-LocationSettings $script:CurrentSettings $script:ActiveLocation
    }
    finally {
        $script:LoadingLocations = $false
    }
}

function Reload-LocationRoster {
    $preferredName = ""
    if ($null -ne $script:ActiveLocation) {
        $preferredName = [string]$script:ActiveLocation.Name
    }

    try {
        $roster = Get-LocationRoster
        $script:Locations = @($roster.Locations)
        $script:RosterWarnings = @($roster.Warnings)
        Update-LocationPicker $preferredName
        if ($script:RosterWarnings.Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                (($script:RosterWarnings | Select-Object -First 10) -join "`r`n"),
                "$($script:AppName) - Location roster",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "$($script:AppName) - Location roster",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    return $true
}

function Update-TickerDisplay {
    $refreshTimer.Stop()
    $statusLabel.Text = "Refreshing..."
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $result = Get-TickerResult $script:ActiveSettings $script:CurrentSecrets
        $script:LastTickerResult = $result
        $tickerLabel.Text = $result.Text
        $tickerLabel.Left = $tickerPanel.ClientSize.Width
        $statusLabel.Text = $result.Status
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $refreshTimer.Interval = ([int]$script:CurrentSettings.RefreshMinutes * 60 * 1000)
        $refreshTimer.Start()
    }
}

$refreshTimer.Add_Tick({ Update-TickerDisplay })
$refreshButton.Add_Click({ Update-TickerDisplay })
$locationPicker.Add_SelectedIndexChanged({
    if ($script:LoadingLocations -or $locationPicker.SelectedIndex -lt 0) { return }
    $script:ActiveLocation = $script:Locations[$locationPicker.SelectedIndex]
    $script:ActiveSettings = ConvertTo-LocationSettings $script:CurrentSettings $script:ActiveLocation
    $script:LastTickerResult = $null
    Update-TickerDisplay
})
$noaaButton.Add_Click({ Open-ApprovedWebUrl (Get-NoaaWebUrl $script:ActiveSettings) })
$wuButton.Add_Click({ Open-ApprovedWebUrl (Get-WuWebUrl $script:ActiveSettings) })
$accuButton.Add_Click({ Open-ApprovedWebUrl (Get-AccuWeatherWebUrl $script:ActiveSettings) })
$locationsButton.Add_Click({
    Open-LocationRoster
    $statusLabel.Text = "Your location list is open. Save and close Excel, then click Reload list."
})
$reloadButton.Add_Click({
    if (Reload-LocationRoster) {
        $script:LastTickerResult = $null
        Update-TickerDisplay
    }
})
$exportButton.Add_Click({
    try {
        $exportPath = Export-TickerSnapshot $script:LastTickerResult $script:ActiveLocation
        [System.Windows.Forms.MessageBox]::Show(
            "Saved for Excel:`r`n$exportPath",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, "OK", "Warning") | Out-Null
    }
})
$settingsButton.Add_Click({
    $updated = Show-SettingsDialog $script:CurrentSettings $script:CurrentSecrets
    if ($null -ne $updated) {
        $script:CurrentSettings = $updated
        $script:CurrentSecrets = Get-Secrets
        $script:ActiveSettings = ConvertTo-LocationSettings $script:CurrentSettings $script:ActiveLocation
        $form.TopMost = [bool]$script:CurrentSettings.AlwaysOnTop
        $refreshTimer.Interval = ([int]$script:CurrentSettings.RefreshMinutes * 60 * 1000)
        Update-TickerDisplay
    }
})
$topButton.Add_Click({
    $form.TopMost = -not $form.TopMost
    if ($form.TopMost) { $topButton.Text = "On top: yes" }
    else { $topButton.Text = "On top: no" }
})
$exitButton.Add_Click({ $form.Close() })

if ($form.TopMost) { $topButton.Text = "On top: yes" }
else { $topButton.Text = "On top: no" }

Update-LocationPicker

$form.Add_Shown({
    $scrollTimer.Start()
    if ($script:RosterWarnings.Count -gt 0) {
        $statusLabel.Text = (($script:RosterWarnings | Select-Object -First 3) -join " | ")
    }
    Update-TickerDisplay
})
$form.Add_FormClosed({
    $scrollTimer.Stop()
    $refreshTimer.Stop()
    $scrollTimer.Dispose()
    $refreshTimer.Dispose()
})

[void][System.Windows.Forms.Application]::Run($form)
