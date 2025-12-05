import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:partiu/common/state/app_state.dart';

/// Controller para gerenciar lógica do ChatAppBar
/// 
/// Segue boas práticas: lógica fora do build(), caching, métodos síncronos
class ChatAppBarController {
  ChatAppBarController({required this.userId});

  final String userId;
  
  // Cache
  bool? _isCreatorCache;
  String? _eventIdCache;

  /// Retorna true se o userId é de um evento
  bool get isEvent => userId.startsWith('event_');

  /// Retorna o eventId (sem prefixo 'event_')
  String get eventId {
    _eventIdCache ??= userId.replaceFirst('event_', '');
    return _eventIdCache!;
  }

  /// Verifica se o usuário atual é o criador do evento
  /// 
  /// Resultado é cached para evitar múltiplas queries
  Future<bool> isEventCreator() async {
    if (_isCreatorCache != null) return _isCreatorCache!;
    
    final currentUserId = AppState.currentUserId;
    if (currentUserId == null) {
      _isCreatorCache = false;
      return false;
    }

    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();
      
      if (!eventDoc.exists) {
        _isCreatorCache = false;
        return false;
      }
      
      final createdBy = eventDoc.data()?['createdBy'] as String?;
      _isCreatorCache = (createdBy == currentUserId);
      return _isCreatorCache!;
    } catch (e) {
      debugPrint('❌ Erro ao verificar criador do evento: $e');
      _isCreatorCache = false;
      return false;
    }
  }

  /// Formata schedule para exibição
  /// 
  /// Retorna string formatada ou vazio se inválido
  static String formatSchedule(dynamic schedule) {
    if (schedule == null || schedule is! Map) return '';
    
    final date = schedule['date'];
    if (date == null) return '';

    DateTime? dateTime;
    if (date is Timestamp) {
      dateTime = date.toDate();
    } else if (date is DateTime) {
      dateTime = date;
    }
    
    if (dateTime == null) return '';
    
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString().substring(2);
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    
    return '$day/$month/$year às $hour:$minute';
  }

  /// Limpa cache (útil para testes)
  void clearCache() {
    _isCreatorCache = null;
    _eventIdCache = null;
  }
}
