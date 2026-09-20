const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

exports.deliverPushNotification = onDocumentCreated('push_queue/{queueId}', async (event) => {
  const message = event.data.data();
  const db = admin.firestore();
  const title = String(message.title || 'Tudo Aqui Macacu').slice(0, 120);
  const body = String(message.description || '').slice(0, 1000);
  const data = { link: String(message.link || ''), queueId: event.params.queueId };
  let deviceDocs = [];

  if (message.targetEmail) {
    const users = await db.collection('users').where('email', '==', message.targetEmail).limit(1).get();
    if (!users.empty) {
      const devices = await users.docs[0].ref.collection('devices').where('active', '!=', false).get();
      deviceDocs = devices.docs;
    }
  } else {
    const devices = await db.collectionGroup('devices').where('active', '!=', false).get();
    deviceDocs = devices.docs;
  }

  const tokens = deviceDocs.map((doc) => doc.id).filter(Boolean);
  let successCount = 0;
  let failureCount = 0;
  let invalidTokens = 0;

  if (tokens.length) {
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data,
      android: { priority: 'high', notification: { channelId: 'general' } },
    });
    successCount = response.successCount;
    failureCount = response.failureCount;
    const cleanup = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error && result.error.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/invalid-argument'
      ) {
        invalidTokens += 1;
        cleanup.push(deviceDocs[index].ref.delete());
      } else {
        cleanup.push(deviceDocs[index].ref.set({ active: false, lastError: code || 'unknown', updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true }));
      }
    });
    await Promise.allSettled(cleanup);
    logger.info('Push entregue', { successCount, failureCount, invalidTokens });
  }

  await event.data.ref.update({
    status: 'sent',
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    recipients: tokens.length,
    successCount,
    failureCount,
    invalidTokens,
  });
});
