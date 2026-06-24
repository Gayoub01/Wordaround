# Browser Cache Detection Script
# Detects if Chrome + Edge cache exceeds 5 GB
# Exit 1 = Detected (over threshold) | Exit 0 = Compliant

$ThresholdGB = 5
$Results = @()

$Browsers = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
}

foreach ($Browser in $Browsers.GetEnumerator()) {
    if (Test-Path $Browser.Value) {
        $SizeBytes = (Get-ChildItem -Path $Browser.Value -Recurse -Force -EA SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
        $SizeGB = [math]::Round($SizeBytes / 1GB, 2)
        $Results += [PSCustomObject]@{
            Browser = $Browser.Key
            SizeGB  = $SizeGB
        }
    }
}

$TotalGB = ($Results | Measure-Object -Property SizeGB -Sum).Sum
$TotalGB = [math]::Round($TotalGB, 2)

if ($TotalGB -gt $ThresholdGB) {
    Write-Output "DETECTED: $env:USERNAME has ${TotalGB} GB of browser cache (Threshold: ${ThresholdGB} GB)"
    foreach ($r in $Results) {
        Write-Output "  - $($r.Browser): $($r.SizeGB) GB"
    }
    Exit 1
}

Write-Output "Compliant: ${TotalGB} GB total cache (Threshold: ${ThresholdGB} GB)"
Exit 0