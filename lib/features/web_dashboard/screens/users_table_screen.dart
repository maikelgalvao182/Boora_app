import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:partiu/shared/models/user_model.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class UsersTableScreen extends StatefulWidget {
  const UsersTableScreen({super.key});

  @override
  State<UsersTableScreen> createState() => _UsersTableScreenState();
}

class _UsersTableScreenState extends State<UsersTableScreen> {
  List<UserModel> _users = [];
  bool _loading = true;
  String? _error;
  DocumentSnapshot? _lastDoc;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  /// ✅ Carrega usuários uma vez com paginação
  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _users = snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
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

  /// ✅ Carrega mais usuários (paginação)
  Future<void> _loadMore() async {
    if (_lastDoc == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _users.addAll(snapshot.docs.map((doc) => UserModel.fromFirestore(doc)));
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar mais usuários: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.translate('web_dashboard_users_management_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: _buildBody(i18n),
    );
  }

  Widget _buildBody(AppLocalizations i18n) {
    if (_loading && _users.isEmpty) {
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
              onPressed: _loadUsers,
              child: Text(i18n.translate('try_again')),
            ),
          ],
        ),
      );
    }

    final docs = _users;
          
          // Convert docs to UserModels
          final users = docs;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Text(
                      '${i18n.translate('web_dashboard_total_users_prefix')}: ${users.length}',
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
                        DataColumn(label: Text(i18n.translate('photo'))),
                        DataColumn(label: Text(i18n.translate('web_dashboard_column_id'))),
                        DataColumn(label: Text(i18n.translate('web_dashboard_column_name'))),
                        DataColumn(label: Text(i18n.translate('web_dashboard_column_email'))),
                        DataColumn(label: Text(i18n.translate('web_dashboard_column_type'))),
                        DataColumn(label: Text(i18n.translate('web_dashboard_column_city'))),
                        DataColumn(label: Text(i18n.translate('web_dashboard_column_state'))),
                      ],
                      rows: users.map((user) {
                        return DataRow(cells: [
                          DataCell(
                            user.photoUrl != null
                                ? CircleAvatar(
                                    radius: 15,
                                    backgroundImage: CachedNetworkImageProvider(user.photoUrl!),
                                  )
                                : const CircleAvatar(
                                    radius: 15,
                                    child: Icon(Icons.person, size: 15),
                                  ),
                          ),
                          DataCell(Text(user.userId.substring(0, 8))), // Shorten ID
                          DataCell(Text(user.fullName ?? i18n.translate('web_dashboard_no_name'))),
                          DataCell(Text(user.email ?? i18n.translate('web_dashboard_no_email'))),
                          DataCell(Text(user.userType)),
                          DataCell(Text(user.locality ?? '-')),
                          DataCell(Text(user.state ?? '-')),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}
