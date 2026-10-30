# Release signing

Android identifies an app by its package name and signing key. Updates must be
signed with the same key, so create it once and keep it safe. If the key or its
password is lost, users can only get updates by uninstalling, which deletes
their on-device records.

## Create the key (once)

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\lifepilot-release.jks `
  -keyalg RSA -keysize 4096 -validity 10000 -alias lifepilot
```

Choose a strong password and store it in a password manager. Keep a copy of
the `.jks` file outside this computer, for example on an encrypted drive.

## Point the build at it

Create `android/key.properties` (ignored by git, never share it):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=lifepilot
storeFile=C:/Users/<you>/lifepilot-release.jks
```

Then build:

```powershell
flutter build apk --release --obfuscate --split-debug-info=build/symbols
# or, for Google Play:
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

Keep the `build/symbols` folder for each released version so crash stack
traces can be decoded with `flutter symbolize`.

## Switching from a debug-signed install

An APK signed with the release key cannot update one signed with the debug
key. Before switching, make an encrypted backup (More › Encrypted backup),
uninstall, install the release build and restore the backup.
