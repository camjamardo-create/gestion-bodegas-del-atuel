# Genera backup lógico con pg_dump en formato custom (-Fc) y/o SQL comprimido.
# Usa el rol propietario. Los archivos quedan en backups/ y están ignorados por Git.
[CmdletBinding()]
param(
    [ValidateSet("custom", "plain", "ambos")][string]$Formato = "ambos",
    [string]$Directorio = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
Import-EnvFileIfRequested
Initialize-ScriptsConfig
Assert-Value -Value $script:OwnerPassword -Name "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"

$backupDir = if ($Directorio) {
    if ([System.IO.Path]::IsPathRooted($Directorio)) { $Directorio } else { Join-Path $script:RepoRoot $Directorio }
} else {
    Join-Path $script:RepoRoot "backups"
}
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$base = "${script:DbName}_${stamp}"
$dumpHost = if ($script:UseDocker) { Get-DockerDbHost } else { $script:DbHost }
$creados = @()

function Assert-Archivo {
    param([string]$Ruta)
    if (-not (Test-Path -LiteralPath $Ruta)) { throw "No se generó el archivo $Ruta" }
    $info = Get-Item -LiteralPath $Ruta
    if ($info.Length -le 0) { throw "El archivo $Ruta está vacío." }
    return $info
}

Write-Host "Backup de $($script:DbName) en $($script:DbHost):$($script:DbPort) como $($script:OwnerUser)"
Write-Host "SSL: $($script:DbSslMode) · destino: $backupDir"
Write-Host ""

if ($Formato -eq "custom" -or $Formato -eq "ambos") {
    $custom = Join-Path $backupDir "$base.dump"
    Write-Host ">> pg_dump -Fc $base.dump"
    if ($script:UseDocker) {
        $dumpArgs = @(
            "pg_dump", "-h", $dumpHost, "-p", $script:DbPort,
            "-U", $script:OwnerUser, "-d", $script:DbName,
            "--format=custom", "--no-owner", "--no-privileges",
            "--file=/backups/$base.dump"
        )
        $r = Invoke-DockerCommand -Arguments $dumpArgs -Mounts @("${backupDir}:/backups")
        if ($r.ExitCode -ne 0) { $r.Output | ForEach-Object { Write-Host $_ }; throw "pg_dump -Fc falló." }
    } else {
        if (-not (Test-Command "pg_dump")) { throw "No se encontró pg_dump local." }
        $env:PGPASSWORD = $script:OwnerPassword
        $env:PGSSLMODE = $script:DbSslMode
        & pg_dump -h $script:DbHost -p $script:DbPort -U $script:OwnerUser -d $script:DbName --format=custom --no-owner --no-privileges --file=$custom
        if ($LASTEXITCODE -ne 0) { throw "pg_dump -Fc falló." }
    }
    $info = Assert-Archivo $custom
    $creados += $info
}

if ($Formato -eq "plain" -or $Formato -eq "ambos") {
    $plainBase = "$base.sql"
    $plainGz = Join-Path $backupDir "$base.sql.gz"
    Write-Host ">> pg_dump --format=plain | gzip -9 $base.sql.gz"
    if ($script:UseDocker) {
        $envs = @{
            PGHOST = $dumpHost
            PGPORT = $script:DbPort
            PGUSER = $script:OwnerUser
            PGDATABASE = $script:DbName
            BACKUP_FILE = "$base.sql.gz"
        }
        $shellArgs = @("-c", 'pg_dump --format=plain --no-owner --no-privileges | gzip -9 > "/backups/$BACKUP_FILE"')
        $r = Invoke-DockerCommand -Arguments (@("sh") + $shellArgs) -Environment $envs -Mounts @("${backupDir}:/backups")
        if ($r.ExitCode -ne 0) { $r.Output | ForEach-Object { Write-Host $_ }; throw "pg_dump plain/gzip falló." }
    } else {
        if (-not (Test-Command "pg_dump")) { throw "No se encontró pg_dump local." }
        if (-not (Test-Command "gzip")) { throw "No se encontró gzip local; usá Docker o instalá gzip." }
        $sqlTmp = Join-Path $backupDir $plainBase
        $env:PGPASSWORD = $script:OwnerPassword
        $env:PGSSLMODE = $script:DbSslMode
        & pg_dump -h $script:DbHost -p $script:DbPort -U $script:OwnerUser -d $script:DbName --format=plain --no-owner --no-privileges --file=$sqlTmp
        if ($LASTEXITCODE -ne 0) { throw "pg_dump plain falló." }
        & gzip -9 -f $sqlTmp
        if ($LASTEXITCODE -ne 0) { throw "gzip falló." }
    }
    $info = Assert-Archivo $plainGz
    $creados += $info
}

Write-Host ""
Write-Host "Backup generado:"
foreach ($info in $creados) {
    Write-Host ("  {0}  ({1:N0} bytes)" -f $info.FullName, $info.Length)
}
Write-Host "No se imprimieron credenciales. Verificá la restauración con scripts/restaurar_y_verificar.ps1."
