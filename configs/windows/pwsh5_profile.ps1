# powershell 5 profile

# starship
Invoke-Expression (&starship init powershell)
$ENV:STARSHIP_CONFIG = "$HOME\\.config\\starship\\starship.toml"

# fnm
fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression

# ni
Remove-Item Alias:ni -Force -ErrorAction Ignore
