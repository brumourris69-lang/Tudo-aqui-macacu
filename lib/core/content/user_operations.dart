import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../config/beta_environment.dart';
import '../config/firestore_collections.dart';
import '../config/mvp_launch_features.dart';
import '../config/spark_public_catalog_environment.dart';
import '../../features/contact/contact_message_validation.dart';
import 'secure_backend.dart';

const contactMessagesPerRollingDay = 3;

class ContactMessageDailyLimitReached implements Exception {
  const ContactMessageDailyLimitReached();
}

/// Spark writes are owner-scoped and quota-checked atomically by Firestore Rules.
/// Hosted operations remain server-authored by the secure callable backend.
Future<void> writeUserOperation(
  String operation,
  Map<String, dynamic> payload,
) async {
  if (BetaEnvironment.enabled && SparkPublicCatalogEnvironment.enabled) {
    throw StateError('As configurações Beta e Spark não podem coexistir.');
  }
  if (!MvpLaunchFeatures.isUserOperationEnabled(operation)) {
    // Telemetry and push-token bookkeeping are intentionally inert in the
    // Spark MVP. Deferred interactive writes fail before any backend call.
    if (operation == 'metric' ||
        operation == 'device' ||
        operation == 'removeDevice') {
      return;
    }
    throw StateError('Esta operação não está disponível no MVP 1.0.');
  }

  final sparkDistribution = SparkPublicCatalogEnvironment.enabled;
  if (BetaEnvironment.enabled || sparkDistribution) {
    final db = FirebaseFirestore.instance;
    if (sparkDistribution && !BetaEnvironment.enabled) {
      final authOptions = FirebaseAuth.instance.app.options;
      final firestoreOptions = db.app.options;
      SparkPublicCatalogEnvironment.requireReady(
        actualProjectId: firestoreOptions.projectId,
      );
      if (authOptions.projectId != firestoreOptions.projectId ||
          authOptions.appId.isEmpty ||
          authOptions.appId != firestoreOptions.appId) {
        throw StateError('A identidade Firebase do usuário não corresponde.');
      }
    } else {
      BetaEnvironment.requireReady();
      BetaEnvironment.requireFirebaseProject(db.app.options.projectId);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Entre na sua conta para salvar este conteúdo.');
    }
    final favorites = db
        .collection(FirestoreCollections.users)
        .doc(user.uid)
        .collection(FirestoreCollections.favorites);

    if (operation == 'unfavorite') {
      final id = payload['id'];
      if (payload.keys.any((key) => key != 'id') ||
          id is! String ||
          id.isEmpty ||
          id.length > 200 ||
          id.contains('/')) {
        throw const FormatException('Favorito inválido.');
      }
      await favorites.doc(id).delete();
      return;
    }

    if (operation == 'favorite') {
      final id = payload['id'];
      final name = payload['name'];
      final type = payload['type'];
      final targetId = payload['targetId'];
      if (payload.keys.toSet().difference(const {
            'id',
            'name',
            'type',
            'targetId',
          }).isNotEmpty ||
          id is! String ||
          id.isEmpty ||
          id.length > 200 ||
          id.contains('/') ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 160 ||
          type is! String ||
          !const {'business', 'tourism', 'event'}.contains(type) ||
          targetId is! String ||
          targetId.isEmpty ||
          targetId.length > 128 ||
          targetId.contains('/') ||
          id != '$type::$targetId') {
        throw const FormatException('Favorito inválido.');
      }
      final reference = favorites.doc(id);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final existing = await transaction.get(reference);
        if (existing.exists) {
          transaction.update(reference, {
            'name': name.trim(),
            'type': type,
            'targetId': targetId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(reference, {
            'id': id,
            'name': name.trim(),
            'type': type,
            'targetId': targetId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
      return;
    }

    if (operation == 'contact' || operation == 'proposal') {
      final isContact = operation == 'contact';
      final allowed = isContact
          ? const {'contact', 'message'}
          : const {'name', 'contact', 'details'};
      if (payload.keys.any((key) => !allowed.contains(key))) {
        throw const FormatException('Solicitação inválida.');
      }
      final name = payload['name'];
      final contact = payload['contact'] ?? '';
      final body = payload[isContact ? 'message' : 'details'];
      if ((!isContact &&
              (name is! String || name.trim().isEmpty || name.length > 120)) ||
          contact is! String ||
          contact.length > 200 ||
          body is! String ||
          body.trim().isEmpty ||
          body.length > (isContact ? 2000 : 4000)) {
        throw const FormatException('Solicitação inválida.');
      }
      if (isContact) {
        final phone = normalizeBrazilianPhone(contact);
        if (!isValidBrazilianPhone(phone) ||
            user.email?.trim().isNotEmpty != true) {
          throw const FormatException('Solicitação inválida.');
        }
        final quota = db
            .collection('users')
            .doc(user.uid)
            .collection('contact_message_limits')
            .doc('current');
        final messageRef = db.collection('contact_messages').doc();
        await db.runTransaction((transaction) async {
          final snapshot = await transaction.get(quota);
          final current = snapshot.data();
          final now = DateTime.now().toUtc();
          final periodStart = current?['periodStartedAt'];
          final count = current?['count'];
          final activePeriod =
              periodStart is Timestamp &&
              now.isBefore(
                periodStart.toDate().toUtc().add(const Duration(hours: 24)),
              );
          if (activePeriod &&
              count is int &&
              count >= contactMessagesPerRollingDay) {
            throw const ContactMessageDailyLimitReached();
          }
          final nextCount = activePeriod && count is int ? count + 1 : 1;
          final nextPeriod = activePeriod
              ? periodStart
              : FieldValue.serverTimestamp();
          transaction.set(quota, {
            'uid': user.uid,
            'count': nextCount,
            'periodStartedAt': nextPeriod,
            'lastMessageId': messageRef.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(messageRef, {
            'uid': user.uid,
            'email': user.email!.trim(),
            'contact': phone,
            'message': body.trim(),
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'quotaPeriodStartedAt': nextPeriod,
          });
        });
      } else {
        await db.collection('business_proposals').add({
          'uid': user.uid,
          'name': name.trim(),
          'contact': contact.trim(),
          'details': body.trim(),
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return;
    }

    if (operation == 'review') {
      final businessId = payload['businessId'];
      final message = payload['message'];
      final stars = payload['stars'];
      if (payload.keys.toSet().difference(const {
            'businessId',
            'message',
            'stars',
          }).isNotEmpty ||
          businessId is! String ||
          businessId.isEmpty ||
          businessId.contains('/') ||
          message is! String ||
          message.trim().isEmpty ||
          message.length > 2000 ||
          stars is! int ||
          stars < 1 ||
          stars > 5) {
        throw const FormatException('Avaliação inválida.');
      }
      final publicBusiness = await db
          .collection('beta_public_catalog')
          .doc('establishments')
          .collection('items')
          .doc(businessId)
          .get();
      final publicData = publicBusiness.data()?['publicData'];
      if (publicData is! Map ||
          publicBusiness.data()?['visibility'] != 'public') {
        throw StateError(
          'O estabelecimento não está disponível para avaliação.',
        );
      }
      await db.collection('reviews').add({
        'uid': user.uid,
        'businessId': businessId,
        'business': (publicData['name'] ?? publicData['title'] ?? '')
            .toString(),
        'message': message.trim(),
        'stars': stars,
        'status': 'pending',
        'published': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    if (operation == 'vote') {
      final pollId = payload['pollId'];
      final option = payload['option'];
      if (payload.keys.toSet().difference(const {
            'pollId',
            'option',
          }).isNotEmpty ||
          pollId is! String ||
          pollId.isEmpty ||
          pollId.contains('/') ||
          option is! String ||
          option.trim().isEmpty ||
          option.length > 160) {
        throw const FormatException('Voto inválido.');
      }
      final vote = db
          .collection('polls')
          .doc(pollId)
          .collection('votes')
          .doc(user.uid);
      await db.runTransaction((transaction) async {
        final existing = await transaction.get(vote);
        if (existing.exists) throw StateError('Você já votou nesta enquete.');
        transaction.set(vote, {
          'uid': user.uid,
          'option': option.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      return;
    }

    if (operation == 'metric' ||
        operation == 'device' ||
        operation == 'removeDevice') {
      // Spark Beta has no push-token registry or paid analytics callable.
      // Event reminders are local to the device and need no user operation.
      return;
    }

    throw StateError(
      'Esta operação exige um serviço hospedado e não está disponível no Beta gratuito.',
    );
  }

  try {
    await SecureBackend.invoke('submitUserOperation', {
      'operation': operation,
      'payload': payload,
    });
  } on FirebaseFunctionsException catch (error) {
    if (operation == 'contact' && error.code == 'resource-exhausted') {
      throw const ContactMessageDailyLimitReached();
    }
    rethrow;
  }
}
