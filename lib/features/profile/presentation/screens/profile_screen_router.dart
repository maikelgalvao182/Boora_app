import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/repositories/user_repository.dart';


/// Router para navegação de perfil
/// Centraliza a navegação e decide qual versão da tela mostrar
class ProfileScreenRouter {

  static final Map<String, User> _profileCache = <String, User>{};

  static void cacheUser(User user) {
    if (user.userId.isEmpty) return;
    debugPrint('💾 [ProfileScreenRouter] cacheUser: ${user.userId}');
    _profileCache[user.userId] = user;
  }

  static User? getCachedUser(String userId) {
    final cached = _profileCache[userId];
    debugPrint('🔍 [ProfileScreenRouter] getCachedUser($userId): ${cached != null ? "FOUND" : "NOT FOUND"}');
    debugPrint('🔍 [ProfileScreenRouter] Cache keys: ${_profileCache.keys.toList()}');
    return cached;
  }
  
  /// Navegar para visualização de perfil
  static Future<void> navigateToProfile(
    BuildContext context, {
    required User user,
  }) async {
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      if (context.mounted) {
        _showError(context, 'user_not_authenticated');
      }
      return;
    }

    context.push(
      '${AppRoutes.profile}/${user.userId}',
      extra: {
        'user': user,
        'currentUserId': currentUserId,
      },
    );

    cacheUser(user);
  }

  /// Navegar para edição de perfil
  static Future<void> navigateToEditProfile(BuildContext context) async {
    // Aguardar um frame para garantir que AppState foi atualizado
    await Future.delayed(Duration.zero);
    
    final currentUserId = AppState.currentUserId;
    
    // Aguardar até 3 frames adicionais se ainda estiver null
    if ((currentUserId == null || currentUserId.isEmpty) && context.mounted) {
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final retryUserId = AppState.currentUserId;
        if (retryUserId != null && retryUserId.isNotEmpty) {
          break;
        }
      }
    }
    
    final finalUserId = AppState.currentUserId;
    
    if (finalUserId == null || finalUserId.isEmpty) {
      if (context.mounted) {
        _showError(context, 'user_not_authenticated_try_again');
      }
      return;
    }

    // Usa go_router ao invés de Navigator direto
    if (context.mounted) {
      context.push(AppRoutes.editProfile);
    }
  }

  /// Navegar por ID do usuário (busca dados frescos)
  static Future<void> navigateByUserId(
    BuildContext context, {
    required String userId,
    bool forceRefresh = false,
  }) async {
    try {
      final currentUserId = AppState.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        if (context.mounted) {
          _showError(context, 'user_not_authenticated');
        }
        return;
      }

      User? userToShow;

      // Mesmo usuário: usa o cache em memória
      final currentUser = AppState.currentUser.value;
      if (currentUser != null && currentUser.userId == userId) {
        userToShow = currentUser;
      } else {
        // Outro usuário: buscar dados no Firestore
        // (mantém a assinatura forceRefresh para uso futuro)
        final userData = await UserRepository().getUserById(userId);
        if (userData != null) {
          final normalized = <String, dynamic>{
            ...userData,
            // Alguns docs não possuem o campo userId, mas o model precisa.
            'userId': userId,
          };
          userToShow = User.fromDocument(normalized);
        }
      }

      if (userToShow == null) {
        if (context.mounted) {
          _showError(context, 'profile_data_not_found');
        }
        return;
      }

      cacheUser(userToShow);

      if (!context.mounted) return;

      context.push(
        '${AppRoutes.profile}/$userId',
        extra: {
          'user': userToShow,
          'currentUserId': currentUserId,
        },
      );
    } catch (e) {
      if (context.mounted) {
        final i18n = AppLocalizations.of(context);
        _showError(
          context,
          '${i18n.translate('error_loading_profile')}: $e',
          translate: false,
        );
      }
    }
  }

  /// Mostra erro via Toast
  static void _showError(
    BuildContext context,
    String messageOrKey, {
    bool translate = true,
  }) {
    final i18n = AppLocalizations.of(context);
    ToastService.showError(
      message: translate ? i18n.translate(messageOrKey) : messageOrKey,
    );
  }
}