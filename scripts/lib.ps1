# Utilidades compartidas por los scripts PowerShell de la Etapa 8.
# No imprime credenciales. Las claves se pasan por entorno.

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:DockerImage = "postgres:18"

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Default = ""
    )
    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Import-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $root = Split-Path -Parent $Path
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { continue }
        if ($line.StartsWith("export ")) { $line = $line.Substring(7).Trim() }
        if ($line -notmatch "=") { continue }
        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($key -and [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key, "Process"))) {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

function Import-EnvFileIfRequested {
    $envFile = Get-EnvValue "ENV_FILE" ""
    if ($envFile) {
        if (-not [System.IO.Path]::IsPathRooted($envFile)) {
            $envFile = Join-Path (Get-Location).Path $envFile
        }
        Import-DotEnv -Path $envFile
    }
}

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Initialize-ScriptsConfig {
    $script:DbHost = Get-EnvValue "DB_HOST" "localhost"
    $script:DbPort = Get-EnvValue "DB_PORT" "5432"
    $script:DbName = Get-EnvValue "DB_NAME" "bodegas_del_atuel"
    $script:DbSslMode = Get-EnvValue "DB_SSLMODE" "require"

    $script:OwnerUser = Get-EnvValue "DB_OWNER_USER" (Get-EnvValue "POSTGRES_USER" "postgres")
    $script:OwnerPassword = Get-EnvValue "DB_OWNER_PASSWORD" (Get-EnvValue "POSTGRES_PASSWORD" "")
    $script:ApiUser = Get-EnvValue "DB_USER" "rol_api"
    $script:ApiPassword = Get-EnvValue "DB_PASSWORD" (Get-EnvValue "APP_DB_PASSWORD" "")
    $script:ReportPassword = Get-EnvValue "APP_REPORT_PASSWORD" ""
    $script:ApiPublicUrl = Get-EnvValue "API_PUBLIC_URL" ""

    $script:PsqlMode = Get-EnvValue "PSQL_MODE" "auto"
    $script:UseDocker = $false
    if ($script:PsqlMode -ne "local" -and (Test-Command "docker")) {
        $script:UseDocker = $true
    } elseif (Test-Command "psql") {
        $script:UseDocker = $false
    } else {
        throw "No se encontró docker ni psql. Instalá Docker Desktop o PostgreSQL."
    }
}

function Assert-Value {
    param(
        [AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Falta la variable de entorno obligatoria $Name."
    }
}

function Assert-SafeIdentifier {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
        throw "Identificador inválido: $Value. Usá solo letras, números y guion bajo."
    }
}

function Get-DockerDbHost {
    if ($script:DbHost -in @("localhost", "127.0.0.1", "::1")) {
        return "host.docker.internal"
    }
    return $script:DbHost
}

function Get-PsqlRelativeSqlFile {
    param([Parameter(Mandatory = $true)][string]$SqlFile)
    $full = $SqlFile
    if (-not [System.IO.Path]::IsPathRooted($full)) {
        $full = Join-Path $script:RepoRoot $full
    }
    $full = [System.IO.Path]::GetFullPath($full)
    if (-not (Test-Path -LiteralPath $full)) {
        throw "No existe el archivo SQL: $full"
    }
    $root = [System.IO.Path]::GetFullPath($script:RepoRoot)
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "El archivo SQL debe estar dentro del repositorio: $full"
    }
    $relative = $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
    return "/repo/$relative"
}

function Set-DbEnvironment {
    param(
        [string]$User,
        [string]$Password,
        [string]$SslMode
    )
    $env:PGPASSWORD = $Password
    $env:PGSSLMODE = $SslMode
    $env:APP_DB_PASSWORD = $script:ApiPassword
    $env:APP_REPORT_PASSWORD = $script:ReportPassword
    $env:PGCONNECT_TIMEOUT = "10"
}

function Restore-DbEnvironment {
    param([hashtable]$Previous)
    foreach ($key in $Previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $Previous[$key], "Process")
    }
}

function Invoke-Psql {
    param(
        [string]$Database = $script:DbName,
        [string]$User = $script:OwnerUser,
        [string]$Password = $script:OwnerPassword,
        [string]$SslMode = $script:DbSslMode,
        [string]$SqlFile = "",
        [string]$Command = "",
        [string]$InputText = "",
        [switch]$TuplesOnly,
        [switch]$NoAlign,
        [string]$FieldSeparator = "|",
        [switch]$AllowFailure
    )
    Assert-Value -Value $Password -Name "la clave de conexión de $User"

    $psqlArgs = @("-X", "-q", "-v", "ON_ERROR_STOP=1", "-h", $(if ($script:UseDocker) { Get-DockerDbHost } else { $script:DbHost }), "-p", $script:DbPort, "-U", $User, "-d", $Database)
    if ($TuplesOnly) { $psqlArgs += "-t" }
    if ($NoAlign) { $psqlArgs += "-A" }
    if ($FieldSeparator) { $psqlArgs += @("-F", $FieldSeparator) }
    if ($SqlFile) {
        if ($script:UseDocker) {
            $psqlArgs += @("-f", (Get-PsqlRelativeSqlFile -SqlFile $SqlFile))
        } else {
            $full = $SqlFile
            if (-not [System.IO.Path]::IsPathRooted($full)) { $full = Join-Path $script:RepoRoot $full }
            if (-not (Test-Path -LiteralPath $full)) { throw "No existe el archivo SQL: $full" }
            $psqlArgs += @("-f", $full)
        }
    }
    if ($Command) { $psqlArgs += @("-c", $Command) }

    $previous = @{
        PGPASSWORD = [Environment]::GetEnvironmentVariable("PGPASSWORD", "Process")
        PGSSLMODE = [Environment]::GetEnvironmentVariable("PGSSLMODE", "Process")
        APP_DB_PASSWORD = [Environment]::GetEnvironmentVariable("APP_DB_PASSWORD", "Process")
        APP_REPORT_PASSWORD = [Environment]::GetEnvironmentVariable("APP_REPORT_PASSWORD", "Process")
        PGCONNECT_TIMEOUT = [Environment]::GetEnvironmentVariable("PGCONNECT_TIMEOUT", "Process")
    }
    Set-DbEnvironment -User $User -Password $Password -SslMode $SslMode

    try {
        if ($script:UseDocker) {
            $dockerArgs = @(
                "run", "--rm", "-i",
                "--add-host=host.docker.internal:host-gateway",
                "-v", "$($script:RepoRoot):/repo:ro",
                "-w", "/repo",
                "-e", "PGPASSWORD",
                "-e", "PGSSLMODE",
                "-e", "APP_DB_PASSWORD",
                "-e", "APP_REPORT_PASSWORD",
                "-e", "PGCONNECT_TIMEOUT",
                $script:DockerImage,
                "psql"
            ) + $psqlArgs
            $eapPrevio = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                if ($InputText) {
                    $output = @($InputText | & docker @dockerArgs 2>&1 | ForEach-Object { "$_" })
                } else {
                    $output = @(& docker @dockerArgs 2>&1 | ForEach-Object { "$_" })
                }
            } finally {
                $ErrorActionPreference = $eapPrevio
            }
        } else {
            $eapPrevio = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                if ($InputText) {
                    $output = @($InputText | & psql @psqlArgs 2>&1 | ForEach-Object { "$_" })
                } else {
                    $output = @(& psql @psqlArgs 2>&1 | ForEach-Object { "$_" })
                }
            } finally {
                $ErrorActionPreference = $eapPrevio
            }
        }
        $code = $LASTEXITCODE
        if ($code -ne 0 -and -not $AllowFailure) {
            $output | ForEach-Object { Write-Host $_ }
            throw "psql terminó con código $code."
        }
        return [pscustomobject]@{ ExitCode = $code; Output = $output }
    } finally {
        Restore-DbEnvironment -Previous $previous
    }
}

function Invoke-DockerCommand {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [hashtable]$Environment = @{},
        [string[]]$Mounts = @()
    )
    Assert-Value -Value $script:OwnerPassword -Name "DB_OWNER_PASSWORD o POSTGRES_PASSWORD"
    $previous = @{}
    foreach ($key in $Environment.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
    }
    $previous["PGPASSWORD"] = [Environment]::GetEnvironmentVariable("PGPASSWORD", "Process")
    $previous["PGSSLMODE"] = [Environment]::GetEnvironmentVariable("PGSSLMODE", "Process")
    $previous["PGCONNECT_TIMEOUT"] = [Environment]::GetEnvironmentVariable("PGCONNECT_TIMEOUT", "Process")
    [Environment]::SetEnvironmentVariable("PGPASSWORD", $script:OwnerPassword, "Process")
    [Environment]::SetEnvironmentVariable("PGSSLMODE", $script:DbSslMode, "Process")
    [Environment]::SetEnvironmentVariable("PGCONNECT_TIMEOUT", "10", "Process")

    try {
        $dockerArgs = @("run", "--rm", "-i", "--add-host=host.docker.internal:host-gateway")
        foreach ($mount in $Mounts) { $dockerArgs += @("-v", $mount) }
        foreach ($key in $Environment.Keys) { $dockerArgs += @("-e", $key) }
        $dockerArgs += @("-e", "PGPASSWORD", "-e", "PGSSLMODE", "-e", "PGCONNECT_TIMEOUT")
        $dockerArgs += @($script:DockerImage)
        $dockerArgs += $Arguments
        $eapPrevio = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = @(& docker @dockerArgs 2>&1 | ForEach-Object { "$_" })
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $eapPrevio
        }
        return [pscustomobject]@{ ExitCode = $code; Output = $output }
    } finally {
        Restore-DbEnvironment -Previous $previous
    }
}
