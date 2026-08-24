import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:minerva_app/ui/app_colors.dart';

/// Route vanaf De Dillenburcht naar uitwedstrijden.
class MatchTravel {
  MatchTravel._();

  static const dillenburchtOriginLabel = 'De Dillenburcht';
  static const dillenburchtOriginAddress = 'Tinie de Munnikstraat 5, 5151VW Drunen';

  static bool isDillenburchtLocation(String? location) {
    final s = location?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return false;
    return s.contains('dillenburcht');
  }

  static bool shouldShowTravel(String? location) {
    final s = location?.trim() ?? '';
    return s.isNotEmpty && !isDillenburchtLocation(s);
  }

  static Uri? googleMapsDirectionsUri(String destination) {
    final dest = destination.trim();
    if (dest.isEmpty) return null;
    final origin = '$dillenburchtOriginLabel, $dillenburchtOriginAddress';
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=${Uri.encodeComponent(origin)}'
      '&destination=${Uri.encodeComponent(dest)}'
      '&travelmode=driving',
    );
  }

  static Future<void> openDirections(String destination) async {
    final uri = googleMapsDirectionsUri(destination);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Route-link voor uitwedstrijden (niet in De Dillenburcht).
class MatchTravelRow extends StatelessWidget {
  const MatchTravelRow({
    super.key,
    required this.location,
    this.textDecoration,
  });

  final String? location;
  final TextDecoration? textDecoration;

  @override
  Widget build(BuildContext context) {
    if (!MatchTravel.shouldShowTravel(location)) {
      return const SizedBox.shrink();
    }

    final style = TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
      fontSize: 13,
      decoration: textDecoration,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => MatchTravel.openDirections(location!.trim()),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(Icons.directions_car_outlined, size: 16, color: style.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Route vanaf De Dillenburcht',
                  style: style,
                ),
              ),
              Icon(Icons.open_in_new, size: 14, color: style.color),
            ],
          ),
        ),
      ),
    );
  }
}
