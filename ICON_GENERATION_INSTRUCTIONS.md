Place the launcher source image you attached into the project at:

  assets/icon/app_icon.png

Then run these commands from the project root to generate platform app icons:

```bash
flutter pub get
flutter pub run flutter_launcher_icons:main
```

Notes:
- The `pubspec.yaml` already contains the `flutter_launcher_icons` config and a dev dependency.
- If you prefer to generate icons manually, you can create the Android mipmap and iOS AppIcon sets using an image editor and place them into `android/app/src/main/res/mipmap-*` and `ios/Runner/Assets.xcassets/AppIcon.appiconset/` respectively.
- After generating icons, rebuild the app:

```bash
flutter clean
flutter run
```
