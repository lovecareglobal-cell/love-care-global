# 💜 LOVE CARE GLOBAL

**Trusted Care, With Love**
CEO-verified Nurses. Safe Clients. No Fake Accounts.
Accra, Ghana — © 2026

---

## 🌐 LIVE APP

**Main App:**
https://lovecareglobal-cell.github.io/love-care-global/

---

## 🔗 ALL PAGES - CLICK TO OPEN

| Page | Link |
| :--- | :--- |
| **🏠 Home / Landing** | https://lovecareglobal-cell.github.io/love-care-global/ |
| **🚀 Get Started / Auth Choice** | https://lovecareglobal-cell.github.io/love-care-global/#/auth-choice |
| **🩺 Nurse Registration** | https://lovecareglobal-cell.github.io/love-care-global/#/nurse-registration |
| **🩺 Nurse Login** | https://lovecareglobal-cell.github.io/love-care-global/#/nurse-login |
| **❤️ Client Registration** | https://lovecareglobal-cell.github.io/love-care-global/#/client-registration |
| **❤️ Client Login** | https://lovecareglobal-cell.github.io/love-care-global/#/client-login |
| **📜 Terms & Conditions** | https://lovecareglobal-cell.github.io/love-care-global/#/terms |
| **🔒 Privacy Policy** | https://lovecareglobal-cell.github.io/love-care-global/#/privacy |
| **💸 Refund Policy** | https://lovecareglobal-cell.github.io/love-care-global/#/refund |
| **🗑️ Delete Account Policy** | https://lovecareglobal-cell.github.io/love-care-global/#/delete-account |
| **👥 Community Guidelines** | https://lovecareglobal-cell.github.io/love-care-global/#/community |

---



## ⚙️ HOW IT WORKS

1.  **NURSE:** Registers with Photo + Video + Phone. Waits for CEO Approval. Cannot login until approved.
2.  **CLIENT:** Registers with Username + Phone + OTP. Login with Username + Password ONLY - No SMS on login.
3.  **SECURITY:** One account cannot be both Nurse + Client. Unregistered users cannot login. Failed registration is deleted completely.
4.  **CEO:** Reviews all Nurses in CEO Dashboard / CEO Control and Approves / Rejects.

---

## 🔥 FIREBASE

**Project:** `web-care-618e8`
**Auth:** Email / Password (Username is stored as email internally)
**Firestore:** `users` collection - role = `nurse` or `client`

**If you see `[core/no-app]` error:**
Check `lib/main.dart` has:
```dart
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
### PASTE AM:

1. GitHub → `README.md` → Pencil → Select All → Delete → Paste this
2. Commit → Done

**⚠️ ONE THING BOSS:** For `/#/ceo-dashboard` link to work, your `main.dart` must get this route too:

```dart
'/ceo-dashboard': (context) => const CeoDashboardPage(),
