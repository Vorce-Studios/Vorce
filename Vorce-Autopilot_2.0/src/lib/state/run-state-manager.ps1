# run-state-manager.ps1
# Manager für hierarchische Zustände (Main, Sub, Part Runs)

function Initialize-RunDirectory {
    param(
        [string]$RunType, # Main, Sub, Part
        [string]$RunName,
        [string]$ParentPath = ""
    )

    $basePath = if ($ParentPath) { $ParentPath } else { Join-Path $PSScriptRoot "../../../var/runtime" }
    $runPath = Join-Path $basePath $RunName

    if (-not (Test-Path $runPath)) {
        New-Item -ItemType Directory -Path $runPath -Force | Out-Null
    }

    return $runPath
}

function New-RunState {
    param(
        [string]$RunType,
        [string]$RunName,
        [string]$RunPath
    )

    $state = @{
        run_id = [guid]::NewGuid().ToString()
        name = $RunName
        type = $RunType
        status = "initialized"
        started_at = (Get-Date).ToString('o')
        completed_at = $null
        errors = @()
        artifacts = @()
        metadata = @{
            run_path = $RunPath
        }
    }

    $stateFile = Join-Path $RunPath "$($RunType.ToUpper())-RUN-STATE.json"
    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile -Encoding UTF8

    return $state
}

function Save-RunState {
    param(
        [object]$State,
        [string]$RunPath
    )

    $stateFile = Join-Path $RunPath "$($State.type.ToUpper())-RUN-STATE.json"
    $State | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile -Encoding UTF8
}

function Add-RunArtifact {
    param(
        [object]$State,
        [string]$ArtifactName,
        [string]$ArtifactPath
    )

    $State.artifacts += @{
        name = $ArtifactName
        path = $ArtifactPath
        timestamp = (Get-Date).ToString('o')
    }
}

function Add-RunError {
    param(
        [object]$State,
        [string]$Message,
        [string]$Context = ""
    )

    $State.errors += @{
        message = $Message
        context = $Context
        timestamp = (Get-Date).ToString('o')
    }
    $State.status = "failed"
}

# Export-ModuleMember -Function Initialize-RunDirectory, New-RunState, Save-RunState, Add-RunArtifact, Add-RunError
