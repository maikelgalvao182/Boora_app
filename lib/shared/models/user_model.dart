import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';

/// Modelo simplificado de usuário
class UserModel {
  final String userId;
  final String? fullName;
  final String? email;
  final String? photoUrl;
  final String userType; // 'vendor' ou 'bride'
  final List<String> interests;
  final String? locality;
  final String? state;
  final String? flag;
  
  const UserModel({
    required this.userId,
    this.fullName,
    this.email,
    this.photoUrl,
    this.userType = 'vendor',
    this.interests = const [],
    this.locality,
    this.state,
    this.flag,
  });
  
  factory UserModel.fromFirebaseUser(firebase_auth.User user) {
    // ⚠️ NUNCA usar user.photoURL (avatar do Google)
    // A foto deve vir do Firestore (photoUrl do documento do usuário)
    return UserModel(
      userId: user.uid,
      fullName: user.displayName,
      email: user.email,
      photoUrl: null, // Será preenchido pelo Firestore
    );
  }
  
  /// Cria UserModel a partir de documento Firestore
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // ⚠️ FILTRAR URLs do Google OAuth (dados legados)
    // Essas URLs não devem ser usadas como avatar do app
    var rawPhotoUrl = data['photoUrl'] as String?;
    if (rawPhotoUrl != null && 
        (rawPhotoUrl.contains('googleusercontent.com') || 
         rawPhotoUrl.contains('lh3.google'))) {
      rawPhotoUrl = null;
    }
    
    return UserModel(
      userId: doc.id,
      fullName: data['fullName'] as String?,
      email: data['email'] as String?,
      photoUrl: rawPhotoUrl,
      userType: data['userType'] as String? ?? 'vendor',
      interests: List<String>.from(data['interests'] ?? []),
      locality: data['locality'] as String?,
      state: data['state'] as String?,
      flag: data['flag'] as String?,
    );
  }
  
  /// Cria UserModel a partir de Map
  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    // ⚠️ FILTRAR URLs do Google OAuth (dados legados)
    var rawPhotoUrl = map['photoUrl'] as String?;
    if (rawPhotoUrl != null && 
        (rawPhotoUrl.contains('googleusercontent.com') || 
         rawPhotoUrl.contains('lh3.google'))) {
      rawPhotoUrl = null;
    }
    
    return UserModel(
      userId: id,
      fullName: map['fullName'] as String?,
      email: map['email'] as String?,
      photoUrl: rawPhotoUrl,
      locality: map['locality'] as String?,
      state: map['state'] as String?,
      flag: map['flag'] as String?,
    );
  }
  
  /// Cria uma cópia com campos atualizados
  UserModel copyWith({
    String? userId,
    String? fullName,
    String? email,
    String? photoUrl,
    String? userType,
    String? locality,
    String? state,
    String? flag,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      userType: userType ?? this.userType,
      locality: locality ?? this.locality,
      state: state ?? this.state,
      flag: flag ?? this.flag,
    );
  }
  
  // Lista de gêneros
  static List<String> get genders => ['Male', 'Female', 'Other'];
  
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'fullName': fullName,
      'email': email,
      'photoUrl': photoUrl,
      'userType': userType,
      'locality': locality,
      'state': state,
      'flag': flag,
    };
  }
  
  /// Alias para toMap (consistência com fromMap)
  Map<String, dynamic> toJson() => toMap();
  
  // Métodos para OAuth display name
  Future<void> setOAuthDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('oauth_display_name', name);
  }
  
  Future<String?> getOAuthDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('oauth_display_name');
  }
  
  Future<void> clearOAuthDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('oauth_display_name');
  }
}
