'use strict';
const { localOnly } = require('./business_search');

function notificationTarget(message) {
  if (Object.hasOwn(message, 'targetUid')) {
    if (typeof message.targetUid !== 'string' || !message.targetUid.length ||
        message.targetUid.length > 128 || message.targetUid.includes('/')) {
      throw new Error('Invalid notification recipient');
    }
    // An explicitly addressed message must never become a broadcast.
    return { targetUid: message.targetUid, targetEmail: '' };
  }
  if (Object.hasOwn(message, 'targetEmail') && typeof message.targetEmail !== 'string') {
    throw new Error('Invalid legacy notification recipient');
  }
  return { targetUid: '', targetEmail: (message.targetEmail || '').trim().toLowerCase() };
}

async function loadTargetDevices(db, target) {
  let userRef;
  if (target.targetUid) {
    userRef = db.collection('users').doc(target.targetUid);
  } else if (target.targetEmail) {
    // Compatibility for old PRIVATE queue entries. Never publish these emails.
    const users = await db.collection('users').where('email', '==', target.targetEmail).limit(2).get();
    if (users.docs.length !== 1) return [];
    userRef = users.docs[0].ref;
  }
  if (userRef) {
    return (await userRef.collection('devices').where('active', '!=', false).get()).docs;
  }
  return (await db.collectionGroup('devices').where('active', '!=', false).get()).docs;
}

async function sendPushBatch(messaging, request) {
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    if (!localOnly()) throw new Error('Notification emulator requires demo and loopback');
    // FCM has no emulator: validate recipient selection locally without any
    // external delivery. This is a simulation, not proof of real FCM delivery.
    return { successCount: request.tokens.length, failureCount: 0,
      responses: request.tokens.map(() => ({ success: true })) };
  }
  return messaging.sendEachForMulticast(request);
}
module.exports = { notificationTarget, loadTargetDevices, sendPushBatch };
