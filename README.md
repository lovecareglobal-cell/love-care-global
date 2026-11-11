# LOVE CARE GLOBAL - Flutter App

> Flutter version of LOVE CARE GLOBAL HOME NURSING PWA.

### ðŸ”— All Links

| What | Link |
|---|---|
| ðŸŒ **Live Site (Flutter Repo Pages)** | https://lovecareglobal-cell.github.io/love-care-global/ |
| ðŸ’» **This Repo (Flutter)** | https://github.com/lovecareglobal-cell/love-care-global |
| ðŸ“± **PWA (Old Repo - HTML)** | https://github.com/lovecareglobal-cell/love-care-global-cell |
| ðŸ  **Home / Index (Live)** | https://lovecareglobal-cell.github.io/love-care-global/ |
| âš™ï¸ **GitHub Pages Settings** | https://github.com/lovecareglobal-cell/love-care-global/settings/pages |
| ðŸ”¥ **Firebase Console** | https://console.firebase.google.com/ |
| ðŸ”” **OneSignal Dashboard** | https://dashboard.onesignal.com/ |
| ðŸ’³ **Paystack Dashboard** | https://dashboard.paystack.com/ |
| â–¶ï¸ **Google Play Console** | https://play.google.com/console/ |

---

## PWA vs Flutter

| | PWA | Flutter |
|---|---|---|
| **Repo** | Old repo â€” `main` branch | This repo â€” `main` branch |
| **Code** | HTML / JS | Dart / Flutter |
| **For** | PWABuilder / TWA | Real Play Store app |
| **Notifications** | Only when app is open / PWA installed | Background notifications â€” even when app is closed (FCM + OneSignal) |
| **Live Site** | Old repo Pages | https://lovecareglobal-cell.github.io/love-care-global/ |

> **Do NOT mix them.** Keep PWA on the old repo, Flutter on this repo.

---

## Setup

```bash
1. flutter pub get
2. Put your google-services.json in android/app/
   and GoogleService-Info.plist in ios/Runner/
3. Replace YOUR_ONESIGNAL_APP_ID in lib/main.dart with your OneSignal App ID
4. flutter run
```

### Build for Play Store

```bash
flutter build appbundle --release
# Upload build/app/outputs/bundle/release/app-release.aab to Play Console
```

### Build for Web (only if you want Pages to show the real app)

```bash
flutter build web --release
# Publish the build/web/ folder to Pages, NOT the repo root
```

---

## Structure

```
love-care-global/
â”œâ”€â”€ README.md                  <- This file
â”œâ”€â”€ index.html                 <- Landing page for GitHub Pages (NOT the app)
â”œâ”€â”€ pubspec.yaml               <- Dependencies
â”œâ”€â”€ android/app/google-services.json   <- YOUR Firebase file (do NOT commit keys publicly if you can avoid it)
â”œâ”€â”€ ios/Runner/GoogleService-Info.plist
â”œâ”€â”€ lib/
â”‚   â”œâ”€â”€ main.dart              <- App entry, FCM + OneSignal, home: IndexScreen()
â”‚   â””â”€â”€ screens/
â”‚       â”œâ”€â”€ index.dart         <- index.html (HOME PAGE)
â”‚       â”œâ”€â”€ nurse_register.dart, nurse_login.dart, nurse_dashboard.dart
â”‚       â”œâ”€â”€ client_register.dart, client_login.dart, client_dashboard.dart
â”‚       â”œâ”€â”€ book_nurse.dart, book_nurse_50.dart, my_bookings.dart
â”‚       â”œâ”€â”€ chat_room.dart, nurse_group_chat.dart
â”‚       â”œâ”€â”€ ceo_*.dart         <- All CEO pages
â”‚       â””â”€â”€ ... (full list below)
```

---

## All Pages â€” HTML â†’ Flutter â€” Links

### ðŸ  Home / Index

| HTML | Flutter | Route | Live / Repo Link |
|---|---|---|---|
| `index.html` / `index_4.html` | `lib/screens/index.dart` | `/` (home) | [Live Home](https://lovecareglobal-cell.github.io/love-care-global/) Â· [index.dart](https://github.com/lovecareglobal-cell/love-care-global/blob/main/lib/screens/index.dart) |

### ðŸ‘©â€âš•ï¸ Nurse

| HTML | Flutter | Route |
|---|---|---|
| `nurse-registration.html` | `lib/screens/nurse_register.dart` | `/nurse-register` |
| `nurse-login.html` | `lib/screens/nurse_login.dart` | `/nurse-login` |
| `nurses-dashboard.html` | `lib/screens/nurse_dashboard.dart` | `/nurse-dashboard` |
| `nurse-group-chat.html` | `lib/screens/nurse_group_chat.dart` | `/nurse-group-chat` |
| `nurse-settings.html` | `lib/screens/nurse_settings.dart` | `/nurse-settings` |
| `nurse-complaint.html` | `lib/screens/nurse_complaint.dart` | `/nurse-complaint` |
| `nurse-withdrawal.html` | `lib/screens/nurse_withdrawal.dart` | `/nurse-withdrawal` |
| `my-job-offer.html` | `lib/screens/my_job_offer.dart` | `/my-job-offer` |

### ðŸ‘¤ Client

| HTML | Flutter | Route |
|---|---|---|
| `client-registration.html` | `lib/screens/client_register.dart` | `/client-register` |
| `client-login.html` | `lib/screens/client_login.dart` | `/client-login` |
| `client-dashboard.html` | `lib/screens/client_dashboard.dart` | `/client-dashboard` |
| `client-settings.html` | `lib/screens/client_settings.dart` | `/client-settings` |
| `client-complaint.html` | `lib/screens/client_complaint.dart` | `/client-complaint` |
| `client-alerts.html` | `lib/screens/client_alerts.dart` | `/client-alerts` |
| `book-nurse.html` | `lib/screens/book_nurse.dart` | `/book-nurse` |
| `book-nurse-50-percent.html` | `lib/screens/book_nurse_50.dart` | `/book-nurse-50` |
| `my-bookings.html` | `lib/screens/my_bookings.dart` | `/my-bookings` |
| `chat-room.html` | `lib/screens/chat_room.dart` | `/chat-room` |
| `refund-query.html` | `lib/screens/refund_query.dart` | `/refund-query` |
| `increase-payment.html` | `lib/screens/increase_payment.dart` | `/increase-payment` |
| `rating.html` | `lib/screens/rating.dart` | `/rating` |
| `sos.html` | `lib/screens/sos.dart` | `/sos` |

### ðŸ”Š Sound / Alerts â€” ONLY Sound Settings

| HTML | Flutter | Route |
|---|---|---|
| `sound-settings.html` | `lib/screens/sound_settings.dart` | `/sound-settings` |
| `alert-settings.html` | `lib/screens/alert_settings.dart` (legacy â€” use Sound Settings only) | `/alert-settings` |

> **Rule:** No alert buttons anywhere. Only **Sound Settings** for sound / alerts. Same for nurses, clients, and CEO.

### ðŸ‘‘ CEO â€” Dashboard (14 Pages)

**CEO Home:** `lib/screens/ceo_dashboard.dart` â€” Route `/ceo-dashboard` â€” [ceo_dashboard.dart](https://github.com/lovecareglobal-cell/love-care-global/blob/main/lib/screens/ceo_dashboard.dart)

| # | HTML | Flutter | Route |
|---|---|---|---|
| 01 | `ceo-complainant.html` | `lib/screens/ceo_complainant.dart` | `/ceo-complainant` |
| 02 | `ceo-control-chat.html` | `lib/screens/ceo_control_chat.dart` | `/ceo-control-chat` |
| 03 | `ceo-notification-room.html` | `lib/screens/ceo_notification_room.dart` | `/ceo-notification-room` |
| 04 | `nurse-group-chat.html` | `lib/screens/nurse_group_chat.dart` | `/nurse-group-chat` |
| 05 | `ceo-control-pricing.html` | `lib/screens/ceo_control_pricing.dart` | `/ceo-control-pricing` |
| 06 | `ceo-finance.html` | `lib/screens/ceo_finance.dart` | `/ceo-finance` |
| 07 | `ceo-live-tracking-map.html` | `lib/screens/ceo_live_tracking_map.dart` | `/ceo-live-tracking-map` |
| 08 | `ceo-penalize.html` | `lib/screens/ceo_penalize.dart` | `/ceo-penalize` |
| 09 | `ceo-registration-center.html` | `lib/screens/ceo_registration_center.dart` | `/ceo-registration-center` |
| 10 | `ceo-refund-management.html` | `lib/screens/ceo_refund_management.dart` | `/ceo-refund-management` |
| 11 | `delete-nurse-all-paths.html` / `force-delete.html` | `lib/screens/force_delete.dart` | `/force-delete` |
| 12 | `ceo-bookings-progress.html` | `lib/screens/ceo_bookings_progress.dart` | `/ceo-bookings-progress` |
| 13 | `hr-page-GHS-USD.html` | `lib/screens/hr_page.dart` | `/hr-page` |
| 14 | `home-banner-control.html` | `lib/screens/home_banner_control.dart` (send HTML if not yet built) | `/home-banner-control` |

### ðŸ§¹ CEO Tools

| HTML | Flutter | Route | What it does |
|---|---|---|---|
| `ceo-control.html` | `lib/screens/ceo_control.dart` | `/ceo-control` | CEO Control â€” Clean |
| `cleanup-auto-approval.html` | `lib/screens/cleanup_auto_approval.dart` | `/cleanup-auto-approval` | Fix auto-approved bug â€” move nurses back to PENDING |
| `force-delete.html` | `lib/screens/force_delete.dart` | `/force-delete` | Force delete nurse by email from EVERYWHERE |

---

## Strict Rules (Do NOT Break)

1. **Nurse login:** Photo + Phone + Video + CEO Approval required. If login fails, do NOT save email at auth â€” delete auth user.
2. **Registration uploads:** Video must be used and saved at Firebase. CV + Video must upload.
3. **National ID:** System must detect if National ID uploaded is good and real from each country.
4. **CEO Registration Center:** DELETE button under each registration, pending or accepted â€” delete account + all particulars from Firebase.
5. **CEO Banner / Group Chat video:** Video must play WITH SOUND. Not stuck on "Sending to Home Page".
6. **Only Sound Settings** for sound / alerts. No alert buttons.
7. **Same Firebase** project / data in Flutter as HTML â€” same RTDB paths, Storage paths, logic.

---

## Firebase

- **Project:** `web-care-618e8`
- **RTDB:** `https://web-care-618e8-default-rtdb.firebaseio.com`
- Same RTDB paths, Storage paths, and logic as HTML. Do not create a second project.

### Firebase Files to Add (Not in Repo)

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

---

## GitHub Pages â€” Why It Showed README Before

GitHub Pages builds from `main` branch, `/ (root)`. If there is no `index.html` in root, Pages falls back to rendering `README.md`.

Fix used in this repo:
- `index.html` at root = landing page for https://lovecareglobal-cell.github.io/love-care-global/
- Real Flutter app is NOT run from that link â€” it is built with `flutter build appbundle` for Play Store, or `flutter build web` for web.

To turn Pages OFF: Repo â†’ Settings â†’ Pages â†’ Source: None â†’ Save.

---

## Upload Checklist

- [ ] Upload `README.md` (this file) to repo root â€” replace old README
- [ ] Upload `index.html` to repo root
- [ ] Upload `lib/screens/index.dart` + updated `lib/main.dart`
- [ ] Upload all `lib/screens/*.dart` files
- [ ] `flutter pub get`
- [ ] Add `google-services.json` + `GoogleService-Info.plist`
- [ ] Replace `YOUR_ONESIGNAL_APP_ID` in `lib/main.dart`
- [ ] `flutter run` â†’ test â†’ `flutter build appbundle` â†’ Play Console

---

## Support / Links Again

- Live Site: https://lovecareglobal-cell.github.io/love-care-global/
- Repo: https://github.com/lovecareglobal-cell/love-care-global
- Pages Settings: https://github.com/lovecareglobal-cell/love-care-global/settings/pages
- Firebase: https://console.firebase.google.com/
- OneSignal: https://dashboard.onesignal.com/
- Paystack: https://dashboard.paystack.com/
- Play Console: https://play.google.com/console/
