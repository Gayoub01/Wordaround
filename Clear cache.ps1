# Clear Chrome Cache (all profiles)
Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data" -Directory |
    ForEach-Object { Remove-Item "$($_.FullName)\Cache\*" -Recurse -Force -EA SilentlyContinue }

# Clear Edge Cache (all profiles)
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data" -Directory |
    ForEach-Object { Remove-Item "$($_.FullName)\Cache\*" -Recurse -Force -EA SilentlyContinue }