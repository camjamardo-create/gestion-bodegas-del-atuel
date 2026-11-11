# Aplica 001..008 con el rol propietario y fija las claves de rol_api y
# rol_reporte desde variables de entorno. No usa credenciales en argumentos.
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
Import-EnvFileIfRequested
Initialize-ScriptsConfig

Assert-Value -Value $script:OwnerPassword -Name "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"
Assert-Value -Value $script:ApiPassword -Name "APP_DB_PASSWORD o DB_PASSWORD"
Assert-Value -Value $script:ReportPassword -Name "APP_REPORT_PASSWORD"

Write-Host "Aplicando migraciones sobre $($script:DbName) en $($script:DbHost):$($script:DbPort) como $($script:OwnerUser)"
Write-Host "Modo de cliente: $(if ($script:UseDocker) { 'docker run postgres:18' } else { 'psql local' })"
Write-Host "SSL: $($script:DbSslMode)"
Write-Host ""

foreach ($numero in 1..8) {
    $archivo = "db/migrations/{0:D3}_" -f $numero
    $encontrado = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot "db/migrations") -Filter ("{0:D3}_*.sql" -f $numero) | Select-Object -First 1
    if (-not $encontrado) {
        throw "No se encontró la migración $numero en db/migrations."
    }
    Write-Host ">> Aplicando $($encontrado.Name)"
    $resultado = Invoke-Psql -SqlFile $encontrado.FullName
    $resultado.Output | ForEach-Object { Write-Host $_ }
    if ($resultado.ExitCode -ne 0) { throw "Falló la migración $($encontrado.Name)." }
}

Write-Host ">> Fijando claves de rol_api y rol_reporte"
$roles = Invoke-Psql -SqlFile "db/initdb/99_password_api.sql"
$roles.Output | ForEach-Object { Write-Host $_ }
if ($roles.ExitCode -ne 0) { throw "No se pudieron fijar las claves de los roles." }

Write-Host ""
Write-Host "Migraciones aplicadas. No se imprimieron claves."
