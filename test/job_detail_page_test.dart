import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/jobs/models/public_job.dart';
import 'package:tudo_aqui_macacu/features/jobs/pages/job_detail_page.dart';

void main() {
  testWidgets('job detail retries errors and renders only public job fields', (
    tester,
  ) async {
    final first = Completer<PublicJob?>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: JobDetailPage(
          jobId: 'job-test-id',
          resolveJob: (id) {
            expect(id, 'job-test-id');
            calls++;
            if (calls == 1) return first.future;
            return Future.value(
              const PublicJob(
                id: 'job-test-id',
                title: 'Vaga fictícia',
                description: 'Descrição completa.',
                company: 'Empresa Exemplo',
              ),
            );
          },
        ),
      ),
    );
    first.completeError(StateError('erro interno'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar esta vaga.'), findsOneWidget);
    expect(find.textContaining('erro interno'), findsNothing);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Vaga fictícia'), findsOneWidget);
    expect(find.text('Descrição completa.'), findsOneWidget);
    expect(find.text('Empresa Exemplo'), findsOneWidget);
    expect(find.textContaining('contato'), findsNothing);
  });
}
