
param (
    [string]   $DockerFileName    = "Dockerfile",
    [string]   $DockerImageName   = "ubuntu-base-docker-container/ubuntu-base",
    [string]   $RegistryUrl       = "ghcr.io",
    [string]   $RegistryUsername,
    [string]   $RegistryPassword,
    [string]   $ImageOrg,
    [string]   $WorkingDirectory  = (Get-Location).Path,
    [string]   $BuildContext      = (Get-Location).Path,
    [string]   $DebugMode         = "false",
    [string]   $PushDockerImage   = "true",
    [string[]] $AdditionalTags    = @("latest", (Get-Date -Format "yyyy-MM"))
)


# switch to working folder
Set-Location $WorkingDirectory


Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
Set-PSResourceRepository -Name "PSGallery" -Trusted
Install-Module -Name LibreDevOpsHelpers -Force -AllowClobber -Scope CurrentUser -Repository PSGallery

# build full image name
if (-not $ImageOrg) { $ImageOrg = $RegistryUsername }
$DockerImageName = "{0}/{1}/{2}" -f $RegistryUrl, $ImageOrg, $DockerImageName

# convert booleans
$DebugMode       = ConvertTo-Boolean $DebugMode
$PushDockerImage = ConvertTo-Boolean $PushDockerImage
if ($DebugMode) { $DebugPreference = "Continue" }

# build
Check-DockerExists
if (-not (Build-DockerImage -ContextPath $BuildContext -DockerFile $DockerFileName)) {
    Write-Error "Build failed"; exit 1
}

# tag extras
foreach ($tag in $AdditionalTags) {
    $fullTag = "{0}:{1}" -f $DockerImageName, $tag
    Write-Host "🏷 Tagging: $fullTag"
    docker tag $DockerImageName $fullTag
}

# push if requested
if ($PushDockerImage) {
    $tagsToPush = $AdditionalTags | ForEach-Object { "{0}:{1}" -f $DockerImageName, $_ }
    if (-not (Push-DockerImage -FullTagNames $tagsToPush)) {
        Write-Error "Push failed"; exit 1
    }
}

Write-Host "✅ All done." -ForegroundColor Green
