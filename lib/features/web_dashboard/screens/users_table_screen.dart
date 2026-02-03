import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';

class UsersTableScreen extends StatefulWidget {
  const UsersTableScreen({super.key});

  @override
  State<UsersTableScreen> createState() => _UsersTableScreenState();
}

class _UsersTableScreenState extends State<UsersTableScreen> {
  int? _totalUsers;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTotalUsers();
  }

  /// ✅ Carrega apenas a contagem total de usuários
  Future<void> _loadTotalUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Usa count() para obter o total real sem carregar documentos
      final countQuery = await FirebaseFirestore.instance
          .collection('Users')
          .count()
          .get();

      if (!mounted) return;

      setState(() {
        _totalUsers = countQuery.count;
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

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          i18n.translate('web_dashboard_users_management_title'),
          style: const TextStyle(color: Colors.black87),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTotalUsers,
          ),
        ],
      ),
      body: _buildBody(i18n),
    );
  }

  Widget _buildBody(AppLocalizations i18n) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.deepPurple,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '😢',
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),
            Text(
              '${i18n.translate('error')}: $_error',
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTotalUsers,
              child: Text(i18n.translate('try_again')),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '👥',
              style: TextStyle(fontSize: 120),
            ),
            const SizedBox(height: 32),
            Text(
              '${_totalUsers ?? 0}',
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              i18n.translate('web_dashboard_total_users_prefix'),
              style: const TextStyle(
                fontSize: 24,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 48),
            OutlinedButton.icon(
              onPressed: _loadTotalUsers,
              icon: const Icon(Icons.refresh),
              label: const Text('Atualizar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                side: const BorderSide(color: Colors.deepPurple),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
