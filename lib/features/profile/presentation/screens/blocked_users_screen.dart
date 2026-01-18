import 'package:flutter/material.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/glimpse_app_bar.dart';
import 'package:partiu/shared/widgets/glimpse_empty_state.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:partiu/features/profile/presentation/widgets/blocked_user_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tela para gerenciar usuários bloqueados
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _blockService = BlockService.instance;
  final _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _blockedUsers = [];
  
  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    if (_currentUserId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Busca IDs dos usuários bloqueados
      final blockedIds = _blockService.getAllBlockedIds(_currentUserId);
      
      if (blockedIds.isEmpty) {
        setState(() {
          _blockedUsers = [];
          _isLoading = false;
        });
        return;
      }

      // Busca dados dos usuários no Firestore
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where(FieldPath.documentId, whereIn: blockedIds.toList())
          .get();
      
      // ✅ PRELOAD: Carregar avatares antes da UI renderizar
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final photoUrl = data['profilePicture'] as String?;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          UserStore.instance.preloadAvatar(doc.id, photoUrl);
        }
      }

      setState(() {
        _blockedUsers = usersSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'userId': doc.id,
            'fullName': data['fullName'] as String? ?? 'Usuário',
            'from': data['from'] as String?,
            'profilePicture': data['profilePicture'] as String?,
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error(
        'Erro ao carregar usuários bloqueados',
        tag: 'BLOCK',
        error: e,
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unblockUser(String userId, String userName) async {
    final i18n = AppLocalizations.of(context);

    String tr(String key, String fallback) {
      final value = i18n.translate(key);
      return value.isNotEmpty ? value : fallback;
    }
    
    // Confirmação
    final confirmed = await GlimpseCupertinoDialog.show(
      context: context,
      title: tr('unblock_user', 'Desbloquear usuário'),
      message: tr('unblock_user_confirmation', 'Deseja desbloquear {name}?').replaceAll('{name}', userName),
      cancelText: tr('cancel', 'Cancelar'),
      confirmText: tr('unblock', 'Desbloquear'),
    );

    if (confirmed != true) return;

    try {
      await _blockService.unblockUser(_currentUserId, userId);
      
      // Atualiza lista localmente
      setState(() {
        _blockedUsers.removeWhere((user) => user['userId'] == userId);
      });

      if (mounted) {
        final i18nToast = AppLocalizations.of(context);
        ToastService.showSuccess(
          message: i18nToast.translate('user_unblocked_successfully'),
        );
      }
    } catch (e) {
      AppLogger.error(
        'Erro ao desbloquear usuário',
        tag: 'BLOCK',
        error: e,
      );
      if (mounted) {
        final i18nToast = AppLocalizations.of(context);
        ToastService.showError(
          message: i18nToast.translate('error_unblocking_user'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    String tr(String key, String fallback) {
      final value = i18n.translate(key);
      return value.isNotEmpty ? value : fallback;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: GlimpseAppBar(
        title: tr('blocked_users', 'Usuários Bloqueados'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
              ? Center(
                  child: GlimpseEmptyState.standard(
                    text: tr('no_blocked_users', 'Você não bloqueou nenhum usuário'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _blockedUsers.length,
                  itemBuilder: (context, index) {
                    final user = _blockedUsers[index];
                    final userId = user['userId'] as String;
                    final fullName = user['fullName'] as String;
                    final from = user['from'] as String?;
                    final photoUrl = user['profilePicture'] as String?;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BlockedUserCard(
                        userId: userId,
                        fullName: fullName,
                        from: from,
                        photoUrl: photoUrl,
                        onUnblock: () => _unblockUser(userId, fullName),
                      ),
                    );
                  },
                ),
    );
  }
}
