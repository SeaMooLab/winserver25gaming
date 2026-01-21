# Server 2025 Gaming

This script attempts to ensure the required Microsoft Store/Xbox gaming components are present and registered:
      - Microsoft Store
      - Xbox app (Gaming App)
      - Xbox Identity Provider
      - Xbox Game Bar
      - Xbox Console Companion (legacy; optional but sometimes helpful)
      - Gaming Services (system service + app package)
      - WebView2 Runtime (used by Store/Xbox UI flows)
      - VC++ 2015-2022 runtimes (common game dependency)

## Strategy
      1) Use Get-AppxPackage to detect packages.
      2) If missing, install via winget using the msstore source (since "treat like Windows 11").
      3) Re-register installed packages via Add-AppxPackage -Register to fix broken registrations.
      4) Ensure Gaming Services services are set to Automatic and running.

## Notes
      - This is designed to be idempotent. Re-running should be safe.
      - Requires Administrator.
      - winget + Microsoft Store source access is required to fetch Store-delivered apps (Xbox app, Identity Provider, etc.)

## Examples

```ps1
.\Install-XboxGamingStack.ps1

# To also install Xbox Console Companion (legacy)
.\Install-XboxGamingStack.ps1 -IncludeLegacyConsoleCompanion
```