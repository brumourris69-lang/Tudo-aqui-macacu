import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/contact/contact_message_validation.dart';

void main() {
  test('accepts Brazilian landline and mobile numbers with area code', () {
    expect(isValidBrazilianPhone('2123456789'), isTrue);
    expect(isValidBrazilianPhone('(21) 91234-5678'), isTrue);
    expect(isValidBrazilianPhone('11987654321'), isTrue);
  });

  test('normalizes punctuation and rejects missing or invalid area codes', () {
    expect(normalizeBrazilianPhone('(21) 91234-5678'), '21912345678');
    expect(isValidBrazilianPhone('123456789'), isFalse);
    expect(isValidBrazilianPhone('0012345678'), isFalse);
    expect(isValidBrazilianPhone('20912345678'), isFalse);
    expect(isValidBrazilianPhone('2123456789'), isTrue);
    expect(isValidBrazilianPhone('21912345678'), isTrue);
    expect(isValidBrazilianPhone('21612345678'), isFalse);
    expect(isValidBrazilianPhone('abc'), isFalse);
  });
}
