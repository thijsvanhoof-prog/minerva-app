import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/committees/committee_normalization.dart';

void main() {
  group('normalizeCommitteeKey', () {
    test('normalizes bestuur variants', () {
      expect(normalizeCommitteeKey('bestuur'), 'bestuur');
      expect(normalizeCommitteeKey('Bestuur Minerva'), 'bestuur');
      expect(normalizeCommitteeKey('Algemeen bestuur'), 'bestuur');
    });

    test('normalizes technische commissie variants', () {
      expect(normalizeCommitteeKey('tc'), 'technische-commissie');
      expect(normalizeCommitteeKey('Technische Commissie'), 'technische-commissie');
    });

    test('normalizes communicatie variants', () {
      expect(normalizeCommitteeKey('cc'), 'communicatie');
      expect(normalizeCommitteeKey('Communicatie'), 'communicatie');
    });

    test('normalizes wedstrijdzaken variants', () {
      expect(normalizeCommitteeKey('wz'), 'wedstrijdzaken');
      expect(normalizeCommitteeKey('Wedstrijdzaken'), 'wedstrijdzaken');
    });

    test('normalizes jeugd variants', () {
      expect(normalizeCommitteeKey('Jeugd'), 'jeugdcommissie');
      expect(normalizeCommitteeKey('Jeugd commissie'), 'jeugdcommissie');
      expect(normalizeCommitteeKey('Jeugdcommissie'), 'jeugdcommissie');
    });

    test('normalizes scheidsrechters/tellers variants', () {
      expect(normalizeCommitteeKey('Scheidsrechters/Tellers'), 'scheidsrechters-tellers');
      expect(normalizeCommitteeKey('scheidsrechters-tellers'), 'scheidsrechters-tellers');
    });

    test('normalizes evenementen variants', () {
      expect(normalizeCommitteeKey('Evenementen-commissie'), 'evenementen');
    });

    test('returns empty string for blank input', () {
      expect(normalizeCommitteeKey(''), '');
      expect(normalizeCommitteeKey('   '), '');
    });

    test('returns lowercase unchanged for unknown custom names', () {
      expect(normalizeCommitteeKey('Sponsorcommissie'), 'sponsorcommissie');
      expect(normalizeCommitteeKey('  Custom Team  '), 'custom team');
    });
  });
}
