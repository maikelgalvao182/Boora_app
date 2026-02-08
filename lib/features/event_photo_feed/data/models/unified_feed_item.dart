import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/event_photo_feed/data/models/event_photo_model.dart';
import 'package:partiu/features/feed/data/models/activity_feed_item_model.dart';

/// Tipo de item no feed unificado
enum UnifiedFeedItemType {
  /// Post de foto de evento
  photo,
  /// Post de criação de atividade
  activity,
}

/// Modelo unificado que representa um item no feed
/// 
/// Pode ser um EventPhoto (foto) ou ActivityFeed (criação de evento)
class UnifiedFeedItem {
  const UnifiedFeedItem._({
    required this.type,
    required this.id,
    required this.createdAt,
    this.photo,
    this.activity,
  });

  /// Cria a partir de um EventPhotoModel
  factory UnifiedFeedItem.fromPhoto(EventPhotoModel photo) {
    return UnifiedFeedItem._(
      type: UnifiedFeedItemType.photo,
      id: photo.id,
      createdAt: photo.createdAt,
      photo: photo,
    );
  }

  /// Cria a partir de um ActivityFeedItemModel
  factory UnifiedFeedItem.fromActivity(ActivityFeedItemModel activity) {
    return UnifiedFeedItem._(
      type: UnifiedFeedItemType.activity,
      id: activity.id,
      createdAt: activity.createdAt,
      activity: activity,
    );
  }

  final UnifiedFeedItemType type;
  final String id;
  final Timestamp? createdAt;
  
  /// Dados do EventPhoto (se type == photo)
  final EventPhotoModel? photo;
  
  /// Dados do ActivityFeed (se type == activity)
  final ActivityFeedItemModel? activity;

  /// Retorna o userId do criador do item
  String get userId => type == UnifiedFeedItemType.photo 
      ? photo!.userId 
      : activity!.userId;

  /// Retorna o eventId associado
  String get eventId => type == UnifiedFeedItemType.photo 
      ? photo!.eventId 
      : activity!.eventId;

  /// Retorna a data de criação como DateTime para ordenação
  DateTime? get createdAtDateTime => createdAt?.toDate();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedFeedItem &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          id == other.id;

  @override
  int get hashCode => type.hashCode ^ id.hashCode;
}

/// Extension para ordenar lista de UnifiedFeedItem por data
extension UnifiedFeedItemListExt on List<UnifiedFeedItem> {
  /// Ordena por createdAt decrescente (mais recente primeiro)
  /// Fotos têm prioridade sobre cards de atividade:
  /// - Intercala fotos e activities mantendo cronologia geral
  /// - Quando ambos estão no mesmo "bloco temporal" (6h), fotos vêm antes
  List<UnifiedFeedItem> sortedByDate() {
    final sorted = List<UnifiedFeedItem>.from(this);
    sorted.sort((a, b) {
      final aDate = a.createdAtDateTime;
      final bDate = b.createdAtDateTime;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      // Se ambos são do mesmo tipo, ordena puramente por data
      if (a.type == b.type) {
        return bDate.compareTo(aDate);
      }

      // Se estão dentro de uma janela de 6h, fotos têm prioridade
      final diff = aDate.difference(bDate).abs();
      if (diff < const Duration(hours: 6)) {
        // Foto vem primeiro (retorna -1 se a é foto, +1 se b é foto)
        return a.type == UnifiedFeedItemType.photo ? -1 : 1;
      }

      // Fora da janela, ordena por data normalmente
      return bDate.compareTo(aDate);
    });
    return sorted;
  }
}
