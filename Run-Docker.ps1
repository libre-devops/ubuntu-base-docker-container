param (
    [string]   $DockerFileName = "Dockerfile",
    [string]   $DockerImageName = "ubuntu-base-docker-container/ubuntu-base",
    [string]   $RegistryUrl = "ghcr.io",
    [string]   $RegistryUsername,
    [string]   $RegistryPassword,
    [string]   $ImageOrg,
    [string]   $WorkingDirectory = (Get-Location).Path,
    [string]   $BuildContext = (Get-Location).Path,
    [string]   $DebugMode = "false",
    [string]   $PushDockerImage = "true",
    [string[]] $AdditionalTags = @("latest", (Get-Date -Format "yyyy-MM"))
)


# switch to working folder
Set-Location $WorkingDirectory

try
{
    if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue)
    {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction Stop
        if ($repo.InstallationPolicy -ne 'Trusted')
        {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }
    }
    elseif (Get-Command Set-PSResourceRepository -ErrorAction SilentlyContinue)
    {
        Set-PSResourceRepository -Name PSGallery -Trusted -ErrorAction Stop
    }
    else
    {
        throw 'PowerShellGet / PSResourceGet not found.'
    }

    if (Get-Command _LogMessage -ErrorAction SilentlyContinue)
    {
        _LogMessage INFO "✅ PSGallery is trusted" -InvocationName $MyInvocation.MyCommand.Name
    }
    else
    {
        Write-Host "✅ PSGallery is trusted" -ForegroundColor Green
    }
}
catch
{
    Write-Error "❌ Failed to trust PSGallery: $_"
    exit 1
}

foreach ($mod in $Modules)
{
    try
    {
        if (-not (Get-Module -ListAvailable -Name $mod))
        {
            Install-Module -Name $mod -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            $msg = "✅ Installed $mod"
        }
        else
        {
            $msg = "ℹ️  $mod already present"
        }

        if (Get-Command _LogMessage -ErrorAction SilentlyContinue)
        {
            _LogMessage INFO $msg -InvocationName $MyInvocation.MyCommand.Name
        }
        else
        {
            Write-Error "Modules don't appear to be imported successfully"
            throw
        }
    }
    catch
    {
        Write-Error "❌ Failed to install $mod : $_"
        exit 1
    }
}



foreach ($mod in $Modules)
{
    try
    {
        if (-not (Get-Module -ListAvailable -Name $mod))
        {
            Install-Module -Name $mod -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            $msg = "✅ Installed $mod"
        }
        else
        {
            $msg = "ℹ️ $mod already present"
        }

        _LogMessage INFO $msg -InvocationName $MyInvocation.MyCommand.Name
    }
    catch
    {
        Write-Error "❌ Failed to install $mod : $_"
        exit 1
    }
}

# build full image name
if (-not $ImageOrg)
{
    $ImageOrg = $RegistryUsername
}
$DockerImageName = "{0}/{1}/{2}" -f $RegistryUrl, $ImageOrg, $DockerImageName

# convert booleans
$DebugMode = ConvertTo-Boolean $DebugMode
$PushDockerImage = ConvertTo-Boolean $PushDockerImage
if ($DebugMode)
{
    $DebugPreference = "Continue"
}

# build
Check-DockerExists
if (-not (Build-DockerImage -ContextPath $BuildContext -DockerFile $DockerFileName))
{
    Write-Error "Build failed"; exit 1
}

# tag extras
foreach ($tag in $AdditionalTags)
{
    $fullTag = "{0}:{1}" -f $DockerImageName, $tag
    Write-Host "🏷 Tagging: $fullTag"
    docker tag $DockerImageName $fullTag
}

# push if requested
if ($PushDockerImage)
{
    $tagsToPush = $AdditionalTags | ForEach-Object { "{0}:{1}" -f $DockerImageName, $_ }
    if (-not (Push-DockerImage -FullTagNames $tagsToPush))
    {
        Write-Error "Push failed"; exit 1
    }
}

Write-Host "✅ All done." -ForegroundColor Green
