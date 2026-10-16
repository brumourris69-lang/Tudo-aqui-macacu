import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';

void main() {
  test('decodes only the public event projection and optional fields', () {
    final event = PublicEvent.fromMap({
      'id': 'event-demo-1',
      'title': 'Festival comunitário',
      'description': 'Descrição completa.',
      'category': 'Cultura',
      'eventDate': '25/10/2026 às 19h',
      'location': 'Praça de Teste',
      'imageUrl': 'https://images.example.invalid/event.jpg',
      'ownerEmail': 'private@example.invalid',
      'privateNotes': 'not returned by the public callable',
    });

    expect(event.id, 'event-demo-1');
    expect(event.title, 'Festival comunitário');
    expect(event.description, 'Descrição completa.');
    expect(event.category, 'Cultura');
    expect(event.eventDate, '25/10/2026 às 19h');
    expect(event.location, 'Praça de Teste');
    expect(event.imageUrl, 'https://images.example.invalid/event.jpg');
    expect(event.toString(), isNot(contains('private@example.invalid')));
  });

  test('missing optional values stay empty and timestamp is formatted', () {
    final event = PublicEvent.fromMap({
      'id': 'event-demo-2',
      'title': 'Encontro de Teste',
      'eventDate': {
        '_publicTimestamp': [1792954800, 0],
      },
    });

    expect(event.description, isEmpty);
    expect(event.category, isEmpty);
    expect(event.location, isEmpty);
    expect(event.imageUrl, isEmpty);
    expect(event.eventDate, isNotEmpty);
  });

  test(
    'rejects malformed identifiers, required fields, and public field types',
    () {
      for (final value in [
        <String, Object?>{'id': '', 'title': 'Evento'},
        <String, Object?>{'id': 'events/private', 'title': 'Evento'},
        <String, Object?>{'id': 'event-1', 'title': ''},
        <String, Object?>{'id': 'event-1', 'title': 'Evento', 'location': 5},
        <String, Object?>{'id': 'event-1', 'title': 'Evento', 'eventDate': 123},
        <String, Object?>{
          'id': 'event-1',
          'title': 'Evento',
          'eventDate': {
            '_publicTimestamp': [1, 'invalid'],
          },
        },
      ]) {
        expect(() => PublicEvent.fromMap(value), throwsFormatException);
      }
    },
  );
}
