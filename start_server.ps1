<#
.SYNOPSIS
    Script para gerenciar serviços Django e Celery em ambiente Windows.

.DESCRIPTION
    Controla inicialização, parada, reinicialização e verificação de status de serviços Django e Celery,
    com gerenciamento de logs e PIDs.

.PARAMETER Command
    Comando a ser executado: start, stop, restart, status
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("start", "stop", "restart", "status")]
    [string]$Command
)

# Configurações
$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogDir = Join-Path $ProjectDir "log"
$Config = @{
    DjangoLog     = Join-Path $LogDir "django.log"
    CeleryLog     = Join-Path $LogDir "celery.log"
    DjangoPidFile = Join-Path $LogDir "django.pid"
    CeleryPidFile = Join-Path $LogDir "celery.pid"
    Port          = "8000"
    BindHost      = "0.0.0.0"
    Timeout       = 5
    VenvPath      = Join-Path $ProjectDir "venv"
}

# Funções auxiliares
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "ERROR", "WARNING")]
        [string]$Type,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$FilePath
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "$timestamp - $Type - $Message"
    
    if ($FilePath) {
        try {
            Add-Content -Path $FilePath -Value $logLine -ErrorAction Stop
        } catch {
            Write-Warning "Falha ao escrever no log ($FilePath): $_"
        }
    }
    Write-Host $logLine
}

function Initialize-Logs {
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
            Write-Log -Type "INFO" -Message "Diretório de logs criado: $LogDir" -FilePath $Config.DjangoLog
        }
        foreach ($logFile in @($Config.DjangoLog, $Config.CeleryLog)) {
            if (-not (Test-Path $logFile)) {
                New-Item -ItemType File -Path $logFile -Force | Out-Null
            }
        }
    } catch {
        Write-Log -Type "ERROR" -Message "Falha ao inicializar logs: $_"
        exit 1
    }
}

function Get-ProcessStatus {
    param (
        [string]$PidFile,
        [string]$ServiceName
    )
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id $pid -ErrorAction SilentlyContinue)) {
            return "Ativo (PID $pid)"
        }
    }
    return "Inativo"
}

function Start-Service {
    param (
        [string]$ServiceName,
        [string]$Command,
        [string]$LogFile,
        [string]$PidFile
    )
    try {
        $process = Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c", $Command `
            -WorkingDirectory $ProjectDir `
            -WindowStyle Hidden `
            -PassThru

        Start-Sleep -Seconds 1
        if ($process.HasExited) {
            throw "Processo ${ServiceName} terminou inesperadamente"
        }

        Set-Content -Path $PidFile -Value $process.Id -ErrorAction Stop
        Write-Log -Type "INFO" -Message "${ServiceName} iniciado (PID $($process.Id))" -FilePath $LogFile
    } catch {
        Write-Log -Type "ERROR" -Message "Falha ao iniciar ${ServiceName}: $_" -FilePath $LogFile
        throw
    }
}

function Stop-Service {
    param (
        [string]$ServiceName,
        [string]$PidFile,
        [string]$LogFile
    )
    if (-not (Test-Path $PidFile)) {
        Write-Log -Type "INFO" -Message "${ServiceName} já está parado" -FilePath $LogFile
        return
    }

    try {
        $pid = Get-Content $PidFile -ErrorAction Stop
        $process = Get-Process -Id $pid -ErrorAction Stop
        Stop-Process -Id $pid -Force -ErrorAction Stop
        Remove-Item -Path $PidFile -Force -ErrorAction Stop
        Write-Log -Type "INFO" -Message "${ServiceName} (PID $pid) finalizado" -FilePath $LogFile
    } catch {
        Write-Log -Type "WARNING" -Message "Erro ao parar ${ServiceName}: $_" -FilePath $LogFile
        if (Test-Path $PidFile) {
            Remove-Item -Path $PidFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Funções principais
function Start-Server {
    Initialize-Logs

    if (-not (Test-Path $Config.VenvPath)) {
        Write-Log -Type "ERROR" -Message "Ambiente virtual não encontrado em: $($Config.VenvPath)"
        exit 1
    }

    Write-Log -Type "INFO" -Message "Iniciando serviços..." -FilePath $Config.DjangoLog

    $djangoCmd = "venv\Scripts\python manage.py runserver $($Config.BindHost):$($Config.Port) >> `"$($Config.DjangoLog)`" 2>&1"
    Start-Service -ServiceName "Django" -Command $djangoCmd -LogFile $Config.DjangoLog -PidFile $Config.DjangoPidFile

    $celeryCmd = "venv\Scripts\celery -A core worker --loglevel=info --pool=solo >> `"$($Config.CeleryLog)`" 2>&1"
    Start-Service -ServiceName "Celery" -Command $celeryCmd -LogFile $Config.CeleryLog -PidFile $Config.CeleryPidFile
}

function Stop-Server {
    Write-Log -Type "INFO" -Message "Parando serviços..." -FilePath $Config.DjangoLog
    Stop-Service -ServiceName "Django" -PidFile $Config.DjangoPidFile -LogFile $Config.DjangoLog
    Stop-Service -ServiceName "Celery" -PidFile $Config.CeleryPidFile -LogFile $Config.CeleryLog
}

function Get-ServerStatus {
    Write-Host "`nStatus dos Serviços:"
    Write-Host " - Django: $(Get-ProcessStatus -PidFile $Config.DjangoPidFile -ServiceName 'Django')"
    Write-Host " - Celery: $(Get-ProcessStatus -PidFile $Config.CeleryPidFile -ServiceName 'Celery')"
}

# Execução
try {
    switch ($Command) {
        "start"   { Start-Server }
        "stop"    { Stop-Server }
        "restart" { Stop-Server; Start-Sleep -Seconds $Config.Timeout; Start-Server }
        "status"  { Get-ServerStatus }
    }
} catch {
    Write-Log -Type "ERROR" -Message "Erro durante execução: $_" -FilePath $Config.DjangoLog
    exit 1
}
