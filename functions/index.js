const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

const MAX_MULTICAST_TOKENS = 500;

function cleanString(value, maxLength) {
  return String(value || '').trim().slice(0, maxLength);
}

function safeExternalLink(value) {
  const raw = cleanString(value, 2048);
  if (!raw) return '';
  try {
    const parsed = new URL(raw);
    return parsed.protocol === 'https:' ? parsed.toString() : '';
  } catch (_) {
    return '';
  }
}

function notificationPayload(message, queueId) {
  return {
    title: cleanString(message.title, 120) || 'Tudo Aqui Macacu',
    body: cleanString(message.description, 1000),
    data: {
      link: safeExternalLink(message.link),
      queueId,
    },
    targetEmail: cleanString(message.targetEmail, 180).toLowerCase(),
  };
}

function chunks(items, size) {
  const result = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

function deviceTokenFromDoc(doc) {
  const token = cleanString(doc.get('token'), 4096);
  return token || cleanString(doc.id, 4096);
}

async function loadTargetDevices(db, targetEmail) {
  if (targetEmail) {
    const users = await db
      .collection('users')
      .where('email', '==', targetEmail)
      .limit(1)
      .get();
    if (users.empty) return [];
    const devices = await users.docs[0].ref
      .collection('devices')
      .where('active', '!=', false)
      .get();
    return devices.docs;
  }

  const devices = await db
    .collectionGroup('devices')
    .where('active', '!=', false)
    .get();
  return devices.docs;
}

function isInvalidTokenError(code) {
  return (
    code === 'messaging/registration-token-not-registered' ||
    code === 'messaging/invalid-registration-token' ||
    code === 'messaging/invalid-argument'
  );
}

exports.deliverPushNotification = onDocumentCreated(
  'push_queue/{queueId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const db = admin.firestore();
    const message = snapshot.data() || {};
    const payload = notificationPayload(message, event.params.queueId);

    if (!payload.body) {
      await snapshot.ref.update({
        status: 'rejected',
        error: 'missing_description',
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.warn('Push rejeitado sem descrição', {
        queueId: event.params.queueId,
      });
      return;
    }

    const deviceDocs = await loadTargetDevices(db, payload.targetEmail);
    const tokenToDoc = new Map();
    for (const doc of deviceDocs) {
      const token = deviceTokenFromDoc(doc);
      if (token) tokenToDoc.set(token, doc);
    }

    const tokens = [...tokenToDoc.keys()];
    let successCount = 0;
    let failureCount = 0;
    let invalidTokens = 0;
    const cleanup = [];

    for (const batch of chunks(tokens, MAX_MULTICAST_TOKENS)) {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
        android: { priority: 'high', notification: { channelId: 'general' } },
      });

      successCount += response.successCount;
      failureCount += response.failureCount;

      response.responses.forEach((result, index) => {
        if (result.success) return;
        const code = result.error && result.error.code;
        const token = batch[index];
        const deviceDoc = tokenToDoc.get(token);
        if (!deviceDoc) return;

        if (isInvalidTokenError(code)) {
          invalidTokens += 1;
          cleanup.push(deviceDoc.ref.delete());
        } else {
          cleanup.push(
            deviceDoc.ref.set(
              {
                active: false,
                lastError: cleanString(code || 'unknown', 120),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            ),
          );
        }
      });
    }

    await Promise.allSettled(cleanup);
    await snapshot.ref.update({
      status: 'sent',
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      recipients: tokens.length,
      successCount,
      failureCount,
      invalidTokens,
    });

    logger.info('Push processado', {
      queueId: event.params.queueId,
      recipients: tokens.length,
      successCount,
      failureCount,
      invalidTokens,
    });
  },
);
