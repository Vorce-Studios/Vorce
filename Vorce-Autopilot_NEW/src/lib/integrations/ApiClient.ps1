# ApiClient.ps1 (Vorce 3.0)
# Modularer REST-Client für externe Dienste (GitHub, Jules)

function Invoke-VorceApiRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = "GET",
        [object]$Body = $null,
        [hashtable]$Headers = @{}
    )
    
    $params = @{
        Uri = $Uri
        Method = $Method
        ContentType = "application/json"
        ErrorAction = "Stop"
    }
    
    if ($Body) { $params["Body"] = $Body | ConvertTo-Json -Depth 10 }
    if ($Headers) { $params["Headers"] = $Headers }
    
    try {
        return Invoke-RestMethod @params
    } catch {
        Write-Error "API Request failed: $($_.Exception.Message)"
        throw $_
    }
}

# Keine Export-ModuleMember nötig — diese Datei wird per Dot-Sourcing (.) geladen.
