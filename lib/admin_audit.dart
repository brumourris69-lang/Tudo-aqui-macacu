import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Mantém um histórico simples de operações comerciais feitas pelo administrador.
/// Falhas de auditoria não bloqueiam a ação já confirmada no painel.
Future<void> recordAdminAudit({
  required String action,
  required String collection,
  required String documentId,
  String? label,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    await FirebaseFirestore.instance.collection('admin_audit_logs').add({
      'action': action,
      'collection': collection,
      'documentId': documentId,
      'label': label ?? '',
      'adminUid': user.uid,
      'adminEmail': user.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  } on FirebaseException catch (error) {
    debugPrint('Auditoria administrativa não registrada: ${error.code}');
  }
}
