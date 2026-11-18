// APK NOTE: For APK, FCM must send android: { channelId: 'love_care_alerts', sound: 'love_care_bell' }
// The functions below already send notification.title/body - Android will use
// AndroidManifest default sound (love_care_bell.mp3 in res/raw) for those.
// If you want per-message channel, add in each send():
//   android: { channelId: 'love_care_alerts', sound: 'love_care_bell', priority: 'high' }
// Website / PWA ignores android.channelId - it uses webpush instead. Both can live together.

// functions/index.js - Firebase Cloud Function
// Deploy:  cd functions  &&  npm install  &&  firebase deploy --only functions
//
// CLIENT NEW RULE:
// Pending = NOT verified email ONLY. CEO does NOT approve Client.
// Immediately emailVerified == true -> isApproved = true, canLogin = true, status = approved -> Login works straight.
// NURSE RULE UNCHANGED: Nurse still needs CEO approval.
//
// What it watches:
//   ceoRegistrationCenter/nurses/{uid}  -> "New Nurse: <name> - Tap to Approve / Reject"
//   ceoRegistrationCenter/clients/{uid} -> "New Client: <name> - Pending verification / Verified"
// Who gets it:
//   Topic 'ceo' - CEO phone subscribes in main.dart
const { onValueCreated } = require('firebase-functions/v2/database');
const admin = require('firebase-admin');
admin.initializeApp();

async function sendToCeo(title, body, type) {
  const message = {
    topic: 'ceo',
    notification: { title, body },
    data: { type: type, url: '/love-care-global/#/ceo-dashboard' },
    webpush: {
      notification: { title, body, icon: '/icons/Icon-192.png' },
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
    // NEW: Tell CEO if client is still Pending (not verified) or already Verified
    const verified = v.emailVerified === true;
    const label = verified ? 'Verified - Can login now, no CEO approval needed' : 'Pending - Not verified email yet';
    await sendToCeo('New Client Registered', name + ' - ' + label, 'client');
  }
);

// ---------- NURSE + CLIENT PUSH ----------
const { onValueWritten } = require('firebase-functions/v2/database');
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

exports.onBookingStatusForClient = onValueWritten(
  { ref: 'bookings/{bookingId}', region: 'us-central1' },
  async (event) => {
    const after = (event.data && event.data.after) ? event.data.after.val() : null;
    const before = (event.data && event.data.before) ? event.data.before.val() : null;
    if (!after) return;
    const oldStatus = before ? String(before.status || '') : '';
    const newStatus = String(after.status || '');
    if (!newStatus || newStatus === oldStatus) return;
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

// ========== COMPLETE DELETE ==========
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
    if (!uid && !email) throw new HttpsError('invalid-argument', 'uid or email required');
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
      console.log('Auth lookup: user not found or already deleted:', e.message);
    }
    let authDeleted = false;
    if (targetUid) {
      try {
        await admin.auth().deleteUser(targetUid);
        authDeleted = true;
        console.log('Auth deleted:', targetUid, targetEmail);
      } catch (e) {
        if (e.code === 'auth/user-not-found') authDeleted = true;
        else { console.error('Auth delete failed:', e); throw new HttpsError('internal', 'Auth delete failed: ' + e.message); }
      }
    }
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
      indexPaths.push('allowedNursesByUid/' + targetUid, 'allowedClientsByUid/' + targetUid, 'allowedNurses/' + targetUid, 'allowedClients/' + targetUid, 'users/' + targetUid);
    }
    if (emailKey) {
      indexPaths.push('allowedNurses/' + emailKey, 'allowedClients/' + emailKey, 'nursesByEmail/' + emailKey, 'clientsByEmail/' + emailKey, 'registeredEmails/' + emailKey, 'usedEmails/' + emailKey, 'registered_emails/' + emailKey, 'used_emails/' + emailKey, 'emailIndex/' + emailKey, 'emails/' + emailKey, 'emailToUid/' + emailKey, 'usersByEmail/' + emailKey, 'nurseEmails/' + emailKey, 'clientEmails/' + emailKey, 'users/' + emailKey);
    }
    if (targetEmail) {
      indexPaths.push('registeredEmails/' + targetEmail, 'usedEmails/' + targetEmail, 'emailToUid/' + targetEmail, 'usersByEmail/' + targetEmail);
    }
    try {
      for (const base of rtdbBases) {
        if (targetUid) await db.ref(base + '/' + targetUid).remove().catch(() => {});
        if (emailKey) await db.ref(base + '/' + emailKey).remove().catch(() => {});
      }
      if (targetUid) {
        await db.ref('ceoRegistrationCenter/nurses/' + targetUid).remove().catch(() => {});
        await db.ref('ceoRegistrationCenter/clients/' + targetUid).remove().catch(() => {});
      }
      for (const p of indexPaths) await db.ref(p).remove().catch(() => {});
      for (const base of ['nurses', 'pending_nurses', 'nurse_registrations', 'clients', 'client_registrations', 'ceoRegistrationCenter/nurses', 'ceoRegistrationCenter/clients']) {
        try {
          const snap = await db.ref(base).get();
          if (snap.exists()) {
            const val = snap.val();
            for (const k of Object.keys(val)) {
              const v = val[k] || {};
              const e2 = String(v.email || v.clientEmail || v.emailAddress || '').toLowerCase();
              if (targetEmail && e2 && e2 === targetEmail) await db.ref(base + '/' + k).remove().catch(() => {});
            }
          }
        } catch (_) {}
      }
    } catch (e) { console.error('RTDB cleanup failed (non-fatal):', e); }
    try {
      const fs = admin.firestore();
      const colls = ['nurses', 'nurse_registrations', 'ceo_registration', 'pending_nurses', 'nurseApplications', 'allNurses', 'nurseUsers', 'clients', 'client_registrations', 'pending_clients', 'clientApplications', 'allClients', 'clientUsers', 'users', 'registeredEmails', 'usedEmails', 'usersByEmail', 'emailIndex', 'nursesByEmail', 'clientsByEmail'];
      for (const coll of colls) {
        if (targetUid) await fs.collection(coll).doc(targetUid).delete().catch(() => {});
        if (emailKey) await fs.collection(coll).doc(emailKey).delete().catch(() => {});
        if (targetEmail) await fs.collection(coll).doc(targetEmail).delete().catch(() => {});
      }
    } catch (e) { console.error('Firestore cleanup failed (non-fatal):', e); }
    try {
      const bucket = admin.storage().bucket();
      if (targetUid) {
        await bucket.deleteFiles({ prefix: 'nurses/' + targetUid + '/' }).catch(() => {});
        await bucket.deleteFiles({ prefix: 'clients/' + targetUid + '/' }).catch(() => {});
        await bucket.deleteFiles({ prefix: 'ceo_registration/' + targetUid + '/' }).catch(() => {});
        try {
          const [files] = await bucket.getFiles({ prefix: 'uploads/', maxResults: 1000 });
          for (const f of files) {
            if (f.name.includes(targetUid) || (targetEmail && f.name.toLowerCase().includes(targetEmail))) await f.delete().catch(() => {});
          }
        } catch (_) {}
      }
    } catch (e) { console.error('Storage cleanup failed (non-fatal):', e); }
    return { ok: true, authDeleted, uid: targetUid, email: targetEmail, message: 'Deleted Auth + DB indexes for ' + targetEmail };
  }
);

// ========== WIPE ALL ==========
exports.wipeAllAuthAndStorage = onCall(
  { region: 'us-central1', timeoutSeconds: 540 },
  async (request) => {
    const keepEmail = String((request.data || {}).keepEmail || '').toLowerCase().trim();
    let authDeleted = 0; let authKept = 0;
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
    let storageDeleted = 0;
    try {
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({ maxResults: 1000 });
      for (const f of files) { try { await f.delete(); storageDeleted++; } catch (_) {} }
    } catch (e) { console.error('Storage wipe failed:', e); }
    try {
      const db = admin.database();
      const roots = ['nurses','pending_nurses','pendingNurses','allNurses','nurse_registrations','nurseApplications','nurseUsers','ceoNurseUpdates','ceoRegistrationCenter','verified_nurses','allowedNurses','allowedNursesByUid','nursesByEmail','nurseProfiles','onlineNurses','nursePresence','nurseLocations','clients','client_registrations','allClients','clientUsers','ceoClientUpdates','verified_clients','allowedClients','allowedClientsByUid','pending_clients','pendingClients','pendingClientRegistrations','clientsByEmail','onlineClients','clientPresence','clientBookings','bookings','registrations','registeredEmails','usedEmails','emailIndex','emails','emailToUid','usersByEmail','nursesByEmail','clientsByEmail','usernames','nurseUsernames','clientUsernames','phones','nursePhones','clientPhones','users','nursingPins','usedPins','jobOffers','chatMessages'];
      for (const r of roots) await db.ref(r).remove().catch(()=>{});
    } catch (e) { console.error('RTDB wipe failed:', e); }
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

// ========== RECOVER ORPHAN AUTH USERS - NEW RULE ==========
// Fix for: Client verifies email, app goes fresh, CEO sees (0), Login says "not registered"
// Called from CEO: FirebaseFunctions.instance.httpsCallable('recoverOrphanAuthUsers').call({})
// NEW RULE:
//  - If Auth emailVerified == true -> Create as APPROVED, canLogin true, status approved. Can login straight, NO CEO.
//  - If Auth emailVerified == false -> Create as PENDING, canLogin false, status pending. Still needs Gmail verify.
//  - Skip CEO + Skip Nurses (if UID already exists in nurses, do NOT create as client)
exports.recoverOrphanAuthUsers = onCall(
  { region: 'us-central1', timeoutSeconds: 540 },
  async (request) => {
    const db = admin.database();
    const fs = admin.firestore();
    let nextPageToken; let recovered = []; let alreadyOk = 0; let approvedNow = 0;
    do {
      const list = await admin.auth().listUsers(1000, nextPageToken);
      for (const u of list.users) {
        const email = String(u.email || '').toLowerCase();
        if (!email) continue;
        if (email === 'joshouapee@gmail.com' || email === 'lovecareglobal@gmail.com') continue;
        // Skip if already has nurse record - never convert nurse to client
        const nurseSnap = await db.ref('nurses/' + u.uid).get();
        if (nurseSnap.exists()) { alreadyOk++; continue; }
        const snap = await db.ref('clients/' + u.uid).get();
        const snap2 = await db.ref('ceoRegistrationCenter/clients/' + u.uid).get();
        if (snap.exists() || snap2.exists()) {
          // Already exists but maybe still Pending while Auth says verified -> auto-approve it now (new rule fix)
          if (u.emailVerified) {
            const fix = { emailVerified: true, verifiedByEmail: true, isApproved: true, approved: true, status: 'approved', approvalStatus: 'approved', canLogin: true, isComplete: true, hasAll4: true, updatedAt: Date.now() };
            await db.ref('clients/' + u.uid).update(fix).catch(()=>{});
            await db.ref('ceoRegistrationCenter/clients/' + u.uid).update(fix).catch(()=>{});
            await db.ref('client_registrations/' + u.uid).update(fix).catch(()=>{});
            await fs.collection('clients').doc(u.uid).set(fix, { merge: true }).catch(()=>{});
            approvedNow++;
          }
          alreadyOk++;
          continue;
        }
        const verified = !!u.emailVerified;
        const name = u.displayName || '';
        const profile = {
          uid: u.uid, id: u.uid, email: email, fullName: name, name: name, username: '', phone: u.phoneNumber || '',
          role: 'client', type: 'client',
          emailVerified: verified, verifiedByEmail: verified,
          // NEW RULE: Verified = Approved, Not verified = Pending
          isApproved: verified, approved: verified,
          status: verified ? 'approved' : 'pending',
          approvalStatus: verified ? 'approved' : 'pending',
          canLogin: verified, isVerified: verified,
          isComplete: verified, hasAll4: verified,
          needsProfile: name === '',
          createdAt: Date.now(), recoveredAt: Date.now(), recoveredBy: 'CEO Recover',
        };
        await db.ref('clients/' + u.uid).set(profile);
        await db.ref('ceoRegistrationCenter/clients/' + u.uid).set(profile);
        await db.ref('client_registrations/' + u.uid).set(profile);
        await fs.collection('clients').doc(u.uid).set({ ...profile, createdAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true }).catch(()=>{});
        if (verified) {
          const emailKey = sanitizeEmailKey(email);
          await db.ref('allowedClients/' + emailKey).set(profile).catch(()=>{});
          await db.ref('allowedClientsByUid/' + u.uid).set(profile).catch(()=>{});
        }
        recovered.push(email + (verified ? ' [VERIFIED->APPROVED]' : ' [PENDING]'));
      }
      nextPageToken = list.pageToken;
    } while (nextPageToken);
    return { ok: true, recovered: recovered.length, alreadyOk, approvedNow, emails: recovered, message: 'Recovered ' + recovered.length + ' missing clients, auto-approved ' + approvedNow + ' verified ones' };
  }
);

// ========== FIX ALL CLIENTS TO NEW RULE ==========
// One-time: Scan all existing RTDB clients, if their Auth says verified, approve them.
// Called from CEO if you want: httpsCallable('fixAllClientsToNewRule').call({})
// Use this for Michael + all old clients wey still show Pending even though dem don verify.
exports.fixAllClientsToNewRule = onCall(
  { region: 'us-central1', timeoutSeconds: 540 },
  async (request) => {
    const db = admin.database();
    const fs = admin.firestore();
    let fixed = 0; let stillPending = 0; let emails = [];
    const snap = await db.ref('clients').get();
    if (!snap.exists()) return { ok: true, fixed: 0, message: 'No clients in RTDB' };
    const val = snap.val();
    for (const uid of Object.keys(val)) {
      try {
        const u = await admin.auth().getUser(uid);
        if (u.emailVerified) {
          const fix = { emailVerified: true, verifiedByEmail: true, isApproved: true, approved: true, status: 'approved', approvalStatus: 'approved', canLogin: true, isComplete: true, hasAll4: true, updatedAt: Date.now() };
          await db.ref('clients/' + uid).update(fix);
          await db.ref('ceoRegistrationCenter/clients/' + uid).update(fix).catch(()=>{});
          await db.ref('client_registrations/' + uid).update(fix).catch(()=>{});
          await fs.collection('clients').doc(uid).set(fix, { merge: true }).catch(()=>{});
          fixed++;
          emails.push(u.email);
        } else {
          stillPending++;
        }
      } catch (_) { stillPending++; }
    }
    return { ok: true, fixed, stillPending, emails, message: 'Auto-approved ' + fixed + ' verified clients, ' + stillPending + ' still pending (not verified)' };
  }
);
