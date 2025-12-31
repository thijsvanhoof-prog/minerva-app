import 'package:flutter/material.dart';

class TeamMembership {
  final int teamId;
  final String role;
  final String teamName;

  const TeamMembership({
    required this.teamId,
    required this.role,
    required this.teamName,
  });

  bool get canManageTeam =>
      role == 'admin' || role == 'trainer' || role == 'coach';
}

class AppUserContext extends InheritedWidget {
  final String profileId;
  final String email;
  final bool isGlobalAdmin;
  final List<TeamMembership> memberships;

  const AppUserContext({
    super.key,
    required this.profileId,
    required this.email,
    required this.isGlobalAdmin,
    required this.memberships,
    required super.child,
  });

  static AppUserContext of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<AppUserContext>();
    if (result == null) {
      throw FlutterError(
        'AppUserContext.of() called but no AppUserContext found.\n'
        'Did you forget to wrap your widget tree?',
      );
    }
    return result;
  }

  @override
  bool updateShouldNotify(AppUserContext oldWidget) {
    return profileId != oldWidget.profileId ||
        email != oldWidget.email ||
        isGlobalAdmin != oldWidget.isGlobalAdmin ||
        memberships != oldWidget.memberships;
  }
}