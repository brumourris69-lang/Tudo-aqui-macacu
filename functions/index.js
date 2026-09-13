const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

exports.deliverPushNotification = onDocumentCreated('push_queue/{queueId}', async (event) => {
  const message = event.data.data();
  const db = admin.firestore();
  const title = message.title || 'Tudo Aqui Macacu';
  const body = message.description || '';
  const data = { link: message.link || '', queueId: event.params.queueId };
  let tokens = [];

  if (message.targetEmail) {
    const users = await db.collection('users').where('email', '==', message.targetEmail).limit(1).get();
    if (!users.empty) {
      const devices = await users.docs[0].ref.collection('devices').get();
      tokens = devices.docs.map((doc) => doc.id);
    }
  } else {
    const devices = await db.collectionGroup('devices').get();
    tokens = devices.docs.map((doc) => doc.id);
  }

  if (tokens.length) {
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data,
      android: { priority: 'high', notification: { channelId: 'general' } },
    });
    logger.info('Push entregue', { successCount: response.successCount, failureCount: response.failureCount });
  }
  await event.data.ref.update({ status: 'sent', sentAt: admin.firestore.FieldValue.serverTimestamp(), recipients: tokens.length });
});
