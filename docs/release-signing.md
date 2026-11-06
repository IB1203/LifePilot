# Signing

LifePilot does not use a separate release key. Release APKs are signed with
the Android debug key of the computer that builds them
(`%USERPROFILE%\.android\debug.keystore`), so there is nothing to create or
keep secret.

## What this means

- Android only installs an update over an app signed with the same key. Keep
  building releases on the same computer, or copy `debug.keystore` to a new
  one; otherwise users must uninstall before installing.
- Versions up to 1.0.2 were signed with a different key (`CN=LifePilot,
  O=IB1203`). Moving from those to 1.1.0 needs a one-time reinstall:
  make an encrypted backup (More › Encrypted backup), uninstall, install the
  new APK, then restore the backup.
- Google Play does not accept debug-signed apps. Publishing there would need
  a proper upload key again.

## Build

```powershell
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```

Attach `build/app/outputs/flutter-apk/app-release.apk` (as `LifePilot.apk`)
and `app-arm64-v8a-release.apk` (as `LifePilot-arm64.apk`) to the GitHub
release. Keep `build/symbols` for each version to decode crash stack traces
with `flutter symbolize`.
