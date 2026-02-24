# OpenSSL Android Module

Standalone OpenSSL binaries for Android, packaged as Magisk, KernelSU (KSU), and APatch compatible modules.

Some Android editions don't include an OpenSSL command accessible on the command line.
This module is for those needing to work with OpenSSL databases on the command line but who are unable to use alternatives like the openssl Termux package.

The module detects the correct architecture and NDK at install. It uses the root overlay to place the openssl binary in an executable directory very commonly in `$PATH` without modifying any real partitions.
For Android 7.1 and up, this is `/product/bin`, and for older devices it is `/system/bin`.

This means the `openssl` command should be accessible regardless of which terminal emulator (or ADB, or Java call) you use.

## Releases

This repository contains release builds as ready-to-go universal Magisk/KSU/APatch modules, plus ABI-specific ones, for each [Android API](https://apilevels.com/) [compatibility window](https://github.com/android/ndk/wiki/Compatibility).
Each universal module contains all the architectures (ABIs) supported by the matching NDK and will copy the correct one at install time (`customize.sh` script).

For all devices from Android 5.0 Lollipop onwards, install the module labelled `Android-5.0-To-16` (built with NDK 29).
For older devices up to Android 4.4.4 KitKat, install the module labelled `Android-1.5-To-7.0` (built with NDK 11).

> [!TIP]
> If you wish to run the binary directly (without installing the module), you can set `$OPENSSL_CONFIG` to specify the *.cnf* configuration for CA and request operations.

## Building for Yourself

> [!IMPORTANT]
> Due to command line length limitations on Windows, you should use WSL with the Linux NDK to build OpenSSL for Android on Windows systems.

### NDK

In order to build openssl for Android yourself, you need a copy of the correct NDK for the target Android SDK.
You can use the `GetNDK/Get-NDK.ps1` script to download and extract an NDK for your system architecture automatically.

Running the script with no parameters will download the latest stable NDK for the current operating system and extract it to *./GetNDK/ndk* in the repo.

```powershell
./GetNDK/Get-NDK.ps1 [[-Version] <int[]>] [[-NdkDir] <String>] [[-TempDir] <String>] [[-ForcePlatform] <String>] [-KeepArchive] [-AllPlatforms] [-NoExtract] [-NoVerify] [<CommonParameters>]
```

- `-Version <ver>` specifies the NDK version to download. Defaults to the latest release (excluding betas).
- `-NdkDir <path>` specifies where to extract the NDK files. Defaults to *./NDK* relative to the script.
- `-TempDir <path>` specifies the staging directory for downloading/extracting the NDK files. Defaults to the user's temp path.
- `-KeepArchive` retains the downloaded NDK archive files in the temp path.
- `-ForcePlatform` downloads the NDK for a specific platform.
- `-AllPlatforms` downloads all supported editions of the NDK (currently 64-bit Windows, Linux, or macOS). This overrides `-ForcePlatform`.
- `-NoExtract` downloads the NDK archive but doesn't attempt to extract it.
- `-NoVerify` skips checking archives against stored file hashes before extracting.

### OpenSSL Source

The repository already contains OpenSSL source in the *./src* directory as a Git submodule.
Optionally, you can update the submodule by running `git -C src pull` or checkout a specific commit/tag ref with `git -C src checkout <ref>`.

### Build Script

> [!IMPORTANT]
> Ensure you set and export the `ANDROID_NDK_ROOT` environment variable to your NDK path.

The build script can build many combinations of target SDKs and NDKs.
If you are running an older device or one with an architecture that's no longer supported, such as ARMv5, you will need to use an earlier NDK.

Please see the [NDK compatibility](https://github.com/android/ndk/wiki/Compatibility) page for more details.

MIPS(64) and ARMv5 (armeabi) were supported up to and including NDK r16.

ARM64-v8a, ARMv7-A, x86_64, x86, and riscv64 are currently supported by the latest NDK.

```bash
export ANDROID_NDK_ROOT=./GetNDK/ndk/Linux64/29 # Path to your downloaded NDK
./build-openssl.sh [-n] [-i API] [-a ARCH] [BUILD_OPTIONS]

Options:
  -i, --api      Target Android API (SDK level) (must be supported by NDK)
  -a, --arch     Target architecture/ABI (arm64|arm64-v8a|arm|armeabi|armeabi-v7a|x86|x86_64|riscv64|mips|mips64)
  -n, --noop     Show build configuration only
  BUILD_OPTIONS  Override build options passed to src/Configure
                 Defaults to: no-shared no-engine no-tests no-capieng
```

### Package Into a Root Module for Magisk, KSU, APatch

This script takes the output from a build and creates a module archive that can be installed with Magisk, KSU, or APatch manager.

```powershell
./Build-ModulePackage.ps1 [-SourceDir] <string> [-BuildSuffix <string>] [-Abis <string[]>] [-Ndk <string>] [-KeepStageDir] [<CommonParameters>]
```

- `-SourceDir <path>` specifies the location of the build artifacts produced by `Build-OpenSSL.ps1`. This always ends in the format *APIx_NDKy*.
- `-BuildSuffix <string>` specifies a suffix to add to the module ID and update URL, for build variants.
- `-Abis <string[]>` specifies the ABI-specific binaries to package in this module, or *Universal* for all.
- `-Ndk <string>` overrides the NDK major revision detected from *all_builds_info.txt* or the `$SourceDir` naming scheme.
- `-KeepStageDir` prevents the script from deleting the staging directory where module files are copied before compression. Always a GUID/UUID.

#### Custom Compile Options

Any additional options passed to the `build-openssl.sh` script are passed through to the Perl configuration script.
For example, to build for ARMv5 with NDK r11 (threading and C-only mode needed):

```bash
export ANDROID_NDK_ROOT=~/ndk/android-ndk-r11 # Path to NDK
./build-openssl.sh -a armeabi no-shared no-engine no-tests no-capieng no-threads no-asm
```

## License

The build scripts in this repo are licensed under the permissive [MIT License](https://choosealicense.com/licenses/mit/).

The OpenSSL source is licensed under the [Apache 2.0 License](https://github.com/openssl/openssl/blob/master/LICENSE.txt).

## Credits

- [OpenSSL](https://github.com/openssl/openssl) &mdash; source
