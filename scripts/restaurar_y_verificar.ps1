# Restaura un backup en una base temporal y compara los conteos de todas las
# tablas contra la base original. No toca la base original.
[CmdletBinding()]
param(
    [string]$BackupFile = "",
    [string]$RestoreDb = "",
    [switch]$Forzar,
    [switch]$EliminarRestaurada
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
Import-EnvFileIfRequested
Initialize-ScriptsConfig
Assert-Value -Value $script:OwnerPassword -Name "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"
Assert-SafeIdentifier -Value $script:OwnerUser

if (-not $BackupFile) {
    $candidatos = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot "backups") -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "\.(dump|backup|sql|sql\.gz)$" } |
        Sort-Object LastWriteTime -Descending
    if (-not $candidatos) { throw "No hay backups en backups/. Indicá -BackupFile." }
    $BackupFile = $candidatos[0].FullName
} elseif (-not [System.IO.Path]::IsPathRooted($BackupFile)) {
    $BackupFile = Join-Path $script:RepoRoot $BackupFile
}
$BackupFile = [System.IO.Path]::GetFullPath($BackupFile)
if (-not (Test-Path -LiteralPath $BackupFile)) { throw "No existe el backup $BackupFile" }
$info = Get-Item -LiteralPath $BackupFile
if ($info.Length -le 0) { throw "El backup está vacío." }
$backupDir = Split-Path -Parent $BackupFile
$backupName = Split-Path -Leaf $BackupFile

if (-not $RestoreDb) {
    $RestoreDb = "{0}_restore_{1}" -f $script:DbName, (Get-Date -Format "yyyyMMdd_HHmmss")
}
Assert-SafeIdentifier -Value $RestoreDb

$dumpHost = if ($script:UseDocker) { Get-DockerDbHost } else { $script:DbHost }

Write-Host "Restauración de prueba"
Write-Host "  Backup: $BackupFile"
Write-Host "  Base original: $($script:DbName) en $($script:DbHost):$($script:DbPort)"
Write-Host "  Base restaurada: $RestoreDb"
Write-Host "  SSL: $($script:DbSslMode)"
Write-Host ""

$existe = Invoke-Psql -Database "postgres" -Command "SELECT 1 FROM pg_database WHERE datname = '$RestoreDb'" -TuplesOnly -NoAlign
if (($existe.Output -join "").Trim() -eq "1") {
    if (-not $Forzar) {
        throw "La base $RestoreDb ya existe. Usá -Forzar para recrearla o elegí otro nombre."
    }
    Write-Host ">> Eliminando base existente $RestoreDb"
    $drop = Invoke-Psql -Database "postgres" -Command "DROP DATABASE `"$RestoreDb`""
    if ($drop.ExitCode -ne 0) { throw "No se pudo eliminar la base existente." }
}

Write-Host ">> Creando $RestoreDb"
$createSql = "CREATE DATABASE `"$RestoreDb`" OWNER `"$($script:OwnerUser)`""
$create = Invoke-Psql -Database "postgres" -Command $createSql
if ($create.ExitCode -ne 0) { throw "No se pudo crear la base de restauración." }

$extension = [System.IO.Path]::GetExtension($BackupFile).ToLowerInvariant()
if ($extension -in @(".dump", ".backup")) {
    Write-Host ">> pg_restore $backupName"
    if ($script:UseDocker) {
        $restoreArgs = @(
            "pg_restore", "--no-owner", "--no-privileges", "--exit-on-error",
            "-h", $dumpHost, "-p", $script:DbPort, "-U", $script:OwnerUser,
            "-d", $RestoreDb, "/backups/$backupName"
        )
        $r = Invoke-DockerCommand -Arguments $restoreArgs -Mounts @("${backupDir}:/backups:ro")
        if ($r.ExitCode -ne 0) { $r.Output | ForEach-Object { Write-Host $_ }; throw "pg_restore falló." }
    } else {
        if (-not (Test-Command "pg_restore")) { throw "No se encontró pg_restore local." }
        $env:PGPASSWORD = $script:OwnerPassword
        $env:PGSSLMODE = $script:DbSslMode
        & pg_restore --no-owner --no-privileges --exit-on-error -h $script:DbHost -p $script:DbPort -U $script:OwnerUser -d $RestoreDb $BackupFile
        if ($LASTEXITCODE -ne 0) { throw "pg_restore falló." }
    }
} elseif ($extension -eq ".gz" -and $BackupFile.ToLowerInvariant().EndsWith(".sql.gz")) {
    Write-Host ">> gunzip | psql $backupName"
    if ($script:UseDocker) {
        $envs = @{
            PGHOST = $dumpHost
            PGPORT = $script:DbPort
            PGUSER = $script:OwnerUser
            PGDATABASE_RESTORE = $RestoreDb
            BACKUP_FILE = $backupName
        }
        $shellArgs = @("-c", 'gunzip -c "/backups/$BACKUP_FILE" | psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE_RESTORE"')
        $r = Invoke-DockerCommand -Arguments (@("sh") + $shellArgs) -Environment $envs -Mounts @("${backupDir}:/backups:ro")
        if ($r.ExitCode -ne 0) { $r.Output | ForEach-Object { Write-Host $_ }; throw "La restauración del SQL comprimido falló." }
    } else {
        if (-not (Test-Command "psql")) { throw "No se encontró psql local." }
        if (-not (Test-Command "gzip")) { throw "No se encontró gzip local." }
        $env:PGPASSWORD = $script:OwnerPassword
        $env:PGSSLMODE = $script:DbSslMode
        & gzip -dc $BackupFile | & psql -X -q -v ON_ERROR_STOP=1 -h $script:DbHost -p $script:DbPort -U $script:OwnerUser -d $RestoreDb
        if ($LASTEXITCODE -ne 0) { throw "La restauración del SQL comprimido falló." }
    }
} elseif ($extension -eq ".sql") {
    Write-Host ">> psql $backupName"
    $env:PGPASSWORD = $script:OwnerPassword
    $env:PGSSLMODE = $script:DbSslMode
    if ($script:UseDocker) {
        $r = Invoke-DockerCommand -Arguments @("psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-h", $dumpHost, "-p", $script:DbPort, "-U", $script:OwnerUser, "-d", $RestoreDb, "-f", "/backups/$backupName") -Mounts @("${backupDir}:/backups:ro")
        if ($r.ExitCode -ne 0) { $r.Output | ForEach-Object { Write-Host $_ }; throw "La restauración del SQL falló." }
    } else {
        & psql -X -q -v ON_ERROR_STOP=1 -h $script:DbHost -p $script:DbPort -U $script:OwnerUser -d $RestoreDb -f $BackupFile
        if ($LASTEXITCODE -ne 0) { throw "La restauración del SQL falló." }
    }
} else {
    throw "Formato de backup no soportado: $extension. Usá .dump, .backup, .sql o .sql.gz."
}

function Get-Conteos {
    param([string]$Database)
    $r = Invoke-Psql -Database $Database -SqlFile "scripts/sql/conteos_todas_tablas.sql" -TuplesOnly -NoAlign
    if ($r.ExitCode -ne 0) { $r.Output | ForEach-Object { Write-Host $_ }; throw "No se pudieron leer los conteos de $Database." }
    $map = @{}
    foreach ($linea in $r.Output) {
        $texto = "$linea".Trim()
        if ($texto -match "^([^|]+)\|([0-9]+)$") {
            $map[$matches[1]] = [int64]$matches[2]
        }
    }
    return $map
}

Write-Host ""
Write-Host ">> Comparando conteos"
$original = Get-Conteos -Database $script:DbName
$restaurada = Get-Conteos -Database $RestoreDb
$tablas = @($original.Keys + $restaurada.Keys | Sort-Object -Unique)
$diferencias = @()
$totalOriginal = [int64]0
$totalRestaurada = [int64]0
foreach ($tabla in $tablas) {
    $a = if ($original.ContainsKey($tabla)) { $original[$tabla] } else { $null }
    $b = if ($restaurada.ContainsKey($tabla)) { $restaurada[$tabla] } else { $null }
    if ($null -ne $a) { $totalOriginal += $a }
    if ($null -ne $b) { $totalRestaurada += $b }
    if ($a -ne $b) {
        $diferencias += [pscustomobject]@{ Tabla = $tabla; Original = $a; Restaurada = $b }
    }
}

if ($diferencias.Count -gt 0) {
    Write-Host "Diferencias encontradas:"
    $diferencias | Format-Table -AutoSize | Out-String | Write-Host
    $codigo = 1
} else {
    Write-Host ("OK: {0} tablas y {1:N0} filas coinciden." -f $tablas.Count, $totalOriginal)
    $codigo = 0
}

if ($EliminarRestaurada) {
    Write-Host ">> Eliminando base restaurada $RestoreDb"
    $drop = Invoke-Psql -Database "postgres" -Command "DROP DATABASE `"$RestoreDb`""
    if ($drop.ExitCode -ne 0) { throw "No se pudo eliminar la base restaurada." }
} else {
    Write-Host "Base restaurada conservada: $RestoreDb"
}

if ($codigo -ne 0) { throw "La verificación de conteos falló." }
Write-Host "Restauración y verificación completadas."
