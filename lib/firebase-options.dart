import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB52-X1D8Cg-wUDWPds_tR7X3cF82dMdRg',
    appId: '1:1062578660694:web:f94dfe12c929df05bce2f7',
    messagingSenderId: '1062578660694',
    projectId: 'web-care-618e8',
    authDomain: 'web-care-618e8.firebaseapp.com',
    databaseURL: 'https://web-care-618e8-default-rtdb.firebaseio.com',
    storageBucket: 'web-care-618e8.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB52-X1D8Cg-wUDWPds_tR7X3cF82dMdRg',
    appId: '1:1062578660694:web:f94dfe12c929df05bce2f7',
    messagingSenderId: '1062578660694',
    projectId: 'web-care-618e8',
    storageBucket: 'web-care-618e8.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB52-X1D8Cg-wUDWPds_tR7X3cF82dMdRg',
    appId: '1:1062578660694:web:f94dfe12c929df05bce2f7',
    messagingSenderId: '1062578660694',
    projectId: 'web-care-618e8',
    storageBucket: 'web-care-618e8.firebasestorage.app',
  );
}
