<#  Run-Docker.ps1
    Builds (and optionally pushes) a Docker image using helper functions from
    LibreDevOpsHelpers.  Requires Docker CLI, PowerShell 7+, and the public
    PSGallery to be reachable. #>

param (
    [string]   $DockerFileName   = 'Dockerfile',                              # relative to BuildContext
    [string]   $DockerImageName  = 'ubuntu-base-docker-container/ubuntu-base',
    [string]   $RegistryUrl      = 'ghcr.io',
    [string]   $RegistryUsername,
    [string]   $RegistryPassword,
    [string]   $ImageOrg,
    [string]   $WorkingDirectory = (Get-Location).Path,                       # repo root
    [string]   $BuildContext     = (Get-Location).Path,                       # folder passed to docker build .
    [string]   $DebugMode        = 'false',
    [string]   $PushDockerImage  = 'true',
    [string[]] $AdditionalTags   = @('latest', (Get-Date -Format 'yyyy-MM'))
)

# ───────────────────────── PSGallery trust & module install ────────────────────
try {
    if     (Get-Command Set-PSRepository       -ErrorAction SilentlyContinue) {
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }
    }
    elseif (Get-Command Set-PSResourceRepository -ErrorAction SilentlyContinue) {
        Set-PSResourceRepository -Name PSGallery -Trusted -ErrorAction Stop
    }
    else { throw '❌ Neither PowerShellGet nor PSResourceGet is available.' }

    Write-Host "✅ PSGallery is trusted"
}
catch { Write-Error "❌ Failed to trust PSGallery: $_"; exit 1 }

try {
    if (-not (Get-Module -ListAvailable -Name LibreDevOpsHelpers)) {
        Install-Module LibreDevOpsHelpers -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "✅ Installed LibreDevOpsHelpers"
    } else {
        Write-Host "ℹ️  LibreDevOpsHelpers already present"
    }
} catch { Write-Error "❌ Failed to install LibreDevOpsHelpers : $_"; exit 1 }

Import-Module LibreDevOpsHelpers -ErrorAction Stop
_LogMessage INFO "✅ LibreDevOpsHelpers (and _LogMessage) loaded" -InvocationName $MyInvocation.MyCommand.Name

# ───────────────────────── prep paths & switches ──────────────────────────────
Set-Location $WorkingDirectory          # work inside repo root

if (-not $ImageOrg) { $ImageOrg = $RegistryUsername }
$DockerImageName = "{0}/{1}/{2}" -f $RegistryUrl, $ImageOrg, $DockerImageName

$DebugMode      = ConvertTo-Boolean $DebugMode
$PushDockerImage= ConvertTo-Boolean $PushDockerImage
if ($DebugMode) { $DebugPreference = 'Continue' }

# build command expects a **path** to context; file path may be relative
$DockerFilePath = Join-Path $BuildContext $DockerFileName

# ───────────────────────── docker build ───────────────────────────────────────
Assert-DockerExists
if (-not (Build-DockerImage -ContextPath $BuildContext -DockerFile $DockerFilePath)) {
    Write-Error 'Build failed'; exit 1
}

# ───────────────────────── tag extras ─────────────────────────────────────────
foreach ($tag in $AdditionalTags) {
    $fullTag = '{0}:{1}' -f $DockerImageName, $tag
    Write-Host "🏷 Tagging: $fullTag"
    docker tag $DockerImageName $fullTag
}

# ───────────────────────── push (optional) ────────────────────────────────────
if ($PushDockerImage) {
    $tagsToPush = $AdditionalTags | ForEach-Object { '{0}:{1}' -f $DockerImageName, $_ }
    if (-not (Push-DockerImage -FullTagNames $tagsToPush)) {
        Write-Error 'Push failed'; exit 1
    }
}

Write-Host '✅ All done.' -ForegroundColor Green
