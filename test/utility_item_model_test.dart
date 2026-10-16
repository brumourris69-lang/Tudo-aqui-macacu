import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/utilities/models/utility_item.dart';

void main() {
  test('UtilityItem.fromData preserva documento completo', () {
    final item = UtilityItem.fromData('bus-doc', {
      'name': 'Ônibus',
      'iconKey': 'bus',
      'description': 'Horários e linhas',
      'category': 'Mobilidade',
      'destinationType': 'internal',
      'destination': 'transport',
      'order': 10,
      'active': false,
    });

    expect(item.id, 'bus-doc');
    expect(item.name, 'Ônibus');
    expect(item.iconKey, 'bus');
    expect(item.description, 'Horários e linhas');
    expect(item.category, 'Mobilidade');
    expect(item.destinationType, 'internal');
    expect(item.destination, 'transport');
    expect(item.order, 10);
    expect(item.active, isFalse);
    expect(item.toMap(), containsPair('name', 'Ônibus'));
    expect(item.toMap(), containsPair('iconKey', 'bus'));
    expect(item.toMap(), containsPair('destination', 'transport'));
    expect(item.toMap(), containsPair('category', 'Mobilidade'));
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

  test('validates destinations before they can be published', () {
    expect(
      validateUtilityConfiguration(
        name: 'Prefeitura',
        description: 'Atendimento',
        destinationType: 'internal',
        destination: 'cityHall',
        order: '10',
      ),
      isNull,
    );
    expect(
      validateUtilityConfiguration(
        name: 'Site',
        description: '',
        destinationType: 'url',
        destination: 'https://prefeitura.example.gov.br',
        order: '10',
      ),
      isNull,
    );
  });

  test('rejects unsafe or malformed utility destinations', () {
    expect(
      validateUtilityConfiguration(
        name: 'Site',
        description: '',
        destinationType: 'url',
        destination: 'javascript:alert(1)',
        order: '10',
      ),
      isNotNull,
    );
    expect(
      validateUtilityConfiguration(
        name: 'Telefone',
        description: '',
        destinationType: 'phone',
        destination: 'abc',
        order: '10',
      ),
      isNotNull,
    );
    expect(
      validateUtilityConfiguration(
        name: 'Telefone',
        description: '',
        destinationType: 'phone',
        destination: 'abc12345678',
        order: '10',
      ),
      isNotNull,
    );
    expect(
      validateUtilityConfiguration(
        name: 'Atalho',
        description: '',
        destinationType: 'internal',
        destination: 'unknown-page',
        order: '10',
      ),
      isNotNull,
    );
  });

  test('describes the exact accepted map URL format', () {
    expect(
      validateUtilityConfiguration(
        name: 'Mapa',
        description: '',
        destinationType: 'map',
        destination: 'javascript:alert(1)',
        order: '10',
      ),
      'Informe uma URL HTTPS válida ou URI geo com caminho preenchido.',
    );
  });

  test('rejects legacy destinations without a supported route handler', () {
    expect(isSupportedUtilityDestination('internal', 'cityHall'), isTrue);
    expect(isSupportedUtilityDestination('internal', 'unknown-page'), isFalse);
    expect(isSupportedUtilityDestination('unknown', 'anything'), isFalse);
    expect(
      isSupportedUtilityDestination('url', 'http://insecure.example'),
      isFalse,
    );
  });

  test('requires a nonempty name and valid explicit order', () {
    expect(
      validateUtilityConfiguration(
        name: '  ',
        description: '',
        destinationType: 'internal',
        destination: 'cityHall',
        order: 'abc',
      ),
      isNotNull,
    );
  });

  test('limits category labels to keep utility cards and groups readable', () {
    expect(
      validateUtilityConfiguration(
        name: 'Serviço',
        description: '',
        destinationType: 'internal',
        destination: 'cityHall',
        order: '10',
        category: List.filled(61, 'x').join(),
      ),
      isNotNull,
    );
  });

  test('groups utilities by configured category without inventing content', () {
    const items = [
      UtilityItem(
        id: 'bus',
        name: 'Ônibus',
        iconKey: 'bus',
        description: '',
        destinationType: 'internal',
        destination: 'transport',
        order: 10,
        category: 'Mobilidade',
      ),
      UtilityItem(
        id: 'trash',
        name: 'Coleta',
        iconKey: 'trash',
        description: '',
        destinationType: 'internal',
        destination: 'trash',
        order: 20,
        category: 'Mobilidade',
      ),
      UtilityItem(
        id: 'phones',
        name: 'Telefones',
        iconKey: 'phone',
        description: '',
        destinationType: 'internal',
        destination: 'usefulPhones',
        order: 30,
      ),
    ];

    final groups = groupUtilitiesByCategory(items);

    expect(groups.keys, ['Mobilidade', 'Geral']);
    expect(groups['Mobilidade']!.map((item) => item.id), ['bus', 'trash']);
    expect(groups['Geral']!.single.id, 'phones');
  });
}
