import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de visualização de perfil
/// 
/// Registra quando um usuário visualiza o perfil de outro.
/// Usado para gerar notificações agregadas do tipo "X pessoas visualizaram seu perfil".
class ProfileViewModel {
  /// ID do documento no Firestore
  final String? id;
  
  /// ID do usuário que visualizou
  final String viewerId;
  
  /// ID do usuário cujo perfil foi visualizado
  final String viewedUserId;
  
  /// Timestamp da visualização
  final DateTime viewedAt;
  
  /// Se esta visualização já foi incluída em uma notificação agregada
  final bool notified;
  
  /// Dados adicionais do viewer (cache para evitar queries extras)
  final String? viewerName;
  final String? viewerPhotoUrl;

  const ProfileViewModel({
    this.id,
    required this.viewerId,
    required this.viewedUserId,
    required this.viewedAt,
    this.notified = false,
    this.viewerName,
    this.viewerPhotoUrl,
  });

  /// Cria instância a partir de documento Firestore
  factory ProfileViewModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    
    return ProfileViewModel(
      id: doc.id,
      viewerId: data['viewerId'] as String,
      viewedUserId: data['viewedUserId'] as String,
      viewedAt: (data['viewedAt'] as Timestamp).toDate(),
      notified: data['notified'] as bool? ?? false,
      viewerName: data['viewerName'] as String?,
      viewerPhotoUrl: data['viewerPhotoUrl'] as String?,
    );
  }

  /// Converte para Map para salvar no Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'viewerId': viewerId,
      'viewedUserId': viewedUserId,
      'viewedAt': Timestamp.fromDate(viewedAt),
      'notified': notified,
      if (viewerName != null) 'viewerName': viewerName,
      if (viewerPhotoUrl != null) 'viewerPhotoUrl': viewerPhotoUrl,
    };
  }

  /// Cria cópia com alterações
  ProfileViewModel copyWith({
    String? id,
    String? viewerId,
    String? viewedUserId,
    DateTime? viewedAt,
    bool? notified,
    String? viewerName,
    String? viewerPhotoUrl,
  }) {
    return ProfileViewModel(
      id: id ?? this.id,
      viewerId: viewerId ?? this.viewerId,
      viewedUserId: viewedUserId ?? this.viewedUserId,
      viewedAt: viewedAt ?? this.viewedAt,
      notified: notified ?? this.notified,
      viewerName: viewerName ?? this.viewerName,
      viewerPhotoUrl: viewerPhotoUrl ?? this.viewerPhotoUrl,
    );
  }

  @override
  String toString() {
    return 'ProfileView(id: $id, viewer: $viewerId, viewed: $viewedUserId, at: $viewedAt, notified: $notified)';
  }
}
