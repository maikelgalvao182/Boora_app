import 'package:flutter/material.dart';
import 'package:partiu/features/web_dashboard/screens/events_table_screen.dart';
import 'package:partiu/features/web_dashboard/screens/users_table_screen.dart';
import 'package:partiu/features/web_dashboard/screens/reports_table_screen.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class DashboardLayout extends StatefulWidget {
  const DashboardLayout({super.key});

  @override
  State<DashboardLayout> createState() => _DashboardLayoutState();
}

class _DashboardLayoutState extends State<DashboardLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const UsersTableScreen(),
    const EventsTableScreen(),
    const ReportsTableScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.people),
                selectedIcon: const Icon(Icons.people_alt),
                label: Text(i18n.translate('web_dashboard_users_tab')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.event),
                selectedIcon: const Icon(Icons.event_available),
                label: Text(i18n.translate('web_dashboard_events_tab')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.warning),
                selectedIcon: const Icon(Icons.warning_amber),
                label: Text(i18n.translate('web_dashboard_reports_tab')),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
