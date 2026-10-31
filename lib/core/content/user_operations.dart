import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/beta_environment.dart';
import '../config/firestore_collections.dart';
import 'secure_backend.dart';

/// Authorship, schema, dates, quotas and deduplication belong to the backend.
Future<void> writeUserOperation(
  String operation,
  Map<String, dynamic> payload,
) async {
  if (BetaEnvironment.enabled) {
    BetaEnvironment.requireReady();
    BetaEnvironment.requireFirebaseProject(
      FirebaseFirestore.instance.app.options.projectId,
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Entre na sua conta para salvar este conteúdo.');
    }
    final favorites = FirebaseFirestore.instance
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
          ? const {'name', 'contact', 'message'}
          : const {'name', 'contact', 'details'};
      if (payload.keys.any((key) => !allowed.contains(key))) {
        throw const FormatException('Solicitação inválida.');
      }
      final name = payload['name'];
      final contact = payload['contact'] ?? '';
      final body = payload[isContact ? 'message' : 'details'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.length > 120 ||
          contact is! String ||
          contact.length > 200 ||
          body is! String ||
          body.trim().isEmpty ||
          body.length > (isContact ? 2000 : 4000)) {
        throw const FormatException('Solicitação inválida.');
      }
      await FirebaseFirestore.instance
          .collection(isContact ? 'contact_messages' : 'business_proposals')
          .add({
            'uid': user.uid,
            'name': name.trim(),
            'contact': contact.trim(),
            (isContact ? 'message' : 'details'): body.trim(),
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
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
      final db = FirebaseFirestore.instance;
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
      final db = FirebaseFirestore.instance;
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

  await SecureBackend.invoke('submitUserOperation', {
    'operation': operation,
    'payload': payload,
  });
}
