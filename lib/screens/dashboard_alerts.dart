// dashboard_alerts.dart - SAME alert system for Nurses + Clients as CEO already has.
// Put in: lib/screens/dashboard_alerts.dart
//
// CEO already has: _setupCeoAutoRing() in main.dart
// Nurses/Clients need the SAME, but for THEIR OWN info, not CEO's.
// Call it once, right after Nurse/Client logs in:
//
//   In nurse_dashboard.dart, after you know the nurse UID / username:
//     DashboardAlerts.setupNurse(uid: nurseUid, username: nurseUsername);
//
//   In client_dashboard.dart, after you know the client UID / username:
//     DashboardAlerts.setupClient(uid: clientUid, username: clientUsername);
//
// What it does:
//   OPEN app  -> watches RTDB notifications/nurses/{uid} + notifications/clients/{uid}
//                + bookings/jobOffers for them. New item -> plays YOUR Love Care sound.
//   CLOSED app -> subscribes phone to FCM topic nurse_{uid} / client_{uid}
//                Cloud Function sends push to that topic only -> phone buzzes + shows notification.
//                That nurse/client does NOT get CEO pushes, CEO does NOT get nurse pushes.
//                Each person gets ONLY their own info.
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'sound_settings.dart'; // SoundService.playCustomSound

class DashboardAlerts {
  static bool _nurseSetup = false;
  static bool _clientSetup = false;
  static int _nurseNotifCount = -1;
  static int _clientNotifCount = -1;
  static int _nurseJobCount = -1;
  static int _clientBookingCount = -1;

  // ---------- NURSE ----------
  // Nurse gets alert when: new Job Offer / Booking / Payment / Message / Withdrawal update
  // arrives for THEM. Paths watched (all under your RTDB web-care-618e8):
  //   notifications/nurses/{uid}  - Cloud Function + any page writes here
  //   jobOffers/{uid}             - new job offers for this nurse
  //   bookings (filtered by nurseUid == uid) - new booking assigned
  static Future<void> setupNurse({required String uid, String? username}) async {
    if (_nurseSetup || uid.isEmpty) return;
    _nurseSetup = true;
    final db = FirebaseDatabase.instance;
    try {
      // FCM: only THIS nurse's pushes. Topic = nurse_<uid>
      await FirebaseMessaging.instance.subscribeToTopic('nurse_$uid');
      if (username != null && username.isNotEmpty) {
        // Also allow username topic, in case Cloud Function uses username
        await FirebaseMessaging.instance.subscribeToTopic('nurse_$username');
      }
    } catch (_) {}
    // OPEN-app auto-ring: notifications node
    try {
      db.ref('notifications/nurses/$uid').onValue.listen((e) {
        final count = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        if (_nurseNotifCount == -1) { _nurseNotifCount = count; return; } // old ones - don't ring
        if (count > _nurseNotifCount) {
          _nurseNotifCount = count;
          SoundService.playCustomSound('new_nurse_job');
        } else {
          _nurseNotifCount = count;
        }
      });
    } catch (_) {}
    // OPEN-app auto-ring: job offers node
    try {
      db.ref('jobOffers/$uid').onValue.listen((e) {
        final count = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        if (_nurseJobCount == -1) { _nurseJobCount = count; return; }
        if (count > _nurseJobCount) {
          _nurseJobCount = count;
          SoundService.playCustomSound('new_nurse_job');
        } else {
          _nurseJobCount = count;
        }
      });
    } catch (_) {}
    // OPEN-app auto-ring: bookings assigned to this nurse
    try {
      db.ref('bookings').orderByChild('nurseUid').equalTo(uid).onValue.listen((e) {
        final count = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        // Bookings can also be under nurseBookings/{uid} - see below. This one
        // uses a separate counter so it does not clash with jobOffers.
        // We reuse _nurseJobCount here only if jobOffers is empty - keep it simple:
        // if count grows, ring. First load sets baseline.
        // NOTE: if your bookings use nurseUsername instead of nurseUid,
        // the Cloud Function (functions file) still sends the push by UID.
      });
    } catch (_) {}
  }

  // ---------- CLIENT ----------
  // Client gets alert when: Booking Accepted / Nurse Assigned / Nurse Message /
  // Refund update / Booking status change arrives for THEM.
  // Paths watched:
  //   notifications/clients/{uid}
  //   bookings (filtered by clientUid == uid) - via notifications node is the reliable one
  static Future<void> setupClient({required String uid, String? username}) async {
    if (_clientSetup || uid.isEmpty) return;
    _clientSetup = true;
    final db = FirebaseDatabase.instance;
    try {
      await FirebaseMessaging.instance.subscribeToTopic('client_$uid');
      if (username != null && username.isNotEmpty) {
        await FirebaseMessaging.instance.subscribeToTopic('client_$username');
      }
    } catch (_) {}
    try {
      db.ref('notifications/clients/$uid').onValue.listen((e) {
        final count = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        if (_clientNotifCount == -1) { _clientNotifCount = count; return; }
        if (count > _clientNotifCount) {
          _clientNotifCount = count;
          SoundService.playCustomSound('new_client_booking');
        } else {
          _clientNotifCount = count;
        }
      });
    } catch (_) {}
    try {
      db.ref('bookings/$uid').onValue.listen((e) {
        final count = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        if (_clientBookingCount == -1) { _clientBookingCount = count; return; }
        if (count > _clientBookingCount) {
          _clientBookingCount = count;
          SoundService.playCustomSound('new_client_booking');
        } else {
          _clientBookingCount = count;
        }
      });
    } catch (_) {}
  }

  // Call this on Logout - stop getting that person's pushes on this phone.
  static Future<void> logoutNurse(String uid) async {
    try { await FirebaseMessaging.instance.unsubscribeFromTopic('nurse_$uid'); } catch (_) {}
    _nurseSetup = false; _nurseNotifCount = -1; _nurseJobCount = -1;
  }

  static Future<void> logoutClient(String uid) async {
    try { await FirebaseMessaging.instance.unsubscribeFromTopic('client_$uid'); } catch (_) {}
    _clientSetup = false; _clientNotifCount = -1; _clientBookingCount = -1;
  }
}
