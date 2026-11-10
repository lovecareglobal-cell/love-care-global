# LOVE CARE GLOBAL - Flutter App

Flutter version of LOVE CARE GLOBAL HOME NURSING PWA.

## PWA vs Flutter
- `main` branch in old repo = PWA (HTML) - for PWABuilder / TWA
- This repo = Flutter - for real Play Store app with background notifications

## Setup
1. `flutter pub get`
2. Put your `google-services.json` in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/`
3. Replace `YOUR_ONESIGNAL_APP_ID` in `lib/main.dart` with your OneSignal App ID
4. `flutter run`

## Firebase
Same Firebase project as PWA: `web-care-618e8`
- RTDB: `ceoHomePageCurrent`, `nurses_group_chat`, `nurses`, `allowedNurses`
- Storage: `nurses/`, `ceoBanners/videos/`
- Auth: Email + Google

## Notifications
- Flutter uses FCM + OneSignal - works even when app is closed / killed
- PWA uses OneSignal Web - works only if PWA installed + browser open
