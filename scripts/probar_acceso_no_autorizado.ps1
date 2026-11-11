# Prueba de acceso a la base con y sin SSL. Debe ejecutarse desde una IP NO
# autorizada para documentar el rechazo. No imprime claves.
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
Import-EnvFileIfRequested
Initialize-ScriptsConfig
Assert-Value -Value $script:ApiPassword -Name "DB_PASSWORD o APP_DB_PASSWORD"

Write-Host "Prueba de acceso a $($script:DbName) en $($script:DbHost):$($script:DbPort) como $($script:ApiUser)"
Write-Host "Ejecutá esta prueba desde una IP NO permitida por el firewall/allowlist."
Write-Host ""

$resultados = @()
foreach ($modo in @("require", "disable")) {
    $r = Invoke-Psql -User $script:ApiUser -Password $script:ApiPassword -SslMode $modo -Command "SELECT current_user, current_database()" -TuplesOnly -NoAlign -AllowFailure
    $acceso = $r.ExitCode -eq 0
    $detalle = if ($acceso) { "conexión aceptada" } else { "conexión rechazada" }
    if (-not $acceso -and $r.Output.Count -gt 0) {
        $primera = ($r.Output | Where-Object { "$_".Trim() } | Select-Object -First 1)
        if ($primera) { $detalle = "$detalle · $primera" }
    }
    $resultados += [pscustomobject]@{
        SSL = $modo
        Resultado = if ($acceso) { "ACEPTADO" } else { "RECHAZADO" }
        Detalle = $detalle
    }
}

$resultados | Format-Table -AutoSize | Out-String | Write-Host

$requiere = $resultados | Where-Object { $_.SSL -eq "require" }
$sinSsl = $resultados | Where-Object { $_.SSL -eq "disable" }
Write-Host ""
if ($sinSsl.Resultado -eq "ACEPTADO") {
    Write-Host "ADVERTENCIA: la base aceptó una conexión sin SSL. Revisá pg_hba.conf." -ForegroundColor Yellow
}
if ($requiere.Resultado -eq "ACEPTADO" -and $sinSsl.Resultado -eq "ACEPTADO") {
    Write-Host "ADVERTENCIA: desde esta IP se aceptan ambos modos. Si la IP no está autorizada, revisá el firewall." -ForegroundColor Yellow
} elseif ($sinSsl.Resultado -eq "RECHAZADO") {
    Write-Host "OK: SSL obligatorio y conexión sin SSL rechazada."
} else {
    Write-Host "Resultado registrado. Desde una IP no autorizada se esperan ambos rechazos."
}
