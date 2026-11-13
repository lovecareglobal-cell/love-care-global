// Firebase Options for Love Care Global - project web-care-618e8
// THIS is the root cause of "Cannot parse Firebase url".
// If databaseURL is missing here, EVERY page that uses
// FirebaseDatabase.instance fails on Web with that FATAL error.
// Put this file in: lib/firebase_options.dart  (replace the old one)
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  // Web - MUST have databaseURL, otherwise Realtime Database fails on Web
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB52-X1D8Cg-wUDWPds_tR7X3cF82dMdRg',
    appId: '1:1062578660694:web:f94dfe12c929df05bce2f7',
    messagingSenderId: '1062578660694',
    projectId: 'web-care-618e8',
    authDomain: 'web-care-618e8.firebaseapp.com',
    storageBucket: 'web-care-618e8.firebasestorage.app',
    // <-- THIS LINE WAS MISSING. This is the fix.
    databaseURL: 'https://web-care-618e8-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB52-X1D8Cg-wUDWPds_tR7X3cF82dMdRg',
    appId: '1:1062578660694:android:REPLACE_WITH_YOUR_ANDROID_APP_ID',
    messagingSenderId: '1062578660694',
    projectId: 'web-care-618e8',
    storageBucket: 'web-care-618e8.firebasestorage.app',
    databaseURL: 'https://web-care-618e8-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB52-X1D8Cg-wUDWPds_tR7X3cF82dMdRg',
    appId: '1:1062578660694:ios:REPLACE_WITH_YOUR_IOS_APP_ID',
    messagingSenderId: '1062578660694',
    projectId: 'web-care-618e8',
    storageBucket: 'web-care-618e8.firebasestorage.app',
    databaseURL: 'https://web-care-618e8-default-rtdb.firebaseio.com',
  );
}
