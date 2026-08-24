import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/match_travel.dart';

void main() {
  group('MatchTravel.isDillenburchtLocation', () {
    test('recognizes Dillenburcht variants', () {
      expect(MatchTravel.isDillenburchtLocation('Dillenburcht, Drunen'), isTrue);
      expect(MatchTravel.isDillenburchtLocation('De Dillenburcht'), isTrue);
      expect(
        MatchTravel.isDillenburchtLocation('DILLENBURCHT, Tinie de Munnikstraat 5'),
        isTrue,
      );
    });

    test('rejects other locations', () {
      expect(MatchTravel.isDillenburchtLocation('Sporthal De Kubus, Vlijmen'), isFalse);
      expect(MatchTravel.isDillenburchtLocation(null), isFalse);
      expect(MatchTravel.isDillenburchtLocation(''), isFalse);
    });
  });

  group('MatchTravel.shouldShowTravel', () {
    test('shows travel for away matches only', () {
      expect(MatchTravel.shouldShowTravel('Sporthal De Kubus, Vlijmen'), isTrue);
      expect(MatchTravel.shouldShowTravel('Dillenburcht, Drunen'), isFalse);
      expect(MatchTravel.shouldShowTravel(null), isFalse);
    });
  });

  group('MatchTravel.googleMapsDirectionsUri', () {
    test('builds directions URL with origin and destination', () {
      final uri = MatchTravel.googleMapsDirectionsUri('Sporthal De Kubus, Vlijmen');
      expect(uri, isNotNull);
      expect(uri!.host, 'www.google.com');
      expect(uri.queryParameters['travelmode'], 'driving');
      expect(uri.queryParameters['origin'], contains('Dillenburcht'));
      expect(uri.queryParameters['destination'], 'Sporthal De Kubus, Vlijmen');
    });
  });
}
