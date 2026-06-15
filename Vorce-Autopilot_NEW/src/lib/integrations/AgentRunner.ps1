# AgentRunner.ps1 (Vorce 3.0)
# Führt KI-Agenten CLI Befehle aus und fängt deren Output ab

function Invoke-VorceAgent {
    param(
        [Parameter(Mandatory)][string]$AgentName, # gemini_cli, claude_code, etc.
        [Parameter(Mandatory)][string]$Prompt,
        [string]$ModelTier = "default",
        [string]$WorkingDirectory = $null
    )

    Write-VorceStep -Message "Rufe KI-Agent auf: $AgentName ($ModelTier)..." -Status "RUN"

    # Prüfe ob Debug-Modus aktiv ist
    $debugMode = if ($global:debugMode -ne $null) { $global:debugMode } else { $false }

    # In V3.0 nutzen wir temporäre Dateien für den Austausch
    $tmpDir = Join-Path $global:VarDir "tmp"
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

    $timestamp = Get-Date -Format "HHmmss"
    $outputFile = Join-Path $tmpDir "output_$timestamp.txt"
    $errorFile = Join-Path $tmpDir "error_$timestamp.txt" # New error file
    $promptInputFile = $null # Initialize
    $process = $null # Initialize

    try {
        $shellCommand = ""
        $agentArgs = @()

        if ($AgentName -eq "gemini_cli") {
            $geminiPs1Path = (Get-Command gemini.ps1).Source
            if (-not $geminiPs1Path) {
                throw "gemini.ps1 nicht gefunden. Ist die Gemini CLI korrekt installiert und im PATH?"
            }
            $pwshPath = (Get-Command pwsh.exe).Source
            if (-not $pwshPath) {
                throw "pwsh.exe nicht gefunden. Ist PowerShell Core korrekt installiert und im PATH?"
            }
            $shellCommand = $pwshPath
            $agentArgs += @("-NoProfile", "-File", $geminiPs1Path)
            $agentArgs += @("--yolo") # Auto-accept all actions for autonomous mode

            $promptInputFile = Join-Path $tmpDir "prompt_input_$timestamp.txt"
            Set-Content -Path $promptInputFile -Value $Prompt -Encoding UTF8

            Write-VorceStep -Message "Agent gestartet. Warte auf Antwort von '$shellCommand' mit Argumenten '$($agentArgs -join ' ')' (Output in '$outputFile', Error in '$errorFile', Input from '$promptInputFile')..." -Status "INFO"
            if ($debugMode) {
                Write-VorceStep -Message "DEBUG: Start-Process FilePath: '$shellCommand'" -Status "INFO"
                Write-VorceStep -Message "DEBUG: Start-Process ArgumentList: '$($agentArgs -join ' ')'" -Status "INFO"
            }

            $process = Start-Process -FilePath $shellCommand -ArgumentList $agentArgs -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile -RedirectStandardInput $promptInputFile -NoNewWindow -Wait -PassThru
        } elseif ($AgentName -eq "claude_code") {
            $shellCommand = "claude.cmd"
            $agentArgs += @("--prompt", $Prompt)

            Write-VorceStep -Message "Agent gestartet. Warte auf Antwort von '$shellCommand' mit Argumenten '$($agentArgs -join ' ')' (Output in '$outputFile', Error in '$errorFile')..." -Status "INFO"

            $process = Start-Process -FilePath $shellCommand -ArgumentList $agentArgs -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile -NoNewWindow -Wait -PassThru
        } else {
            throw "Unbekannter Agent: $AgentName"
        }

        # Check if process actually started
        if ($null -eq $process) {
            Write-VorceStep -Message "Fehler: Start-Process konnte nicht initialisiert werden." -Status "ERROR"
            return $null
        }

        # Read both output and error streams
        $stdOutContent = if (Test-Path -LiteralPath $outputFile) { Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8 } else { "" }
        $stdErrContent = if (Test-Path -LiteralPath $errorFile) { Get-Content -LiteralPath $errorFile -Raw -Encoding UTF8 } else { "" }

        # Combine them for the final output
        $output = ($stdOutContent, $stdErrContent | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"

        if ($process.ExitCode -ne 0) {
            Write-VorceStep -Message "Agent $AgentName fehlgeschlagen (Exit: $($process.ExitCode)). Output: $($output | Select-Object -First 200)" -Status "ERROR"
            return $null
        }

        if (-not [string]::IsNullOrWhiteSpace($output)) {
            if ($debugMode) {
                Write-VorceStep -Message "DEBUG: Raw Agent Output Start >>>" -Status "INFO"
                Write-Host $output
                Write-VorceStep -Message "DEBUG: Raw Agent Output End <<<" -Status "INFO"
            } else {
                Write-Host $output
            }
        }

        if ([string]::IsNullOrWhiteSpace($output)) {
            Write-VorceStep -Message "Agent '$AgentName' hat keine Antwort geliefert. Output-Datei leer." -Status "WARN"
            return $null
        }

        Write-VorceStep -Message "Antwort erhalten ($($output.Length) Zeichen)." -Status "OK"
        Write-VorceStep -Message "Agent Output (First 200 chars): $($output.Substring(0, [System.Math]::Min(200, $output.Length)))" -Status "INFO"

        return $output
    } catch {
        Write-VorceStep -Message "Fehler beim Aufruf des Agents: $($_.Exception.Message)" -Status "ERROR"
        return $null
    } finally {
        Write-VorceStep -Message "Bereinige temporäre Dateien: '$outputFile'" -Status "INFO"
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        if ($errorFile) { # Ensure errorFile is cleaned up
             Write-VorceStep -Message "Bereinige temporäre Fehler-Datei: '$errorFile'" -Status "INFO"
             Remove-Item $errorFile -Force -ErrorAction SilentlyContinue
        }
        if ($promptInputFile) {
            Write-VorceStep -Message "Bereinige temporäre Prompt-Datei: '$promptInputFile'" -Status "INFO"
            Remove-Item $promptInputFile -Force -ErrorAction SilentlyContinue
        }
    }
}
