import 'package:cloud_firestore/cloud_firestore.dart';

const utilitySpriteMap = <String, int>{
  'business': 0,
  'cityHall': 0,
  'cityhall': 0,
  'prefeitura': 0,
  'publicPlaces': 0,
  'publicplaces': 0,
  'publicPlace': 0,
  'publicplace': 0,
  'places': 0,
  'bus': 10,
  'transport': 10,
  'transporte': 10,
  'onibus': 10,
  'ônibus': 10,
  'trash': 17,
  'coleta': 17,
  'lixo': 17,
  'garbage': 17,
  'water': 5,
  'agua': 5,
  'água': 5,
  'energy': 2,
  'energia': 2,
  'coupons': 16,
  'coupon': 16,
  'cupons': 16,
  'alerts': 17,
  'alert': 17,
  'avisos': 17,
  'events': 7,
  'event': 7,
  'eventos': 7,
  'tourism': 5,
  'turismo': 5,
  'map': 5,
  'mapa': 5,
  'news': 6,
  'noticias': 6,
  'notícias': 6,
  'polls': 17,
  'enquetes': 17,
  'health': 8,
  'saude': 8,
  'saúde': 8,
  'pharmacy': 8,
  'pharmacyDuty': 8,
  'pharmacyduty': 8,
  'farmacia': 8,
  'farmácia': 8,
  'plantao': 8,
  'plantão': 8,
  'emergency': 8,
  'emergencia': 8,
  'emergência': 8,
  'resolver': 17,
  'phone': 17,
  'phones': 17,
  'telefone': 17,
  'telefones': 17,
  'usefulPhones': 17,
  'usefulphones': 17,
  'whatsapp': 17,
  'link': 17,
  'services': 2,
  'servicos': 2,
  'serviços': 2,
};

const utilitySemanticIconKeys = <String>{
  'bus',
  'trash',
  'cityHall',
  'water',
  'energy',
  'waterEnergy',
  'coupons',
  'alerts',
  'events',
  'tourism',
  'map',
  'news',
  'polls',
  'business',
  'health',
  'pharmacy',
  'emergency',
  'resolver',
  'publicPlace',
  'phone',
  'whatsapp',
  'link',
  'services',
};

const supportedUtilityDestinationTypes = [
  'internal',
  'url',
  'phone',
  'whatsapp',
  'map',
];

const supportedUtilityInternalPages = <String, String>{
  'waterEnergy': 'Conta de Água e Energia',
  'transport': 'Ônibus e transporte',
  'trash': 'Coleta de lixo',
  'usefulPhones': 'Telefones úteis',
  'coupons': 'Cupons exclusivos',
  'alerts': 'Alertas da cidade',
  'pharmacyDuty': 'Farmácia de plantão',
  'emergency': 'Emergência',
  'resolver': 'Onde Resolver?',
  'publicPlaces': 'Locais públicos',
  'events': 'Agenda com lembrete',
  'tourism': 'Roteiros turísticos',
  'map': 'Mapa de Macacu',
  'news': 'Notícias locais',
  'polls': 'Enquetes da cidade',
  'businessProposal': 'Indique uma empresa',
  'health': 'Saúde',
  'healthContent': 'Conteúdos de saúde',
  'cityHall': 'Prefeitura',
};

/// Returns a user-facing validation error, or null when the utility can be
/// stored and its destination can be opened using the supported safe handlers.
String? validateUtilityConfiguration({
  required String name,
  required String description,
  required String destinationType,
  required String destination,
  required String order,
  String category = '',
}) {
  final cleanName = name.trim();
  final cleanDestination = destination.trim();
  if (cleanName.isEmpty) return 'Informe o nome da utilidade.';
  if (cleanName.length > 100) return 'O nome deve ter até 100 caracteres.';
  if (description.trim().length > 240) {
    return 'A descrição deve ter até 240 caracteres.';
  }
  if (category.trim().length > 60) {
    return 'A categoria deve ter até 60 caracteres.';
  }
  if (!supportedUtilityDestinationTypes.contains(destinationType)) {
    return 'Selecione um tipo de destino válido.';
  }
  if (!isSupportedUtilityDestination(destinationType, cleanDestination)) {
    if (destinationType == 'internal') {
      return 'Selecione uma página interna disponível.';
    }
    return switch (destinationType) {
      'url' => 'Informe um endereço HTTPS válido.',
      'phone' => 'Informe um telefone válido.',
      'whatsapp' => 'Informe um telefone ou link wa.me válido.',
      'map' =>
        'Informe uma URL HTTPS válida ou URI geo com caminho preenchido.',
      _ => 'Informe um destino válido.',
    };
  }
  final parsedOrder = int.tryParse(order.trim());
  if (parsedOrder == null || parsedOrder < 0 || parsedOrder > 99999) {
    return 'A ordem deve ser um número entre 0 e 99999.';
  }
  return null;
}

bool isSupportedUtilityDestination(String type, String value) {
  if (type == 'internal') {
    return supportedUtilityInternalPages.containsKey(value);
  }
  if (!supportedUtilityDestinationTypes.contains(type)) return false;
  return _isValidUtilityExternalDestination(type, value);
}

bool _isValidUtilityExternalDestination(String type, String value) {
  if (type == 'phone' || type == 'whatsapp' && !value.contains('://')) {
    if (!RegExp(r'^\+?[\d\s().-]+$').hasMatch(value)) return false;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8 && digits.length <= 15;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.userInfo.isNotEmpty) return false;
  if (type == 'whatsapp') {
    return uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'wa.me' &&
        RegExp(r'^/\d{8,15}$').hasMatch(uri.path) &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }
  if (type == 'map' && uri.scheme == 'geo') return uri.path.trim().isNotEmpty;
  return uri.scheme == 'https' && uri.host.trim().isNotEmpty;
}

String normalizeUtilityKey(String key) =>
    key.trim().isEmpty ? 'services' : key.trim();

int utilitySprite(String key) =>
    utilitySpriteMap[normalizeUtilityKey(key)] ??
    utilitySpriteMap[normalizeUtilityKey(key).toLowerCase()] ??
    2;

typedef _UtilityInferenceRule = ({
  List<String> words,
  String icon,
  String destination,
});

const _utilityInferenceRules = <_UtilityInferenceRule>[
  (
    words: ['ônibus', 'onibus', 'transporte'],
    icon: 'bus',
    destination: 'transport',
  ),
  (words: ['coleta', 'lixo'], icon: 'trash', destination: 'trash'),
  (words: ['telefone', 'contato'], icon: 'phone', destination: 'usefulPhones'),
  (
    words: ['farm', 'plantão', 'plantao'],
    icon: 'pharmacy',
    destination: 'pharmacyDuty',
  ),
  (
    words: ['emerg', 'samu', 'bombeiro'],
    icon: 'emergency',
    destination: 'emergency',
  ),
  (
    words: ['resolver', 'secretaria', 'documento'],
    icon: 'resolver',
    destination: 'resolver',
  ),
  (words: ['prefeitura'], icon: 'cityHall', destination: 'cityHall'),
  (words: ['água', 'agua'], icon: 'water', destination: 'water'),
  (words: ['energia', 'luz'], icon: 'energy', destination: 'energy'),
  (
    words: ['local', 'públic', 'public'],
    icon: 'publicPlace',
    destination: 'publicPlaces',
  ),
  (
    words: ['turismo', 'cachoeira', 'mapa'],
    icon: 'tourism',
    destination: 'tourism',
  ),
  (words: ['evento', 'agenda'], icon: 'events', destination: 'events'),
  (words: ['notícia', 'noticia'], icon: 'news', destination: 'news'),
  (words: ['saúde', 'saude', 'posto'], icon: 'health', destination: 'health'),
  (words: ['cupom', 'promo'], icon: 'coupons', destination: 'coupons'),
];

_UtilityInferenceRule? _utilityInferenceFor(String text) {
  for (final rule in _utilityInferenceRules) {
    if (rule.words.any(text.contains)) return rule;
  }
  return null;
}

String inferUtilityIconKey(Map<String, dynamic> data, String id) {
  final explicit = (data['iconKey'] ?? '').toString().trim();
  if (utilitySpriteMap.containsKey(explicit) ||
      utilitySemanticIconKeys.contains(explicit)) {
    return explicit;
  }
  final text =
      '${data['name'] ?? data['title'] ?? ''} ${data['description'] ?? ''} ${data['destination'] ?? ''} $id'
          .toLowerCase();
  return _utilityInferenceFor(text)?.icon ?? 'services';
}

String inferUtilityDestination(Map<String, dynamic> data, String id) {
  final explicit = (data['destination'] ?? data['link'] ?? '')
      .toString()
      .trim();
  if (explicit.isNotEmpty) return explicit;
  final text =
      '${data['name'] ?? data['title'] ?? ''} ${data['description'] ?? ''} $id'
          .toLowerCase();
  return _utilityInferenceFor(text)?.destination ?? id;
}

class UtilityItem {
  const UtilityItem({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.destinationType,
    required this.destination,
    required this.order,
    this.category = '',
    this.description = '',
    this.active = true,
  });

  factory UtilityItem.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) => UtilityItem.fromData(doc.id, doc.data());

  factory UtilityItem.fromData(String id, Map<String, dynamic> data) {
    return UtilityItem(
      id: id,
      name: (data['name'] ?? data['title'] ?? '').toString(),
      iconKey: inferUtilityIconKey(data, id),
      description: (data['description'] ?? '').toString(),
      destinationType: (data['destinationType'] ?? 'internal').toString(),
      destination: inferUtilityDestination(data, id),
      order: int.tryParse((data['order'] ?? '0').toString()) ?? 0,
      category: (data['category'] ?? '').toString().trim(),
      active: data['active'] as bool? ?? data['published'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String iconKey;
  final String description;
  final String destinationType;
  final String destination;
  final int order;
  final String category;
  final bool active;

  Map<String, dynamic> toMap() => {
    'name': name,
    'iconKey': iconKey,
    'description': description,
    'destinationType': destinationType,
    'destination': destination,
    'order': order,
    'category': category.trim(),
    'active': active,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

Map<String, List<UtilityItem>> groupUtilitiesByCategory(
  Iterable<UtilityItem> items,
) {
  final groups = <String, List<UtilityItem>>{};
  final labelsByKey = <String, String>{};
  for (final item in items) {
    final label = item.category.trim().isEmpty ? 'Geral' : item.category.trim();
    final normalized = label.toLowerCase();
    final groupLabel = labelsByKey.putIfAbsent(normalized, () => label);
    groups.putIfAbsent(groupLabel, () => <UtilityItem>[]).add(item);
  }
  return groups;
}
