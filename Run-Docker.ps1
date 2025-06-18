<#
.SYNOPSIS
Build (and optionally push) a Docker image – GitHub Actions-friendly.
#>

param (
    [string]   $DockerFileName = 'Dockerfile',
    [string]   $DockerImageName = 'ubuntu-base-docker-container/ubuntu-base',
    [string]   $RegistryUrl = 'ghcr.io',
    [string]   $RegistryUsername,
    [string]   $RegistryPassword,
    [string]   $ImageOrg,
    [string]   $WorkingDirectory = (Get-Location).Path,
    [string]   $BuildContext = (Get-Location).Path,
    [string]   $DebugMode = 'false',
    [string]   $PushDockerImage = 'true',
    [string[]] $AdditionalTags = @('latest', (Get-Date -Format 'yyyy-MM'))
)

# ────────────────────────────────────────────────────────────────────────────
# 0.  Trust PSGallery & ensure LibreDevOpsHelpers
# ────────────────────────────────────────────────────────────────────────────
try
{
    if (Get-Command Set-PSRepository -EA SilentlyContinue)
    {
        if ((Get-PSRepository PSGallery).InstallationPolicy -ne 'Trusted')
        {
            Set-PSRepository PSGallery -InstallationPolicy Trusted -EA Stop
        }
    }
    elseif (Get-Command Set-PSResourceRepository -EA SilentlyContinue)
    {
        Set-PSResourceRepository PSGallery -Trusted -EA Stop
    }
    else
    {
        throw 'Neither PowerShellGet nor PSResourceGet available.'
    }

    Write-Host "✅ PSGallery is trusted"
}
catch
{
    Write-Error "❌ $( $_.Exception.Message )"; exit 1
}

if (-not (Get-Module -ListAvailable -Name LibreDevOpsHelpers))
{
    try
    {
        Install-Module LibreDevOpsHelpers -Repo PSGallery `
            -Scope CurrentUser -Force -AllowClobber -EA Stop
        Write-Host "✅ Installed LibreDevOpsHelpers"
    }
    catch
    {
        Write-Error "❌ $_"; exit 1
    }
}
Import-Module LibreDevOpsHelpers
_LogMessage INFO "✅ LibreDevOpsHelpers loaded" -Inv $MyInvocation.MyCommand.Name

# ────────────────────────────────────────────────────────────────────────────
# 1.  Normalise paths & flags
# ────────────────────────────────────────────────────────────────────────────
$RepoRoot = (Resolve-Path $WorkingDirectory).Path

# Normalise BuildContext ----------------------------------------------------
switch ($BuildContext)
{
    'github_workspace' {
        $BuildContext = $RepoRoot
    }
    default {
        if (-not [IO.Path]::IsPathRooted($BuildContext))
        {
            $BuildContext = Join-Path $RepoRoot $BuildContext
        }
        $BuildContext = (Resolve-Path $BuildContext).Path
    }
}

# Normalise Dockerfile path --------------------------------------------------
if ( [IO.Path]::IsPathRooted($DockerFileName))
{
    # caller passed an absolute path – ignore BuildContext
    $DockerfilePath = (Resolve-Path $DockerFileName).Path
}
else
{
    $DockerfilePath = Join-Path $BuildContext $DockerFileName
    $DockerfilePath = (Resolve-Path $DockerfilePath).Path
}

Set-Location $RepoRoot        # stay in repo root for the rest

if (-not $ImageOrg)
{
    $ImageOrg = $RegistryUsername
}
$DockerImageName = "{0}/{1}/{2}" -f $RegistryUrl, $ImageOrg, $DockerImageName
if ([string]::IsNullOrWhiteSpace($DockerImageName) -or
        $DockerImageName -match '\/\/') {
    Write-Error 'Image name is empty – did you forget -ImageOrg or -RegistryUsername?'
    exit 1
}

$DebugMode = ConvertTo-Boolean $DebugMode
$PushDockerImage = ConvertTo-Boolean $PushDockerImage
if ($DebugMode)
{
    $DebugPreference = 'Continue'
}

# ────────────────────────────────────────────────────────────────────────────
# 2.  Build
# ────────────────────────────────────────────────────────────────────────────
Assert-DockerExists
_LogMessage INFO "⏳ Building '$DockerImageName' from $DockerfilePath" `
           -Inv $MyInvocation.MyCommand.Name

$built = Build-DockerImage -DockerfilePath $DockerfilePath -ContextPath $BuildContext
if (-not $built)
{
    Write-Error '❌ docker build failed'; exit 1
}

# ────────────────────────────────────────────────────────────────────────────
# 3.  Tag extras
# ────────────────────────────────────────────────────────────────────────────
foreach ($tag in $AdditionalTags)
{
    $fullTag = "{0}:{1}" -f $DockerImageName, $tag
    _LogMessage INFO "🏷  Tagging $fullTag" -Inv $MyInvocation.MyCommand.Name
    docker tag $DockerImageName $fullTag
}

# ────────────────────────────────────────────────────────────────────────────
# 4.  Push (optional)
# ────────────────────────────────────────────────────────────────────────────
if ($PushDockerImage)
{
    $tags = $AdditionalTags | ForEach-Object { "{0}:{1}" -f $DockerImageName, $_ }
    if (-not (Push-DockerImage -FullTagNames $tags))
    {
        Write-Error '❌ docker push failed'; exit 1
    }
}

_LogMessage INFO '✅ All done.' -Inv $MyInvocation.MyCommand.Name
