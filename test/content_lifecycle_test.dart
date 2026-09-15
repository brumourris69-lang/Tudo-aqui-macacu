import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  test('conteúdo sem data de expiração permanece ativo', () {
    expect(isActiveContent(<String, dynamic>{}), isTrue);
  });

  test('conteúdo expirado não aparece para o público', () {
    expect(
      isActiveContent(<String, dynamic>{
        'expiresAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
      }),
      isFalse,
    );
  });

  test('conteúdo com expiração futura permanece visível', () {
    expect(
      isActiveContent(<String, dynamic>{
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
      }),
      isTrue,
    );
  });
}
