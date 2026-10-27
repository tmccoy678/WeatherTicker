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
    "Get-PropertyValue",
    "Get-NestedValue",
    "Format-Number",
    "Convert-TemperatureFromCelsius",
    "Convert-WindFromMetersPerSecond",
    "Convert-PressureFromPascals",
    "Convert-DegreesToCardinal",
    "Get-NoaaSegment",
    "Get-WuSegment",
    "Get-AccuWeatherSegment"
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

Assert-Equal (Convert-TemperatureFromCelsius 20 "imperial") 68 "Celsius-to-Fahrenheit conversion failed."
Assert-Equal ([Math]::Round((Convert-WindFromMetersPerSecond 10 "metric"), 3)) 36 "Metric wind conversion failed."
Assert-Equal (Convert-DegreesToCardinal 225) "SW" "Cardinal wind conversion failed."

$script:AppName = "Three-Source Weather Ticker"
$script:AppVersion = "1.0.1"
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

$metricSettings = [pscustomobject]@{
    Latitude   = 31.4973
    Longitude  = -89.7425
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
Assert-Equal $script:RequestedUris[1] "https://api.weather.gov/gridpoints/JAN/94,28/forecast?units=si" "Metric NOAA forecasts must request SI measurements."
Assert-Contains $noaaText "wind S 14 km/h gust 25 km/h" "NOAA wind and gust units must stay explicit."
Assert-Contains $noaaText "Tonight: 20C, Clear, wind 16 km/h S" "NOAA forecast wind must use the selected measurement system."

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

Write-Host "WeatherTicker tests passed."
