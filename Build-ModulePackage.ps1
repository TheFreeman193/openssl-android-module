#!/usr/bin/env pwsh
# Copyright (c) 2026 Nicholas Bissell (TheFreeman193) MIT License: https://spdx.org/licenses/MIT.html

using namespace System.IO
using namespace System.Management.Automation
using namespace System.Collections.Generic
using namespace System.Text

[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [string]$SourceDir,

    [string]$BuildSuffix = '',

    [ValidateSet('Universal', 'arm64-v8a', 'armeabi-v7a', 'armeabi', 'x86_64', 'x86', 'mips64', 'mips', 'riscv64')]
    [string[]]$Abis = 'Universal',

    [string]$Ndk,

    [switch]$KeepStageDir
)
begin {
    $ShouldContinue = $false
    $NdkDataFile = Join-Path $PSScriptRoot 'GetNDK/NDKData.psd1'
    $OutDir = Join-Path $PSScriptRoot 'out'
    if (-not (Test-Path $NdkDataFile -PathType Leaf)) {
        $Err = [ErrorRecord]::new([FileNotFoundException]::new("NDK version map file '$NdkDataFile' not found."), 'FileNotFound', 'ObjectNotFound', $NdkDataFile)
        $PSCmdlet.WriteError($Err)
        return
    }

    $NdkData = Import-PowerShellDataFile $NdkDataFile
    $NdkSupportedApiMap = $NdkData.NDK_API
    $ApiAndroidVersionMap = $NdkData.API_VERSION

    if ($Abis -contains 'Universal') {
        $AbiName = 'Universal'
        $Abis = 'arm64-v8a', 'armeabi-v7a', 'armeabi', 'x86_64', 'x86', 'mips64', 'mips', 'riscv64'
    } else {
        $AbiName = $Abis -replace '[^a-z0-9_\-]' -join '-'
    }

    $DelList = [List[string]]::new()
    $ShouldContinue = $true
}
process {
    if (-not $ShouldContinue) { return }

    $SourceLeaf = Split-Path $SourceDir -Leaf
    $BuildMetaFile = Join-Path $SourceDir 'all_builds_info.txt'
    if (-not $Ndk -and (Test-Path $BuildMetaFile)) {
        $BuildMetadata = Get-Content $BuildMetaFile -Raw | ConvertFrom-StringData
        if ($null -ne $BuildMetadata.NDK_MAJOR -and $BuildMetadata.NDK_MAJOR -match '^\d+$') { $Ndk = $BuildMetadata.NDK_MAJOR }
    }
    if (-not $Ndk) {
        if ($SourceLeaf -notmatch 'API\d+_NDK(\d+)') {
            Write-Error 'Unable to determine NDK version from all_builds_info.txt or SourceDir name! Override with -Ndk <int> if NDK revision known'
            return
        }
        $Ndk = $Matches[1]
    }

    $MinMax = $NdkSupportedApiMap["$Ndk"] | Measure-Object -Minimum -Maximum
    $Min = $MinMax.Minimum -as [int]
    $Max = $MinMax.Maximum -as [int]
    $Latest = $NdkData['API_LATEST'] -as [int]
    if ($Max -eq ($Latest - 1)) { $Max = $Latest }
    $FirstVer = $ApiAndroidVersionMap["$Min"]
    $LastVer = $ApiAndroidVersionMap["$Max"]
    
    $ModulePropFile = Join-Path (Split-Path $OutDir) 'module_template/module.prop'
    $CustomiseScriptFile = Join-Path (Split-Path $OutDir) 'module_template/customize.sh'
    $InstallScripts = Join-Path (Split-Path $OutDir) 'module_template/META-INF'

    $ModuleProps = Get-Content $ModulePropFile -Raw | ConvertFrom-StringData
    if (-not $?) { return }
    if (-not [string]::IsNullOrWhiteSpace($BuildSuffix)) {
        $ModuleProps.id = $ModuleProps.id, $BuildSuffix -join '-'
    }
    $ModuleProps.updateJson = $ModuleProps.updateJson -replace
    '/module-update-.+\.json', "/module-update-$BuildSuffix-$AbiName.json" -replace '--', '-'
    [version]$Version = $ModuleProps.version
    $ModuleProps.versionCode = ($Version.Major * 1e4 + $Version.Minor * 100 + $Version.Build) -as [string]

    Write-Host -fo White "Packaging module for OpenSSL $($ModuleProps.version) - Android APIs $FirstVer-$LastVer"

    $StageDir = Join-Path $OutDir (New-Guid).Guid
    $null = New-Item -ItemType Directory $StageDir
    if (-not $?) { return }
    if (-not $KeepStageDir) { $DelList.Add($StageDir) }
    $PSCmdlet.WriteVerbose("Staging dir: '$StageDir', Delete after: $(-not $KeepStageDir)")

    Write-Host -fo White '    Create customize.sh script...'
    $CustomiseScript = (Get-Content $CustomiseScriptFile -Raw) -f
    $Min, $Max, "Android $FirstVer", "Android $LastVer", $ModuleProps.name, $ModuleProps.id
    if (-not $?) { return }

    Set-Content (Join-Path $StageDir 'customize.sh') $CustomiseScript -NoNewline
    if (-not $?) { return }

    Write-Host -fo White '    Create module.prop metadata...'
    $ModulePropTarget = Join-Path $StageDir 'module.prop'
    Set-Content $ModulePropTarget -Value @"
id=$($ModuleProps.id)
name=$($ModuleProps.name)
version=$($ModuleProps.version)
versionCode=$($ModuleProps.versionCode)
author=$($ModuleProps.author)
description=$($ModuleProps.description)
updateJson=$($ModuleProps.updateJson)
"@
    if (-not $?) { return }

    Write-Host -fo White '    Copy module installer scripts...'
    Copy-Item $InstallScripts $StageDir -Recurse
    if (-not $?) { return }

    Write-Host -fo White '    Copy binaries...'
    $BinDir = Join-Path $StageDir 'bin'
    $null = New-Item -ItemType Directory $BinDir
    if (-not $?) { return }
    Get-ChildItem $SourceDir -Directory | Where-Object Name -In $Abis | Copy-Item -Destination $BinDir -Recurse
    if (-not $?) { return }

    Write-Host -fo White '    Copy SSL default configuration...'
    $SslDir = Join-Path $StageDir 'system/etc/ssl'
    $null = New-Item -ItemType Directory $SslDir
    if (-not $?) { return }
    Get-ChildItem (Join-Path $SourceDir '*.cnf') -File | Copy-Item -Destination $SslDir -Recurse
    if (-not $?) { return }

    Write-Host -fo White '    Create module archive...'
    $ArchivePath = Join-Path $OutDir "OpenSSL-$($ModuleProps.version)-Android-$FirstVer-To-$LastVer-$AbiName.zip"

    Compress-Archive -Path "$StageDir/*" -DestinationPath $ArchivePath -CompressionLevel Optimal -Force -ErrorAction Stop
    if (-not $?) { return }

    Write-Host -fo White "    Module archive: $ArchivePath"
    Write-Host -fo Green '    Success.'
}
end {
    foreach ($Path in $DelList) {
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path $Path)) {
            Remove-Item $Path -Force -Recurse
        }
    }
}

<#
.SYNOPSIS
    Creates OpenSSL Android modules from build artifacts
.DESCRIPTION
    Creates OpenSSL Android module archives that can be installed with Magisk, KSU, or APatch manager.
.NOTES
    This script determines the NDK and API versions using the directory name from $SourceDir. You should therefore
    ensure that the artifact root name is in the form 'APIx_NDKy' and is structured as follows:

    APIx_NDKy
        arm64-v8a
            openssl
        armeabi-v7a
            openssl
        x86
            openssl
        ...
.PARAMETER SourceDir
    Specifies the location of the build artifacts produced by Build-OpenSSL.ps1.
    This always ends in the format SKDx_NDKy.
.PARAMETER OutDir
    Specifies where to save the complete module archive. Defaults to ./out relative to the script.
.PARAMETER KeepStageDir
    Prevents the script from deleting the staging directory where module files are copied before compression.
    Staging dirs are always a GUID/UUID e.g. 'a96d3ea2-b602-45f3-af67-d294a7871255'
.PARAMETER BuildSuffix
    Changes the module updateJson URL target and module ID to include a suffix.
.PARAMETER Abis
    Select the ABIs (application binary interfaces) to include in the module package.
    If 'Universal' is found anywhere in the list, the script packages all found ABIs.
.LINK
    https://github.com/TheFreeman193/openssl-android-module/blob/main/README.md
.EXAMPLE
    ./Build-ModulePackage.ps1 -SourceDir ./out/API35_NDK29

    Creates an installable module ZIP archive from the build output stored in ./out/API35_NDK29. The resulting
    module will be named "OpenSSL-<version>-Android-5.0-To-16.zip".
#>
