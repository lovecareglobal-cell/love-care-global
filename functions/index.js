// APK NOTE: For APK, FCM must send android: { channelId: 'love_care_alerts', sound: 'love_care_bell' }
// The functions below already send notification.title/body - Android will use
// AndroidManifest default sound (love_care_bell.mp3 in res/raw) for those.
// If you want per-message channel, add in each send():
//   android: { channelId: 'love_care_alerts', sound: 'love_care_bell', priority: 'high' }
// Website / PWA ignores android.channelId - it uses webpush instead. Both can live together.

// functions/index.js - Firebase Cloud Function - sends push when a new Nurse/Client registers
// Deploy:  cd functions  &&  npm install  &&  firebase deploy --only functions
// This is what makes the phone alert when the app is CLOSED.
// Without this, nothing sends the push - the app alone cannot wake itself up.
//
// What it watches:
//   ceoRegistrationCenter/nurses/{uid}  -> "New Nurse: <name>"
//   ceoRegistrationCenter/clients/{uid} -> "New Client: <name>"
// Who gets it:
//   Topic 'ceo' - your CEO phone subscribes to it in main.dart (subscribeToTopic('ceo'))
//   Only CEO gets it, not nurses/clients.
const { onValueCreated } = require('firebase-functions/v2/database');
const admin = require('firebase-admin');
admin.initializeApp();

async function sendToCeo(title, body, type) {
  const message = {
    topic: 'ceo',
    notification: { title, body },
    data: {
      type: type,
      url: '/love-care-global/#/ceo-dashboard',
    },
    webpush: {
      notification: {
        title,
        body,
        icon: '/icons/Icon-192.png',
      },
      fcmOptions: { link: '/love-care-global/#/ceo-dashboard' },
    },
  };
  try {
    await admin.messaging().send(message);
    console.log('Push sent to ceo:', title);
  } catch (e) {
    console.error('Push failed:', e);
  }
}

exports.onNewNurse = onValueCreated(
  { ref: 'ceoRegistrationCenter/nurses/{uid}', region: 'us-central1' },
  async (event) => {
    const v = event.data.val() || {};
    const name = v.fullName || v.name || v.displayName || v.username || 'New Nurse';
    await sendToCeo('New Nurse Registered', name + ' - Tap to Approve / Reject', 'nurse');
  }
);

exports.onNewClient = onValueCreated(
  { ref: 'ceoRegistrationCenter/clients/{uid}', region: 'us-central1' },
  async (event) => {
    const v = event.data.val() || {};
    const name = v.fullName || v.name || v.displayName || v.clientName || v.username || 'New Client';
    await sendToCeo('New Client Registered', name + ' - Tap to view', 'client');
  }
);

// ---------- NURSE + CLIENT PUSH (same system, personal topics) ----------
// Nurses/clients subscribe in main.dart to:
//   topic 'user_{uid}'  - ONLY their own info
//   topic 'nurses' / 'clients' - broadcast
// So Ama (nurse) does NOT get Kofi's job offer.
//
// 1. New Booking / Job Offer -> Nurse gets "New Job Offer"
//    Watches: bookings/{bookingId} created, with nurseId / nurseUid
exports.onNewBookingForNurse = onValueCreated(
  { ref: 'bookings/{bookingId}', region: 'us-central1' },
  async (event) => {
    const v = event.data.val() || {};
    const nurseId = v.nurseId || v.nurseUid || null;
    const clientName = v.clientName || v.clientFullName || 'A Client';
    const title = 'New Job Offer / Booking';
    const body = clientName + ' sent you a booking - Tap to view';
    const msg = {
      notification: { title, body },
      data: { type: 'booking', url: '/love-care-global/#/nurse-dashboard' },
      webpush: { notification: { title, body, icon: '/icons/Icon-192.png' }, fcmOptions: { link: '/love-care-global/#/nurse-dashboard' } },
    };
    try {
      if (nurseId) await admin.messaging().send({ ...msg, topic: 'user_' + nurseId });
      else await admin.messaging().send({ ...msg, topic: 'nurses' });
    } catch (e) { console.error('Nurse booking push failed:', e); }
  }
);

// 2. Booking status changes -> Client gets "Booking Accepted / Nurse Assigned"
//    Watches: bookings/{bookingId} updated. Use onValueWritten and check status.
//    We send only if status looks like accepted / assigned / confirmed / completed.
const { onValueWritten } = require('firebase-functions/v2/database');
exports.onBookingStatusForClient = onValueWritten(
  { ref: 'bookings/{bookingId}', region: 'us-central1' },
  async (event) => {
    const after = (event.data && event.data.after) ? event.data.after.val() : null;
    const before = (event.data && event.data.before) ? event.data.before.val() : null;
    if (!after) return;
    const oldStatus = before ? String(before.status || '') : '';
    const newStatus = String(after.status || '');
    if (!newStatus || newStatus === oldStatus) return; // not a status change
    const clientId = after.clientId || after.clientUid || null;
    if (!clientId) return;
    const s = newStatus.toLowerCase();
    let title = 'Booking Update';
    let body = 'Your booking status: ' + newStatus;
    if (s.includes('accept') || s.includes('assign') || s.includes('confirm')) {
      title = 'Booking Accepted';
      body = 'A nurse accepted your booking - Tap to view';
    } else if (s.includes('reject') || s.includes('declin')) {
      title = 'Booking Update';
      body = 'Your booking was not accepted - Tap to book another nurse';
    } else if (s.includes('complet')) {
      title = 'Booking Completed';
      body = 'Your booking is completed - Tap to rate your nurse';
    }
    try {
      await admin.messaging().send({
        topic: 'user_' + clientId,
        notification: { title, body },
        data: { type: 'booking_update', url: '/love-care-global/#/client-dashboard' },
        webpush: { notification: { title, body, icon: '/icons/Icon-192.png' }, fcmOptions: { link: '/love-care-global/#/client-dashboard' } },
      });
    } catch (e) { console.error('Client booking push failed:', e); }
  }
);

// 3. New Job Offer (separate node, if your app uses jobOffers / my_job_offer) -> Nurse
exports.onNewJobOffer = onValueCreated(
  { ref: 'jobOffers/{offerId}', region: 'us-central1' },
  async (event) => {
    const v = event.data.val() || {};
    const nurseId = v.nurseId || v.nurseUid || null;
    const title = 'New Job Offer';
    const body = (v.clientName || 'A Client') + ' sent you a job offer - Tap to view';
    try {
      if (nurseId) await admin.messaging().send({ topic: 'user_' + nurseId, notification: { title, body }, data: { type: 'job_offer', url: '/love-care-global/#/my-job-offer' } });
      else await admin.messaging().send({ topic: 'nurses', notification: { title, body }, data: { type: 'job_offer', url: '/love-care-global/#/my-job-offer' } });
    } catch (e) { console.error('Job offer push failed:', e); }
  }
);

// 4. Chat message -> the RECEIVER (nurse OR client) gets "New Message"
//    Watches: chatMessages/{msgId} created, with toId / receiverId
exports.onNewChatMessage = onValueCreated(
  { ref: 'chatMessages/{msgId}', region: 'us-central1' },
  async (event) => {
    const v = event.data.val() || {};
    const toId = v.toId || v.receiverId || v.toUid || null;
    if (!toId) return;
    const title = 'New Message';
    const body = (v.senderName || 'Someone') + ': ' + String(v.text || v.message || 'Sent you a message').substring(0, 80);
    try {
      await admin.messaging().send({
        topic: 'user_' + toId,
        notification: { title, body },
        data: { type: 'message', url: '/love-care-global/#/chat-room' },
        webpush: { notification: { title, body, icon: '/icons/Icon-192.png' } },
      });
    } catch (e) { console.error('Chat push failed:', e); }
  }
);

// ========== NEW: COMPLETE DELETE - CEO DELETE => EMAIL FIT RE-REGISTER ==========
// Called from CEO app: FirebaseFunctions.instance.httpsCallable('deleteAuthUser').call({uid, email})
// Why this exists: Flutter app CANNOT delete another user's Auth account.
// Only Admin SDK (this function) can. Without this, delete in CEO app leaves
// Auth behind, and re-register fails with "email-already-in-use / already registered".
// This function uses v2 onCall to match the rest of this file - DO NOT use v1 syntax here.
// It deletes:
//   1. Firebase Auth user (by uid, or by email if uid empty)
//   2. RTDB: nurses/clients + all registration + allowed + email indexes + bookings for that uid
//   3. Firestore: same collections (best-effort, no crash if doc no dey)
//   4. Storage: nurses/{uid} + clients/{uid} folders (best-effort)
// CEO Flutter already deletes RTDB/Firestore/Storage too - this is backup so
// even if Flutter delete fails halfway, Auth + indexes still go, and email is free.
const { onCall, HttpsError } = require('firebase-functions/v2/https');

function sanitizeEmailKey(email) {
  return String(email || '').toLowerCase().replace(/[\.#\$@\[\]]/g, '_');
}

exports.deleteAuthUser = onCall(
  { region: 'us-central1' },
  async (request) => {
    const data = request.data || {};
    const uid = String(data.uid || '').trim();
    const email = String(data.email || '').toLowerCase().trim();
    const emailKey = sanitizeEmailKey(email);

    if (!uid && !email) {
      throw new HttpsError('invalid-argument', 'uid or email required');
    }

    // --- 1. Find Auth uid ---
    let targetUid = uid;
    let targetEmail = email;
    try {
      if (targetUid) {
        const u = await admin.auth().getUser(targetUid);
        targetEmail = (u.email || targetEmail || '').toLowerCase();
      } else if (targetEmail) {
        const u = await admin.auth().getUserByEmail(targetEmail);
        targetUid = u.uid;
      }
    } catch (e) {
      // Auth user may already be gone - continue to clean DB anyway
      console.log('Auth lookup: user not found or already deleted:', e.message);
    }

    // --- 2. Delete Auth user ---
    let authDeleted = false;
    if (targetUid) {
      try {
        await admin.auth().deleteUser(targetUid);
        authDeleted = true;
        console.log('Auth deleted:', targetUid, targetEmail);
      } catch (e) {
        if (e.code === 'auth/user-not-found') {
          authDeleted = true; // already gone = good, email is free
        } else {
          console.error('Auth delete failed:', e);
          throw new HttpsError('internal', 'Auth delete failed: ' + e.message);
        }
      }
    }

    // --- 3. RTDB cleanup (backup for Flutter delete) ---
    const db = admin.database();
    const rtdbBases = [
      'nurses', 'pending_nurses', 'pendingNurses', 'allNurses',
      'nurse_registrations', 'nurseApplications', 'nurseUsers',
      'ceoNurseUpdates', 'verified_nurses', 'nurseProfiles',
      'onlineNurses', 'nursePresence', 'nurseLocations',
      'clients', 'client_registrations', 'allClients', 'clientUsers',
      'ceoClientUpdates', 'verified_clients', 'onlineClients',
      'clientPresence', 'pending_clients', 'pendingClients',
      'pendingClientRegistrations', 'registrations',
    ];
    const indexPaths = [];
    if (targetUid) {
      indexPaths.push(
        'allowedNursesByUid/' + targetUid,
        'allowedClientsByUid/' + targetUid,
        'allowedNurses/' + targetUid,
        'allowedClients/' + targetUid,
        'users/' + targetUid,
      );
    }
    if (emailKey) {
      indexPaths.push(
        'allowedNurses/' + emailKey,
        'allowedClients/' + emailKey,
        'nursesByEmail/' + emailKey,
        'clientsByEmail/' + emailKey,
        'registeredEmails/' + emailKey,
        'usedEmails/' + emailKey,
        'registered_emails/' + emailKey,
        'used_emails/' + emailKey,
        'emailIndex/' + emailKey,
        'emails/' + emailKey,
        'emailToUid/' + emailKey,
        'usersByEmail/' + emailKey,
        'nurseEmails/' + emailKey,
        'clientEmails/' + emailKey,
        'users/' + emailKey,
      );
    }
    if (targetEmail) {
      indexPaths.push(
        'registeredEmails/' + targetEmail,
        'usedEmails/' + targetEmail,
        'emailToUid/' + targetEmail,
        'usersByEmail/' + targetEmail,
      );
    }
    try {
      for (const base of rtdbBases) {
        if (targetUid) await db.ref(base + '/' + targetUid).remove().catch(() => {});
        if (emailKey) await db.ref(base + '/' + emailKey).remove().catch(() => {});
      }
      // ceoRegistrationCenter sub-nodes
      if (targetUid) {
        await db.ref('ceoRegistrationCenter/nurses/' + targetUid).remove().catch(() => {});
        await db.ref('ceoRegistrationCenter/clients/' + targetUid).remove().catch(() => {});
      }
      for (const p of indexPaths) {
        await db.ref(p).remove().catch(() => {});
      }
      // Final sweep: any child in main bases whose email matches
      for (const base of ['nurses', 'pending_nurses', 'nurse_registrations', 'clients', 'client_registrations', 'ceoRegistrationCenter/nurses', 'ceoRegistrationCenter/clients']) {
        try {
          const snap = await db.ref(base).get();
          if (snap.exists()) {
            const val = snap.val();
            for (const k of Object.keys(val)) {
              const v = val[k] || {};
              const e2 = String(v.email || v.clientEmail || v.emailAddress || '').toLowerCase();
              if (targetEmail && e2 && e2 === targetEmail) {
                await db.ref(base + '/' + k).remove().catch(() => {});
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      console.error('RTDB cleanup failed (non-fatal):', e);
    }

    // --- 4. Firestore cleanup (best-effort) ---
    try {
      const fs = admin.firestore();
      const colls = ['nurses', 'nurse_registrations', 'ceo_registration', 'pending_nurses', 'nurseApplications', 'allNurses', 'nurseUsers', 'clients', 'client_registrations', 'pending_clients', 'clientApplications', 'allClients', 'clientUsers', 'users', 'registeredEmails', 'usedEmails', 'usersByEmail', 'emailIndex', 'nursesByEmail', 'clientsByEmail'];
      for (const coll of colls) {
        if (targetUid) await fs.collection(coll).doc(targetUid).delete().catch(() => {});
        if (emailKey) await fs.collection(coll).doc(emailKey).delete().catch(() => {});
        if (targetEmail) await fs.collection(coll).doc(targetEmail).delete().catch(() => {});
      }
    } catch (e) {
      console.error('Firestore cleanup failed (non-fatal):', e);
    }

    // --- 5. Storage cleanup (best-effort) - NOW scans ALL prefixes, not only nurses/{uid} ---
    try {
      const bucket = admin.storage().bucket();
      if (targetUid) {
        await bucket.deleteFiles({ prefix: 'nurses/' + targetUid + '/' }).catch(() => {});
        await bucket.deleteFiles({ prefix: 'clients/' + targetUid + '/' }).catch(() => {});
        await bucket.deleteFiles({ prefix: 'ceo_registration/' + targetUid + '/' }).catch(() => {});
        // Also try common upload folders with uid in name - registration dey use uploads/videos/images + random name
        // We list and delete files whose name contains uid - best effort
        try {
          const [files] = await bucket.getFiles({ prefix: 'uploads/', maxResults: 1000 });
          for (const f of files) {
            if (f.name.includes(targetUid) || (targetEmail && f.name.toLowerCase().includes(targetEmail))) {
              await f.delete().catch(() => {});
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      console.error('Storage cleanup failed (non-fatal):', e);
    }

    return { ok: true, authDeleted, uid: targetUid, email: targetEmail, message: 'Deleted Auth + DB indexes for ' + targetEmail };
  }
);

// ========== WIPE ALL - ONE TIME CLEANUP - FIX FOR CONSOLE STILL SHOWING EMAILS / FILES ==========
// Why Console still show emails/files after CEO list show (0)?
// 1. deleteAuthUser never deploy before, so Auth remain
// 2. Storage files no dey for nurses/{uid}/ - dem dey for uploads/videos/images + random name
// Called from CEO app: FirebaseFunctions.instance.httpsCallable('wipeAllAuthAndStorage').call({keepEmail: 'lovecareglobal@gmail.com'})
// This deletes EVERY Auth user (except keepEmail) + EVERY Storage file + ALL RTDB + ALL Firestore
// Use ONLY when you want empty system. CEO app go call am once, with Type WIPE confirm.
exports.wipeAllAuthAndStorage = onCall(
  { region: 'us-central1', timeoutSeconds: 540 },
  async (request) => {
    const keepEmail = String((request.data || {}).keepEmail || '').toLowerCase().trim();
    let authDeleted = 0;
    let authKept = 0;

    // --- 1. Delete ALL Auth users ---
    let nextPageToken;
    do {
      const list = await admin.auth().listUsers(1000, nextPageToken);
      for (const u of list.users) {
        const em = String(u.email || '').toLowerCase();
        if (keepEmail && em === keepEmail) { authKept++; continue; }
        try { await admin.auth().deleteUser(u.uid); authDeleted++; } catch (_) {}
      }
      nextPageToken = list.pageToken;
    } while (nextPageToken);

    // --- 2. Delete ALL Storage files (no matter folder name) ---
    let storageDeleted = 0;
    try {
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({ maxResults: 1000 });
      for (const f of files) {
        try { await f.delete(); storageDeleted++; } catch (_) {}
      }
    } catch (e) { console.error('Storage wipe failed:', e); }

    // --- 3. Delete ALL RTDB root nodes ---
    try {
      const db = admin.database();
      const roots = ['nurses','pending_nurses','pendingNurses','allNurses','nurse_registrations','nurseApplications','nurseUsers','ceoNurseUpdates','ceoRegistrationCenter','verified_nurses','allowedNurses','allowedNursesByUid','nursesByEmail','nurseProfiles','onlineNurses','nursePresence','nurseLocations','clients','client_registrations','allClients','clientUsers','ceoClientUpdates','verified_clients','allowedClients','allowedClientsByUid','pending_clients','pendingClients','pendingClientRegistrations','clientsByEmail','onlineClients','clientPresence','clientBookings','bookings','registrations','registeredEmails','usedEmails','emailIndex','emails','emailToUid','usersByEmail','nursesByEmail','clientsByEmail','usernames','nurseUsernames','clientUsernames','phones','nursePhones','clientPhones','users','nursingPins','usedPins','jobOffers','chatMessages'];
      for (const r of roots) await db.ref(r).remove().catch(()=>{});
    } catch (e) { console.error('RTDB wipe failed:', e); }

    // --- 4. Delete ALL Firestore collections ---
    try {
      const fs = admin.firestore();
      const colls = ['nurses','nurse_registrations','ceo_registration','pending_nurses','nurseApplications','allNurses','nurseUsers','clients','client_registrations','pending_clients','clientApplications','allClients','clientUsers','users','registeredEmails','usedEmails','usersByEmail'];
      for (const c of colls) {
        const snap = await fs.collection(c).limit(500).get();
        for (const d of snap.docs) await d.reference.delete().catch(()=>{});
      }
    } catch (e) { console.error('Firestore wipe failed:', e); }

    return { ok: true, authDeleted, authKept, storageDeleted, message: 'Deleted ' + authDeleted + ' Auth users, kept ' + authKept + ', deleted ' + storageDeleted + ' Storage files' };
  }
);
