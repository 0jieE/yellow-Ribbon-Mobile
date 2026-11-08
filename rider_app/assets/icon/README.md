# Launcher icon source

Save the **yellow scooter on a dark circle** artwork here as `icon.png`, then
run:

```
dart run flutter_launcher_icons
```

That regenerates `android/app/src/main/res/mipmap-*/ic_launcher.png` and the
adaptive-icon XML. Commit the generated files — the build does not run the
generator.

Requirements: square PNG, 1024×1024, no transparency at the edges (Android
masks it to the launcher's shape).

Note the adaptive background for this app is ink (`#1F1F1F`), not amber — the
mark is yellow-on-dark, the reverse of the other two.

This file is not bundled into the app. It is a build-time input only, which
is why it is deliberately absent from the `assets:` list in `pubspec.yaml`.
