import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/utilities/models/utility_item.dart';

void main() {
  test('UtilityItem.fromData preserva documento completo', () {
    final item = UtilityItem.fromData('bus-doc', {
      'name': 'Ônibus',
      'iconKey': 'bus',
      'description': 'Horários e linhas',
      'destinationType': 'internal',
      'destination': 'transport',
      'order': 10,
      'active': false,
    });

    expect(item.id, 'bus-doc');
    expect(item.name, 'Ônibus');
    expect(item.iconKey, 'bus');
    expect(item.description, 'Horários e linhas');
    expect(item.destinationType, 'internal');
    expect(item.destination, 'transport');
    expect(item.order, 10);
    expect(item.active, isFalse);
    expect(item.toMap(), containsPair('name', 'Ônibus'));
    expect(item.toMap(), containsPair('iconKey', 'bus'));
    expect(item.toMap(), containsPair('destination', 'transport'));
  });

  test('UtilityItem.fromData usa fallbacks quando campos opcionais faltam', () {
    final item = UtilityItem.fromData('pharmacyDuty', {
      'title': 'Farmácia de plantão',
      'description': 'Veja a escala atual',
      'published': false,
      'order': '45',
    });

    expect(item.id, 'pharmacyDuty');
    expect(item.name, 'Farmácia de plantão');
    expect(item.iconKey, 'pharmacy');
    expect(item.description, 'Veja a escala atual');
    expect(item.destinationType, 'internal');
    expect(item.destination, 'pharmacyDuty');
    expect(item.order, 45);
    expect(item.active, isFalse);
  });

  test('UtilityItem.fromData infere destino legado por link', () {
    final item = UtilityItem.fromData('mapa', {
      'name': 'Mapa da cidade',
      'description': 'Localize serviços',
      'link': 'https://maps.google.com/example',
      'destinationType': 'url',
    });

    expect(item.name, 'Mapa da cidade');
    expect(item.iconKey, 'publicPlace');
    expect(item.destinationType, 'url');
    expect(item.destination, 'https://maps.google.com/example');
    expect(item.order, 0);
    expect(item.active, isTrue);
  });

  test('UtilityItem.fromData usa services como fallback de icone', () {
    final item = UtilityItem.fromData('generico', {
      'name': 'Serviço genérico',
      'iconKey': 'icone-inexistente',
    });

    expect(item.iconKey, 'services');
    expect(item.destination, 'generico');
    expect(item.order, 0);
    expect(item.active, isTrue);
  });
}
