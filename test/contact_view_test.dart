import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/user_operations.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

class _ContactUser implements User {
  @override
  bool get isAnonymous => false;

  @override
  String get uid => 'contact-test-user';

  @override
  String? get email => 'morador@example.invalid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'signed-in form identifies the account and asks only phone/message',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ContactView(authChanges: Stream.value(_ContactUser())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('morador@example.invalid'), findsOneWidget);
      expect(find.text('E-mail da conta'), findsOneWidget);
      expect(find.text('Nome'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Telefone com DDD'), findsOneWidget);
      expect(find.text('Mensagem'), findsOneWidget);
      expect(find.textContaining('até 3 mensagens'), findsOneWidget);
    },
  );

  testWidgets('validates phone and message then submits only those fields', (
    tester,
  ) async {
    String? submittedPhone;
    String? submittedMessage;
    final submitted = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: ContactView(
          authChanges: Stream.value(_ContactUser()),
          submitMessageForTesting: (phone, message) async {
            submittedPhone = phone;
            submittedMessage = message;
            submitted.complete();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Enviar mensagem'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ContactView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Enviar mensagem'));
    await tester.pumpAndSettle();
    expect(find.text('Digite um telefone válido com DDD.'), findsOneWidget);
    expect(find.text('Digite sua mensagem antes de enviar.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), '(21) 91234-5678');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      '  Sugestão de teste  ',
    );
    await tester.tap(find.text('Enviar mensagem'));
    await tester.pump();
    await submitted.future;

    expect(submittedPhone, '21912345678');
    expect(submittedMessage, 'Sugestão de teste');
  });

  testWidgets('shows a clear message when the account daily limit is reached', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ContactView(
          authChanges: Stream.value(_ContactUser()),
          submitMessageForTesting: (_, _) async =>
              throw const ContactMessageDailyLimitReached(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '21912345678');
    await tester.enterText(find.byType(TextFormField).at(1), 'Mensagem teste');
    await tester.scrollUntilVisible(
      find.text('Enviar mensagem'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ContactView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Enviar mensagem'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Você atingiu o limite diário de 3 mensagens. Tente novamente mais tarde.',
      ),
      findsOneWidget,
    );
  });
}
