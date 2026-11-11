# Carga masiva completa o reducida. La carga usa el rol propietario, nunca
# rol_api. Al terminar se pueden ejecutar los controles de la Etapa 3.
[CmdletBinding()]
param(
    [ValidateSet("full", "reducida")][string]$Modo = "full",
    [double]$Escala = 0,
    [switch]$ConControl,
    [switch]$SinControl
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
Import-EnvFileIfRequested
Initialize-ScriptsConfig
Assert-Value -Value $script:OwnerPassword -Name "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"

$python = Join-Path $script:RepoRoot ".venv/Scripts/python.exe"
if (-not (Test-Path -LiteralPath $python)) {
    $python = Join-Path $script:RepoRoot ".venv/bin/python"
}
if (-not (Test-Path -LiteralPath $python)) {
    if (Test-Command "python") { $python = "python" }
    elseif (Test-Command "python3") { $python = "python3" }
    else { throw "No se encontró Python. Creá .venv o instalá Python 3.12." }
}

$env:DATABASE_URL = ""
$env:PGHOST = $script:DbHost
$env:PGPORT = $script:DbPort
$env:PGUSER = $script:OwnerUser
$env:PGPASSWORD = $script:OwnerPassword
$env:PGDATABASE = $script:DbName
$env:PGSSLMODE = $script:DbSslMode
$env:PGCONNECT_TIMEOUT = "30"
$env:APP_DB_PASSWORD = $script:ApiPassword
$env:APP_REPORT_PASSWORD = $script:ReportPassword

$argumentos = @("db/seed/cargar_datos.py", "--limpiar")
$conControl = [bool]$ConControl
if ($Modo -eq "reducida") {
    $escalaFinal = if ($Escala -gt 0) { $Escala } else { 0.1 }
    $argumentos += @("--escala", $escalaFinal.ToString([System.Globalization.CultureInfo]::InvariantCulture))
    if (-not $conControl) { $argumentos += "--sin-control" }
} elseif ($Escala -gt 0) {
    $argumentos += @("--escala", $Escala.ToString([System.Globalization.CultureInfo]::InvariantCulture))
}
if ($SinControl) { $argumentos += "--sin-control" }

Write-Host "Carga $Modo sobre $($script:DbName) en $($script:DbHost):$($script:DbPort) como $($script:OwnerUser)"
Write-Host "SSL: $($script:DbSslMode)"
Write-Host ""

& $python @argumentos
$codigo = $LASTEXITCODE
if ($codigo -ne 0) { throw "La carga terminó con código $codigo." }

if ($conControl -and $Modo -eq "reducida") {
    Write-Host ""
    Write-Host "Ejecutando consultas de control de la Etapa 3..."
    $control = Invoke-Psql -SqlFile "db/seed/consultas_control.sql"
    $control.Output | ForEach-Object { Write-Host $_ }
    if ($control.ExitCode -ne 0) { throw "Fallaron las consultas de control." }
}

Write-Host ""
Write-Host "Carga finalizada correctamente."
