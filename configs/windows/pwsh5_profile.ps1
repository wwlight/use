# powershell 5 profile

# starship
Invoke-Expression (&starship init powershell)
$ENV:STARSHIP_CONFIG = "$HOME\\.config\\starship\\starship.toml"

# ni
Remove-Item Alias:ni -Force -ErrorAction Ignore
