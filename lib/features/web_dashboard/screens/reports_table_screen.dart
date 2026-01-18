import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class ReportsTableScreen extends StatefulWidget {
  const ReportsTableScreen({super.key});

  @override
  State<ReportsTableScreen> createState() => _ReportsTableScreenState();
}

class _ReportsTableScreenState extends State<ReportsTableScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.translate('web_dashboard_reports_management_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: i18n.translate('web_dashboard_reports_all_tab')),
            Tab(text: i18n.translate('web_dashboard_reports_users_tab')),
            Tab(text: i18n.translate('web_dashboard_reports_events_tab')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ReportsListView(filterType: null),
          _ReportsListView(filterType: 'user'),
          _ReportsListView(filterType: 'event'),
        ],
      ),
    );
  }
}

class _ReportsListView extends StatelessWidget {
  const _ReportsListView({this.filterType});

  final String? filterType;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return StreamBuilder<QuerySnapshot>(
      stream: _getReportsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text('${i18n.translate('error')}: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Text(i18n.translate('web_dashboard_no_reports')),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '${i18n.translate('web_dashboard_total_reports_prefix')}: ${docs.length}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(
                          label: Text(i18n.translate('web_dashboard_column_id'))),
                      DataColumn(
                          label: Text(i18n.translate('web_dashboard_column_type'))),
                      DataColumn(
                          label: Text(i18n.translate('web_dashboard_column_reporter'))),
                      DataColumn(
                          label: Text(i18n.translate('web_dashboard_column_target'))),
                      DataColumn(
                          label: Text(i18n.translate('web_dashboard_column_message'))),
                      DataColumn(
                          label: Text(i18n.translate('web_dashboard_column_date'))),
                      DataColumn(
                          label: Text(i18n.translate('web_dashboard_column_status'))),
                    ],
                    rows: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return _buildReportRow(context, doc.id, data, i18n);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Stream<QuerySnapshot> _getReportsStream() {
    final reportsRef = FirebaseFirestore.instance.collection('reports');

    if (filterType == null) {
      return reportsRef.orderBy('createdAt', descending: true).snapshots();
    }

    return reportsRef
        .where('type', isEqualTo: filterType)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  DataRow _buildReportRow(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
    AppLocalizations i18n,
  ) {
    final reportType = data['type'] as String? ?? '-';
    final reporterId = data['reporterId'] as String? ?? 
                       data['reportedBy'] as String? ?? '-';
    final targetUserId = data['targetUserId'] as String?;
    final eventId = data['eventId'] as String?;
    final message = data['message'] as String? ?? 
                    data['reportText'] as String? ?? 
                    i18n.translate('web_dashboard_no_message');
    final activityText = data['activityText'] as String?;
    final status = data['status'] as String? ?? 'pending';
    
    final createdAt = data['createdAt'] as Timestamp?;
    final dateStr = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : i18n.translate('web_dashboard_no_date');

    // Determinar target (destino da denúncia)
    String targetDisplay = '-';
    if (reportType == 'event' && eventId != null) {
      targetDisplay = activityText != null 
          ? '$eventId (${activityText.substring(0, activityText.length > 30 ? 30 : activityText.length)}${activityText.length > 30 ? '...' : ''})'
          : eventId.substring(0, 8);
    } else if (reportType == 'user' && targetUserId != null) {
      targetDisplay = targetUserId.substring(0, 8);
    }

    return DataRow(
      cells: [
        DataCell(Text(docId.substring(0, 8))),
        DataCell(_buildTypeChip(reportType)),
        DataCell(Text(reporterId.substring(0, 8))),
        DataCell(Text(targetDisplay)),
        DataCell(
          SizedBox(
            width: 300,
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(dateStr)),
        DataCell(_buildStatusChip(status, i18n)),
      ],
    );
  }

  Widget _buildTypeChip(String type) {
    Color color;
    IconData icon;

    switch (type.toLowerCase()) {
      case 'event':
        color = Colors.blue;
        icon = Icons.event;
        break;
      case 'user':
        color = Colors.purple;
        icon = Icons.person;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        type.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildStatusChip(String status, AppLocalizations i18n) {
    Color color;
    String label;

    switch (status.toLowerCase()) {
      case 'pending':
        color = Colors.orange;
        label = i18n.translate('web_dashboard_status_pending');
        break;
      case 'resolved':
        color = Colors.green;
        label = i18n.translate('web_dashboard_status_resolved');
        break;
      case 'dismissed':
        color = Colors.grey;
        label = i18n.translate('web_dashboard_status_dismissed');
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Chip(
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
