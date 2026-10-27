#Requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected'; received '$Actual'."
    }
}

function Assert-Contains {
    param(
        [string]$Actual,
        [string]$Expected,
        [string]$Message
    )

    if (-not $Actual.Contains($Expected)) {
        throw "$Message Missing '$Expected' in '$Actual'."
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repositoryRoot "WeatherTicker.ps1"
$firstLine = Get-Content -LiteralPath $sourcePath -TotalCount 1
Assert-Equal $firstLine "#Requires -Version 5.1" "The application must start with a valid PowerShell version directive."

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $sourcePath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    $details = @($parseErrors | ForEach-Object { $_.Message }) -join "; "
    throw "WeatherTicker.ps1 has PowerShell parse errors: $details"
}

$functionNames = @(
    "New-DefaultSettings",
    "Get-PropertyValue",
    "Get-NestedValue",
    "Assert-AllowedApiUri",
    "Invoke-ApprovedJsonRequest",
    "Format-Number",
    "Get-SafeErrorMessage",
    "Convert-TemperatureFromCelsius",
    "Convert-WindFromMetersPerSecond",
    "Convert-PressureFromPascals",
    "Convert-DegreesToCardinal",
    "ConvertTo-LocationSettings",
    "Get-NoaaSegment",
    "Get-WuSegment",
    "Get-AccuWeatherSegment",
    "Get-TickerResult",
    "New-RefreshWorkerScript"
)

foreach ($functionName in $functionNames) {
    $definition = $ast.Find({
        param($node)
        return ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName)
    }, $true)
    if ($null -eq $definition) {
        throw "Required function '$functionName' was not found."
    }
    Invoke-Expression $definition.Extent.Text
}

$workerScript = New-RefreshWorkerScript
$workerTokens = $null
$workerParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput(
    $workerScript,
    [ref]$workerTokens,
    [ref]$workerParseErrors
)
if ($workerParseErrors.Count -gt 0) {
    $details = @($workerParseErrors | ForEach-Object { $_.Message }) -join "; "
    throw "The background refresh worker has PowerShell parse errors: $details"
}

$updateTickerDefinition = $ast.Find({
    param($node)
    return ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Update-TickerDisplay")
}, $true)
if ($null -eq $updateTickerDefinition) {
    throw "Required function 'Update-TickerDisplay' was not found."
}
$updateTickerText = $updateTickerDefinition.Extent.Text
Assert-Contains $updateTickerText "BeginInvoke" "Ticker refreshes must start asynchronously so the window remains responsive."
if ($updateTickerText.Contains("Get-TickerResult")) {
    throw "Update-TickerDisplay must not run provider requests directly on the WinForms UI thread."
}
$sourceText = Get-Content -LiteralPath $sourcePath -Raw
Assert-Contains $sourceText 'RefreshPowerShell.EndInvoke' "The UI thread must collect and apply completed background refresh results."

Assert-Equal (Convert-TemperatureFromCelsius 20 "imperial") 68 "Celsius-to-Fahrenheit conversion failed."
Assert-Equal ([Math]::Round((Convert-WindFromMetersPerSecond 10 "metric"), 3)) 36 "Metric wind conversion failed."
Assert-Equal (Convert-DegreesToCardinal 225) "SW" "Cardinal wind conversion failed."

$baseLocationSettings = [pscustomobject](New-DefaultSettings)
$baseLocationSettings.WuStationId = "KMSBASS1"
$baseLocationSettings.WuPageUrl = "https://www.wunderground.com/dashboard/pws/KMSBASS1"
$baseLocationSettings.AccuWeatherLocationKey = "2159243"
$baseLocationSettings.AccuWeatherPageUrl = "https://www.accuweather.com/en/us/bassfield/39421/weather-forecast/2159243"

$blankProviderLocation = [pscustomobject]@{
    Name = "Prentiss"
    Latitude = 31.5985
    Longitude = -89.8676
    ElevationFeet = ""
    Spotter = ""
    CallSign = ""
    WuStationId = ""
    WuPageUrl = ""
    AccuWeatherLocationKey = ""
    AccuWeatherPageUrl = ""
}
$isolatedLocationSettings = ConvertTo-LocationSettings $baseLocationSettings $blankProviderLocation
Assert-Equal $isolatedLocationSettings.WuStationId "" "A distinct roster location must not inherit the fallback Weather Underground station."
Assert-Equal $isolatedLocationSettings.WuPageUrl "" "A distinct roster location must not inherit the fallback Weather Underground page."
Assert-Equal $isolatedLocationSettings.AccuWeatherLocationKey "" "A distinct roster location must not inherit the fallback AccuWeather key."
Assert-Equal $isolatedLocationSettings.AccuWeatherPageUrl "" "A distinct roster location must not inherit the fallback AccuWeather page."

$fallbackLocation = [pscustomobject]@{
    Name = "Bassfield"
    Latitude = 31.4973
    Longitude = -89.7425
    ElevationFeet = ""
    Spotter = ""
    CallSign = ""
    WuStationId = ""
    WuPageUrl = ""
    AccuWeatherLocationKey = ""
    AccuWeatherPageUrl = ""
}
$fallbackLocationSettings = ConvertTo-LocationSettings $baseLocationSettings $fallbackLocation
Assert-Equal $fallbackLocationSettings.WuStationId "KMSBASS1" "The saved fallback location must retain its Weather Underground station."
Assert-Equal $fallbackLocationSettings.AccuWeatherLocationKey "2159243" "The saved fallback location must retain its AccuWeather key."

$explicitProviderLocation = $blankProviderLocation.PSObject.Copy()
$explicitProviderLocation.WuStationId = "KMSPREN1"
$explicitProviderLocation.WuPageUrl = "https://www.wunderground.com/dashboard/pws/KMSPREN1"
$explicitProviderLocation.AccuWeatherLocationKey = "999999"
$explicitProviderLocation.AccuWeatherPageUrl = "https://www.accuweather.com/en/us/prentiss/39474/weather-forecast/999999"
$explicitLocationSettings = ConvertTo-LocationSettings $baseLocationSettings $explicitProviderLocation
Assert-Equal $explicitLocationSettings.WuStationId "KMSPREN1" "An explicit roster Weather Underground station must be used."
Assert-Equal $explicitLocationSettings.AccuWeatherLocationKey "999999" "An explicit roster AccuWeather key must be used."

$script:AppName = "Three-Source Weather Ticker"
$script:AppVersion = "test"
$script:RequestedUris = New-Object System.Collections.Generic.List[string]
$script:Responses = New-Object System.Collections.Generic.Queue[object]

function Invoke-ApprovedJsonRequest {
    param(
        [string]$Uri,
        [hashtable]$Headers = @{},
        [string]$UserAgent = "test"
    )

    [void]$script:RequestedUris.Add($Uri)
    if ($script:Responses.Count -eq 0) {
        throw "The test response queue is empty for $Uri."
    }
    return $script:Responses.Dequeue()
}

$runspaceWorker = [System.Management.Automation.PowerShell]::Create()
[void]$runspaceWorker.AddScript((New-RefreshWorkerScript))
[void]$runspaceWorker.AddArgument([pscustomobject]@{
    Latitude = 31.4973
    Longitude = -89.7425
    NwsContact = ""
    Units = "imperial"
    DisplayName = "Runspace test"
    WuStationId = ""
    AccuWeatherLocationKey = ""
})
[void]$runspaceWorker.AddArgument([pscustomobject]@{
    WuApiKey = ""
    AccuWeatherApiKey = ""
})
[void]$runspaceWorker.AddArgument($script:AppName)
[void]$runspaceWorker.AddArgument($script:AppVersion)
[void]$runspaceWorker.AddArgument([string[]]@("api.weather.gov", "api.weather.com", "dataservice.accuweather.com"))
$runspaceHandle = $runspaceWorker.BeginInvoke()
try {
    if (-not $runspaceHandle.AsyncWaitHandle.WaitOne(5000)) {
        [void]$runspaceWorker.BeginStop($null, $null)
        throw "The background refresh worker did not complete within five seconds."
    }
    $runspaceOutput = @($runspaceWorker.EndInvoke($runspaceHandle))
    Assert-Equal $runspaceOutput.Count 1 "The background refresh worker must return one ticker result."
    Assert-Contains ([string]$runspaceOutput[0].Text) "NOAA/NWS: temporarily unavailable" "The background refresh worker must return a provider-safe result when a request fails."
}
finally {
    $runspaceWorker.Dispose()
}

$metricSettings = [pscustomobject]@{
    Latitude   = 31.497345
    Longitude  = -89.742512
    NwsContact = ""
    Units      = "metric"
    DisplayName = "Metric test"
}

$script:Responses.Enqueue([pscustomobject]@{
    properties = [pscustomobject]@{
        forecast = "https://api.weather.gov/gridpoints/JAN/94,28/forecast"
        observationStations = "https://api.weather.gov/gridpoints/JAN/94,28/stations"
    }
})
$script:Responses.Enqueue([pscustomobject]@{
    properties = [pscustomobject]@{
        periods = @([pscustomobject]@{
            name = "Tonight"
            temperature = 20
            temperatureUnit = "C"
            shortForecast = "Clear"
            windSpeed = "16 km/h"
            windDirection = "S"
        })
    }
})
$script:Responses.Enqueue([pscustomobject]@{
    features = @([pscustomobject]@{ id = "https://api.weather.gov/stations/KLUL" })
})
$script:Responses.Enqueue([pscustomobject]@{
    properties = [pscustomobject]@{
        temperature = [pscustomobject]@{ value = 20 }
        dewpoint = [pscustomobject]@{ value = 10 }
        relativeHumidity = [pscustomobject]@{ value = 50 }
        windSpeed = [pscustomobject]@{ value = 4 }
        windGust = [pscustomobject]@{ value = 7 }
        windDirection = [pscustomobject]@{ value = 180 }
        barometricPressure = [pscustomobject]@{ value = 101325 }
        textDescription = "Clear"
    }
})
$script:Responses.Enqueue([pscustomobject]@{ features = @() })

$noaaText = Get-NoaaSegment $metricSettings
Assert-Equal $script:RequestedUris[0] "https://api.weather.gov/points/31.4973,-89.7425" "NOAA point requests must use no more than four decimal places."
Assert-Equal $script:RequestedUris[1] "https://api.weather.gov/gridpoints/JAN/94,28/forecast?units=si" "Metric NOAA forecasts must request SI measurements."
Assert-Equal $script:RequestedUris[4] "https://api.weather.gov/alerts/active?point=31.4973,-89.7425" "NOAA alert requests must use no more than four decimal places."
Assert-Contains $noaaText "wind S 14 km/h gust 25 km/h" "NOAA wind and gust units must stay explicit."
Assert-Contains $noaaText "Tonight: 20C, Clear, wind 16 km/h S" "NOAA forecast wind must use the selected measurement system."

$script:RequestedUris.Clear()
$script:Responses.Clear()
$imperialSettings = [pscustomobject]@{
    Latitude = 31.497345
    Longitude = -89.742512
    NwsContact = ""
    Units = "imperial"
    DisplayName = "Imperial test"
}
$script:Responses.Enqueue([pscustomobject]@{
    properties = [pscustomobject]@{
        forecast = "https://api.weather.gov/gridpoints/JAN/94,28/forecast"
        observationStations = "https://api.weather.gov/gridpoints/JAN/94,28/stations"
    }
})
$script:Responses.Enqueue([pscustomobject]@{
    properties = [pscustomobject]@{
        periods = @([pscustomobject]@{
            name = "Tonight"
            temperature = 68
            temperatureUnit = "F"
            shortForecast = "Clear"
            windSpeed = "10 mph"
            windDirection = "S"
        })
    }
})
$script:Responses.Enqueue([pscustomobject]@{
    features = @([pscustomobject]@{ id = "https://api.weather.gov/stations/KLUL" })
})
$script:Responses.Enqueue([pscustomobject]@{
    properties = [pscustomobject]@{
        temperature = [pscustomobject]@{ value = 20 }
        dewpoint = [pscustomobject]@{ value = 10 }
        relativeHumidity = [pscustomobject]@{ value = 50 }
        windSpeed = [pscustomobject]@{ value = 4 }
        windGust = [pscustomobject]@{ value = 7 }
        windDirection = [pscustomobject]@{ value = 180 }
        barometricPressure = [pscustomobject]@{ value = 101325 }
        textDescription = "Clear"
    }
})
$script:Responses.Enqueue([pscustomobject]@{ features = @() })

$imperialNoaaText = Get-NoaaSegment $imperialSettings
Assert-Equal $script:RequestedUris[1] "https://api.weather.gov/gridpoints/JAN/94,28/forecast?units=us" "Imperial NOAA forecasts must request US customary measurements."
Assert-Contains $imperialNoaaText "wind S 9 mph gust 16 mph" "Imperial NOAA wind and gust units must stay explicit."
Assert-Contains $imperialNoaaText "Tonight: 68F, Clear, wind 10 mph S" "Imperial NOAA forecast wind must use the selected measurement system."

$script:RequestedUris.Clear()
$script:Responses.Clear()
$script:Responses.Enqueue([pscustomobject]@{
    observations = @([pscustomobject]@{
        humidity = 55
        winddir = 180
        metric = [pscustomobject]@{
            temp = 20
            windSpeed = 10
            windGust = 20
            pressure = 1013.25
            precipRate = 2.5
            precipTotal = 5
        }
    })
})
$wuText = Get-WuSegment ([pscustomobject]@{ Units = "metric"; WuStationId = "KTEST1" }) ([pscustomobject]@{ WuApiKey = "test-key" })
Assert-Contains $wuText "wind S 10.0 km/h gust 20.0 km/h" "Weather Underground gust units must stay explicit."
Assert-Contains $wuText "precip rate 2.50 mm/hr; daily precip 5.00 mm" "Weather Underground rate and total measurements must use distinct units."

$script:RequestedUris.Clear()
$script:Responses.Clear()
$script:Responses.Enqueue([pscustomobject]@{
    observations = @([pscustomobject]@{
        humidity = 55
        winddir = 180
        imperial = [pscustomobject]@{
            temp = 68
            windSpeed = 6.2
            windGust = 12.4
            pressure = 29.92
            precipRate = 0.10
            precipTotal = 0.20
        }
    })
})
$imperialWuText = Get-WuSegment ([pscustomobject]@{ Units = "imperial"; WuStationId = "KTEST1" }) ([pscustomobject]@{ WuApiKey = "test-key" })
Assert-Contains $script:RequestedUris[0] "units=e" "Imperial Weather Underground requests must use English units."
Assert-Contains $imperialWuText "wind S 6.2 mph gust 12.4 mph" "Imperial Weather Underground gust units must stay explicit."
Assert-Contains $imperialWuText "precip rate 0.10 in/hr; daily precip 0.20 in" "Imperial Weather Underground rate and total measurements must use distinct units."

$script:RequestedUris.Clear()
$script:Responses.Clear()
$script:Responses.Enqueue([pscustomobject]@{
    WeatherText = "Clear"
    Temperature = [pscustomobject]@{ Metric = [pscustomobject]@{ Value = 20 } }
    RealFeelTemperature = [pscustomobject]@{ Metric = [pscustomobject]@{ Value = 19 } }
    RelativeHumidity = 55
    Wind = [pscustomobject]@{
        Direction = [pscustomobject]@{ English = "NW" }
        Speed = [pscustomobject]@{ Metric = [pscustomobject]@{ Value = 10 } }
    }
    WindGust = [pscustomobject]@{ Speed = [pscustomobject]@{ Metric = [pscustomobject]@{ Value = 20 } } }
    Pressure = [pscustomobject]@{ Metric = [pscustomobject]@{ Value = 1013.25 } }
    Precip1hr = [pscustomobject]@{ Metric = [pscustomobject]@{ Value = 2.5 } }
})
$accuText = Get-AccuWeatherSegment ([pscustomobject]@{ Units = "metric"; AccuWeatherLocationKey = "TEST" }) ([pscustomobject]@{ AccuWeatherApiKey = "test-key" })
Assert-Contains $accuText "wind NW 10.0 km/h gust 20.0 km/h" "AccuWeather gust units must stay explicit."

$script:RequestedUris.Clear()
$script:Responses.Clear()
$script:Responses.Enqueue([pscustomobject]@{
    WeatherText = "Clear"
    Temperature = [pscustomobject]@{ Imperial = [pscustomobject]@{ Value = 68 } }
    RealFeelTemperature = [pscustomobject]@{ Imperial = [pscustomobject]@{ Value = 66 } }
    RelativeHumidity = 55
    Wind = [pscustomobject]@{
        Direction = [pscustomobject]@{ English = "NW" }
        Speed = [pscustomobject]@{ Imperial = [pscustomobject]@{ Value = 6.2 } }
    }
    WindGust = [pscustomobject]@{ Speed = [pscustomobject]@{ Imperial = [pscustomobject]@{ Value = 12.4 } } }
    Pressure = [pscustomobject]@{ Imperial = [pscustomobject]@{ Value = 29.92 } }
    Precip1hr = [pscustomobject]@{ Imperial = [pscustomobject]@{ Value = 0.10 } }
})
$imperialAccuText = Get-AccuWeatherSegment ([pscustomobject]@{ Units = "imperial"; AccuWeatherLocationKey = "TEST" }) ([pscustomobject]@{ AccuWeatherApiKey = "test-key" })
Assert-Contains $imperialAccuText "wind NW 6.2 mph gust 12.4 mph" "Imperial AccuWeather gust units must stay explicit."
Assert-Contains $imperialAccuText "precip 1h 0.10 in" "Imperial AccuWeather precipitation units must stay explicit."

Write-Host "WeatherTicker tests passed."
