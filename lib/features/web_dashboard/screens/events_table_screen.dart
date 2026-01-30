import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/features/home/data/models/event_model.dart';
import 'package:intl/intl.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class EventsTableScreen extends StatefulWidget {
  const EventsTableScreen({super.key});

  @override
  State<EventsTableScreen> createState() => _EventsTableScreenState();
}

class _EventsTableScreenState extends State<EventsTableScreen> {
  List<EventModel> _events = [];
  bool _loading = true;
  String? _error;
  DocumentSnapshot? _lastDoc;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  /// ✅ Carrega eventos uma vez com paginação
  Future<void> _loadEvents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _events = snapshot.docs.map((doc) {
          final data = doc.data();
          return EventModel.fromMap(data, doc.id);
        }).toList();
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// ✅ Carrega mais eventos (paginação)
  Future<void> _loadMore() async {
    if (_lastDoc == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _events.addAll(snapshot.docs.map((doc) {
          final data = doc.data();
          return EventModel.fromMap(data, doc.id);
        }));
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar mais eventos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.translate('web_dashboard_events_management_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvents,
          ),
        ],
      ),
      body: _buildBody(i18n),
    );
  }

  Widget _buildBody(AppLocalizations i18n) {
    if (_loading && _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${i18n.translate('error')}: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEvents,
              child: Text(i18n.translate('try_again')),
            ),
          ],
        ),
      );
    }

    final events = _events;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Text(
                      '${i18n.translate('web_dashboard_total_events_prefix')}: ${events.length}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    if (_lastDoc != null)
                      TextButton.icon(
                        icon: const Icon(Icons.arrow_downward),
                        label: Text(i18n.translate('load_more')),
                        onPressed: _loadMore,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                columns: [
                  DataColumn(label: Text(i18n.translate('web_dashboard_column_id'))),
                  DataColumn(label: Text(i18n.translate('web_dashboard_column_title'))),
                  DataColumn(label: Text(i18n.translate('web_dashboard_column_created_by'))),
                  DataColumn(label: Text(i18n.translate('web_dashboard_column_date'))),
                  DataColumn(label: Text(i18n.translate('web_dashboard_column_status'))),
                ],
                rows: events.map((event) {
                  return DataRow(cells: [
                    DataCell(Text(event.id.substring(0, 8))),
                    DataCell(Text('${event.emoji} ${event.title}')),
                    DataCell(Text(event.creatorFullName ?? event.createdBy)),
                    DataCell(Text(event.scheduleDate != null 
                      ? DateFormat('dd/MM/yyyy HH:mm').format(event.scheduleDate!) 
                      : i18n.translate('web_dashboard_no_date'))),
                    DataCell(Text(event.isAvailable
                        ? i18n.translate('web_dashboard_status_available')
                        : i18n.translate('web_dashboard_status_unavailable'))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
