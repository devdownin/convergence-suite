# Compatible avec Windows PowerShell 5.1 et PowerShell 7.
[CmdletBinding(DefaultParameterSetName = 'Test')]
param(
    [Parameter(ParameterSetName = 'Test')]
    [ValidateSet('Rapide', 'Complet')]
    [string]$Mode = 'Rapide',

    [Parameter(Mandatory = $true, ParameterSetName = 'Arret')]
    [switch]$Arreter
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.forecast-test.env'
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $rootHash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root))
} finally {
    $sha.Dispose()
}
$project = 'convergence-forecast-test-' + ([BitConverter]::ToString($rootHash, 0, 6).Replace('-', '').ToLowerInvariant())
$composeArgs = @(
    'compose', '--project-name', $project, '--env-file', $envFile,
    '-f', (Join-Path $root 'compose.yaml'),
    '-f', (Join-Path $root 'compose.forecast.yaml'),
    '-f', (Join-Path $root 'compose.forecast-test.yaml')
)

function Invoke-Compose {
    param([string[]]$Arguments)
    & docker @composeArgs @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose a echoue (code $LASTEXITCODE) : $($Arguments -join ' ')"
    }
}

$stage = 'Verification de Docker'
try {
    if ($Arreter -and -not (Test-Path -LiteralPath $envFile)) {
        Write-Host 'Aucune pile de test initialisee.'
        exit 0
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker est introuvable. Installez ou demarrez Docker Desktop.'
    }
    $engine = & docker info --format '{{.OSType}}'
    if ($LASTEXITCODE -ne 0 -or $engine -ne 'linux') {
        throw 'Demarrez Docker Desktop et selectionnez les conteneurs Linux.'
    }

    if ($Arreter) {
        $stage = 'Arret de la pile de test'
        Invoke-Compose @('down')
        Write-Host 'Pile de test arretee. Historique et poids des modeles conserves.'
        exit 0
    }

    $stage = 'Preparation de la configuration de test'
    if (-not (Test-Path -LiteralPath $envFile)) {
        $secretNames = @(
            'EXPLORER_MCP_AUTH_TOKEN', 'KEX_AGENT_API_KEY', 'AUTOROUTES_POSTGRES_PASSWORD',
            'FORECAST_POSTGRES_PASSWORD', 'TIMESFM_TOKEN'
        )
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $secrets = foreach ($name in $secretNames) {
                $bytes = New-Object byte[] 32
                $rng.GetBytes($bytes)
                $name + '=' + [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
            }
            [System.IO.File]::WriteAllLines($envFile, [string[]]$secrets)
        } finally {
            $rng.Dispose()
        }
    }
    Invoke-Compose @('config', '--quiet')

    $stage = 'Demarrage des services et chargement des modeles'
    Write-Host "Mode $Mode | projet $project"
    if ($Mode -eq 'Rapide') {
        Invoke-Compose @('up', '-d', '--build', 'timesfm')
        $stage = 'Inference TimesFM et Timestral sur une serie synthetique'
        Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'check-forecast-models.py') |
            & docker @composeArgs exec -T timesfm python -
        if ($LASTEXITCODE -ne 0) {
            throw "La verification des modeles a echoue (code $LASTEXITCODE)."
        }
    } else {
        Invoke-Compose @('up', '-d', '--build', 'explorer', 'autoroutes-backend', 'autoroutes-simulator')
        $binding = Invoke-Compose @('port', 'explorer', '8080')
        Write-Host "KafkaExplorer : http://$binding/metrics"
        $stage = 'Collecte Kafka et previsions des trois series de peage'
        Invoke-Compose @('run', '--rm', '--build', '--no-deps', '-T', 'forecast-test')
    }
    Write-Host "Test $Mode reussi. Pour arreter la pile : .\scripts\test-forecast.ps1 -Arreter"
} catch {
    [Console]::Error.WriteLine("$stage - $($_.Exception.Message)")
    if ($stage -ne 'Verification de Docker' -and (Test-Path -LiteralPath $envFile)) {
        & docker @composeArgs ps --all
        & docker @composeArgs logs --no-color --tail 60 forecast-model-prefetch timesfm explorer
    }
    exit 1
}
