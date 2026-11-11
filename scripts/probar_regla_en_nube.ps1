# Prueba de regla de negocio en la nube: intenta vender más unidades que el
# stock total y verifica que la API responda 409 sin modificar el stock.
# No modifica datos si la regla funciona. No imprime secretos.
[CmdletBinding()]
param(
    [string]$ApiUrl = "",
    [int]$Cliente = 0,
    [int]$Sala = 0,
    [int]$Vino = 0,
    [int]$Cantidad = 0
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
Import-EnvFileIfRequested

$api = if ($ApiUrl) { $ApiUrl } else { Get-EnvValue "API_PUBLIC_URL" "" }
if (-not $api) { throw "Definí -ApiUrl o la variable API_PUBLIC_URL (ej. https://app.example.com/api)." }
$api = $api.TrimEnd("/")
$clienteId = if ($Cliente -gt 0) { $Cliente } else { [int](Get-EnvValue "CLIENTE_ID" "1") }
$salaId = if ($Sala -gt 0) { $Sala } else { [int](Get-EnvValue "SALA_ID" "1") }

$curl = if (Test-Command "curl.exe") { "curl.exe" } elseif (Test-Command "curl") { "curl" } else { throw "Se requiere curl para esta prueba." }

function Invoke-Api {
    param([string]$Method, [string]$Path, [object]$Body = $null)
    $temp = $null
    $curlArgs = @("-sS", "-X", $Method, "-H", "Accept: application/json", "-w", "`n%{http_code}", "--max-time", "40")
    if ($null -ne $Body) {
        $temp = [System.IO.Path]::GetTempFileName()
        $json = $Body | ConvertTo-Json -Compress -Depth 10
        [System.IO.File]::WriteAllText($temp, $json, [System.Text.Encoding]::UTF8)
        $curlArgs += @("-H", "Content-Type: application/json", "--data-binary", "@$temp")
    }
    $curlArgs += "$api$Path"
    try {
        $raw = (& $curl @curlArgs 2>&1 | Out-String).TrimEnd()
    } finally {
        if ($temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    $lineas = $raw -split "`n"
    $status = 0
    if ($lineas.Count -gt 0) { [void][int]::TryParse($lineas[-1].Trim(), [ref]$status) }
    $cuerpo = if ($lineas.Count -gt 1) { ($lineas[0..($lineas.Count - 2)] -join "`n") } else { "" }
    $jsonBody = $null
    if ($cuerpo) {
        try { $jsonBody = $cuerpo | ConvertFrom-Json } catch { $jsonBody = $null }
    }
    return [pscustomobject]@{ Status = $status; Body = $jsonBody; Raw = $cuerpo }
}

function Get-Stock {
    param([int]$Codigo)
    $r = Invoke-Api -Method "GET" -Path "/vinos/$Codigo"
    if ($r.Status -ne 200 -or $null -eq $r.Body) { return $null }
    return $r.Body.stock_total
}

Write-Host "Prueba de regla en $api"
Write-Host ""

if ($Vino -le 0) {
    $lista = Invoke-Api -Method "GET" -Path "/vinos?page_size=1"
    if ($lista.Status -ne 200 -or $null -eq $lista.Body -or $lista.Body.total -eq 0) {
        throw "No se pudo obtener un vino de prueba desde /vinos."
    }
    $Vino = [int]$lista.Body.items[0].codigo
}
$stockAntes = Get-Stock -Codigo $Vino
if ($null -eq $stockAntes) { throw "No se pudo leer el vino $Vino." }
$cantidadPrueba = if ($Cantidad -gt 0) { $Cantidad } else { [int]$stockAntes + 1 }
if ($cantidadPrueba -le 0) { $cantidadPrueba = 1 }

Write-Host "Vino: $Vino · stock total antes: $stockAntes · cantidad solicitada: $cantidadPrueba"
Write-Host "Cliente: $clienteId · sala: $salaId"

$payload = @{
    id_cliente = $clienteId
    id_sala_venta = $salaId
    renglones = @(@{ codigo_vino = $Vino; cantidad = $cantidadPrueba })
}
$venta = Invoke-Api -Method "POST" -Path "/comprobantes" -Body $payload
$stockDespues = Get-Stock -Codigo $Vino

$mensaje = ""
if ($null -ne $venta.Body -and $null -ne $venta.Body.error) {
    $mensaje = "$($venta.Body.error.codigo): $($venta.Body.error.mensaje)"
} elseif ($null -ne $venta.Body -and $null -ne $venta.Body.numero) {
    $mensaje = "se creó el comprobante $($venta.Body.numero)"
}

Write-Host "HTTP: $($venta.Status)"
if ($mensaje) { Write-Host "Respuesta: $mensaje" }
Write-Host "Stock total después: $stockDespues"
Write-Host ""

$ok = $venta.Status -eq 409 -and $stockDespues -eq $stockAntes
if ($ok) {
    Write-Host "PASS: la regla rechazó la venta y el stock no cambió."
    exit 0
}

if ($venta.Status -eq 409) {
    Write-Host "FAIL: hubo 409, pero el stock cambió." -ForegroundColor Red
} elseif ($venta.Status -eq 201) {
    Write-Host "FAIL: la venta fue aceptada; se creó un comprobante real." -ForegroundColor Red
} else {
    Write-Host "FAIL: se esperaba 409 y se recibió $($venta.Status). Revisá los IDs de cliente/sala/vino." -ForegroundColor Red
}
exit 1
