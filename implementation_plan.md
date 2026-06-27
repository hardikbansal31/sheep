# Implement GitHub Release Auto-Updater & Windows Inno Setup Installer

Since Sheep is not distributed on app stores, we need a cross-platform way to notify users when a new version is released on GitHub, and a professional installer for Windows instead of a raw zip.

## User Review Required

We will implement a custom, lightweight update checker rather than relying on heavy third-party auto-updater packages. This approach guarantees compatibility across all platforms (Windows, Linux, macOS, Android, iOS) and is very easy to maintain.

We will also add an `installer.iss` script at the root directory (its there but its not working currently, github still builds a .zip). This script allows Windows users to compile a professional, single-executable installer using Inno Setup, packaging the compiled Flutter Windows release.

## Proposed Changes

### Dependencies
We will add the following standard Flutter packages to `pubspec.yaml`:
- `package_info_plus`: To read the current version of the app (e.g., `1.1.0`).
- `http`: To query the GitHub API.
- `url_launcher`: To open the GitHub download page in the browser.

### [Update Service]

#### [NEW] [update_service.dart](file:///home/hardik/projects/sheep/lib/core/update/update_service.dart)
A new service class that handles the update logic:
- Fetches `https://api.github.com/repos/hardikbansal31/sheep/releases/latest`.
- Parses the `tag_name` (e.g., `v1.2.0`) and compares it against the local app version using a simple semver comparison.
- Provides a `checkForUpdates(BuildContext)` method that displays an `AlertDialog` with the new version number, release notes, and an "Update Now" button if an update is found.

### [App Lifecycle]

#### [MODIFY] [main_layout.dart](file:///home/hardik/projects/sheep/lib/features/layout/layout_shell.dart) or similar
- We will inject the `checkForUpdates` call into the initial application load (e.g., in a post-frame callback in the main app layout) so that it runs exactly once per app session (offload it to a background thread so it doesnt block main ui. it should silently fail if internet is not present and then the application should run unaffected. add a check for updates button in settings page with a spinner as well. ).

### [Windows Installer]

#### [NEW] [installer.iss](file:///home/hardik/projects/sheep/installer.iss)
An Inno Setup Script template configuration for Windows packaging. It will:
- Target `build\windows\x64\runner\Release\*` for inclusion.
- Define installer properties like AppName (`Sheep`), AppVersion (`1.1.0`), Publisher, default installation directory (`{autopf}\Sheep`), shortcut creation, and automatic execution option after setup completes.

## Verification Plan

### Manual Verification
1. I will temporarily set the local app version to `0.0.1` and test the app to ensure the update dialog triggers and shows the latest GitHub release.
2. I will verify that the "Update Now" button successfully opens the web browser to the correct GitHub URL.
3. We will review the `installer.iss` script to verify file paths match the standard Flutter build output.
