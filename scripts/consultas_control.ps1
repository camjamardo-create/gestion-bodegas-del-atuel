# Ejecuta las consultas de control de la Etapa 3 contra la base indicada.
# Es un script de lectura; usa el rol propietario para poder ver todas las tablas.
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
Import-EnvFileIfRequested
Initialize-ScriptsConfig
Assert-Value -Value $script:OwnerPassword -Name "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"

Write-Host "Controles sobre $($script:DbName) en $($script:DbHost):$($script:DbPort) como $($script:OwnerUser)"
Write-Host "SSL: $($script:DbSslMode)"
Write-Host ""

$resultado = Invoke-Psql -SqlFile "db/seed/consultas_control.sql"
$resultado.Output | ForEach-Object { Write-Host $_ }
if ($resultado.ExitCode -ne 0) { throw "Las consultas de control terminaron con error." }

Write-Host ""
Write-Host "Controles ejecutados. Revisá que las consultas marcadas como problema devuelvan 0 filas."
