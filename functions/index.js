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
