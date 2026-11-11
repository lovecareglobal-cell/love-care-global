// REPLACE these 6 values with YOURS from Firebase Console > Project Settings > Your apps > Web app
// Firebase Console: https://console.firebase.google.com
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
class DefaultFirebaseOptions {
  static FirebaseOptions get web => const FirebaseOptions(
    apiKey: 'PASTE_YOUR_API_KEY_HERE',
    appId: 'PASTE_YOUR_APP_ID_HERE',
    messagingSenderId: 'PASTE_YOUR_SENDER_ID_HERE',
    projectId: 'PASTE_YOUR_PROJECT_ID_HERE',
    authDomain: 'PASTE_YOUR_PROJECT_ID_HERE.firebaseapp.com',
    databaseURL: 'https://PASTE_YOUR_PROJECT_ID_HERE-default-rtdb.firebaseio.com',
    storageBucket: 'PASTE_YOUR_PROJECT_ID_HERE.appspot.com',
  );
}
