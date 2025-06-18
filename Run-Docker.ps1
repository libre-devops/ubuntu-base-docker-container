<#
.SYNOPSIS
Build (and optionally push) a Docker image – GitHub Actions-friendly.

.PARAMETER DockerFileName
  File name of the Dockerfile, relative to -BuildContext.

.PARAMETER BuildContext
  Directory to use as docker build context.

  If you pass the literal string **github_workspace** the script substitutes
  it with "${{ github.workspace }}".

.PARAMETER WorkingDirectory
  Directory where the script will `Set-Location` before running anything
  (usually the repo root).

… (all other parameters unchanged)
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

# ──────────────────────────────────────────────────────────────────────────────
# 0.  Trust PSGallery + install LibreDevOpsHelpers
# ──────────────────────────────────────────────────────────────────────────────
try
{
    if (Get-Command Set-PSRepository -EA SilentlyContinue)
    {
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted')
        {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -EA Stop
        }
    }
    elseif (Get-Command Set-PSResourceRepository -EA SilentlyContinue)
    {
        Set-PSResourceRepository -Name PSGallery -Trusted -EA Stop
    }
    else
    {
        throw 'Neither PowerShellGet nor PSResourceGet is available.'
    }

    Write-Host "✅ PSGallery is trusted"
}
catch
{
    Write-Error "❌ Failed to trust PSGallery: $_"; exit 1
}

if (-not (Get-Module -ListAvailable -Name LibreDevOpsHelpers))
{
    try
    {
        Install-Module LibreDevOpsHelpers -Repository PSGallery `
            -Scope CurrentUser -AllowClobber -Force -EA Stop
        Write-Host "✅ Installed LibreDevOpsHelpers"
    }
    catch
    {
        Write-Error "❌ Could not install LibreDevOpsHelpers: $_"; exit 1
    }
}

Import-Module LibreDevOpsHelpers
_LogMessage INFO "✅ LibreDevOpsHelpers (and _LogMessage) loaded" `
           -InvocationName $MyInvocation.MyCommand.Name

# ──────────────────────────────────────────────────────────────────────────────
# 1.  Resolve paths & flags
# ──────────────────────────────────────────────────────────────────────────────
if ($BuildContext -eq 'github_workspace')
{
    $BuildContext = $WorkingDirectory
}
Set-Location $WorkingDirectory

$DockerfilePath = Join-Path $BuildContext $DockerFileName

if (-not $ImageOrg)
{
    $ImageOrg = $RegistryUsername
}
$DockerImageName = '{0}/{1}/{2}' -f $RegistryUrl, $ImageOrg, $DockerImageName

$DebugMode = ConvertTo-Boolean $DebugMode
$PushDockerImage = ConvertTo-Boolean $PushDockerImage
if ($DebugMode)
{
    $DebugPreference = 'Continue'
}

# ──────────────────────────────────────────────────────────────────────────────
# 2.  Build
# ──────────────────────────────────────────────────────────────────────────────
Assert-DockerExists              # helper from LibreDevOpsHelpers

_LogMessage INFO "⏳ Building '$DockerImageName' from Dockerfile: $DockerfilePath" `
           -InvocationName $MyInvocation.MyCommand.Name

$built = Build-DockerImage `
           -DockerfilePath $DockerfilePath `
           -ContextPath    $BuildContext

if (-not $built)
{
    Write-Error '❌ docker build failed'; exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# 3.  Tag extras
# ──────────────────────────────────────────────────────────────────────────────
foreach ($tag in $AdditionalTags)
{
    $fullTag = '{0}:{1}' -f $DockerImageName, $tag
    _LogMessage INFO "🏷  Tagging: $fullTag" -InvocationName $MyInvocation.MyCommand.Name
    docker tag $DockerImageName $fullTag
}

# ──────────────────────────────────────────────────────────────────────────────
# 4.  Push (optional)
# ──────────────────────────────────────────────────────────────────────────────
if ($PushDockerImage)
{
    $fullTags = $AdditionalTags | ForEach-Object { '{0}:{1}' -f $DockerImageName, $_ }
    if (-not (Push-DockerImage -FullTagNames $fullTags))
    {
        Write-Error '❌ docker push failed'; exit 1
    }
}

_LogMessage INFO '✅ All done.' -InvocationName $MyInvocation.MyCommand.Name
