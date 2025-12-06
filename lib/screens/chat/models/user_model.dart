/// Modelo simplificado de usuário para o chat com otimizações de performance
class UserModel {

  const UserModel({
    required this.id,
    this.name,
    this.photoUrl,
    this.isOnline,
    this.lastLogin,
  });

  /// Criar UserModel a partir de documento Firestore
  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    DateTime? lastLogin;
    try {
      final lastLoginField = data['user_last_login'];
      if (lastLoginField != null) {
        lastLogin = (lastLoginField as dynamic).toDate();
      }
    } catch (e) {
      // Se houver erro ao converter timestamp, deixar null
      lastLogin = null;
    }

    return UserModel(
      id: id,
      name: data['fullname'] as String?,
      photoUrl: data['user_profile_photo'] as String?,
      isOnline: data['user_is_online'] as bool?,
      lastLogin: lastLogin,
    );
  }
  final String id;
  final String? name;
  final String? photoUrl;
  final bool? isOnline;
  final DateTime? lastLogin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
