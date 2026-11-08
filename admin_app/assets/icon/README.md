# Launcher icon source

Save the **storefront / awning** artwork here as `icon.png`, then run:

```
dart run flutter_launcher_icons
```

That regenerates `android/app/src/main/res/mipmap-*/ic_launcher.png` and the
adaptive-icon XML. Commit the generated files — the build does not run the
generator.

Requirements: square PNG, 1024×1024, no transparency at the edges (Android
masks it to the launcher's shape).

This file is not bundled into the app. It is a build-time input only, which
is why it is deliberately absent from the `assets:` list in `pubspec.yaml`.
