import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Repository centralizado para queries da coleção Users
/// 
/// Evita duplicação de código ao reutilizar queries comuns
class UserRepository {
  final FirebaseFirestore _firestore;

  UserRepository([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Referência à coleção Users
  CollectionReference get _usersCollection => _firestore.collection('Users');

  /// Busca um usuário por ID
  /// 
  /// Retorna null se não encontrado
  Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      final doc = await _usersCollection.doc(userId).get();
      
      if (!doc.exists) {
        debugPrint('⚠️ Usuário não encontrado: $userId');
        return null;
      }

      return {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar usuário $userId: $e');
      return null;
    }
  }

  /// Busca múltiplos usuários por IDs (batch otimizado)
  /// 
  /// Retorna Map<userId, userData> para acesso rápido
  /// Firestore whereIn aceita até 10 IDs por query
  Future<Map<String, Map<String, dynamic>>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return {};

    try {
      final results = <String, Map<String, dynamic>>{};
      
      // Dividir em chunks de 10 (limite do whereIn)
      for (var i = 0; i < userIds.length; i += 10) {
        final chunk = userIds.skip(i).take(10).toList();
        
        final snapshot = await _usersCollection
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snapshot.docs) {
          results[doc.id] = {
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          };
        }
      }

      return results;
    } catch (e) {
      debugPrint('❌ Erro ao buscar usuários por IDs: $e');
      return {};
    }
  }

  /// Busca dados básicos de um usuário (photoUrl + fullName)
  /// 
  /// Usado para exibir avatar + nome em listas
  Future<Map<String, dynamic>?> getUserBasicInfo(String userId) async {
    try {
      final doc = await _usersCollection.doc(userId).get();
      
      if (!doc.exists) {
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;
      return {
        'userId': userId,
        'photoUrl': data['photoUrl'] as String?,
        'fullName': data['fullName'] as String?,
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar info básica do usuário $userId: $e');
      return null;
    }
  }

  /// Busca dados básicos de múltiplos usuários (batch)
  /// 
  /// Retorna List para manter ordem original dos IDs
  Future<List<Map<String, dynamic>>> getUsersBasicInfo(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    try {
      final usersMap = await getUsersByIds(userIds);
      
      // Retornar na ordem original dos IDs, filtrar nulls
      return userIds
          .map((userId) {
            final userData = usersMap[userId];
            if (userData == null) return null;
            
            return {
              'userId': userId,
              'photoUrl': userData['photoUrl'] as String?,
              'fullName': userData['fullName'] as String?,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar info básica de usuários: $e');
      return [];
    }
  }

  /// Stream de dados do usuário (para listeners em tempo real)
  Stream<Map<String, dynamic>?> watchUser(String userId) {
    return _usersCollection
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return {
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          };
        });
  }

  /// Atualiza dados de um usuário
  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    try {
      await _usersCollection.doc(userId).update(data);
      debugPrint('✅ Usuário atualizado: $userId');
    } catch (e) {
      debugPrint('❌ Erro ao atualizar usuário $userId: $e');
      rethrow;
    }
  }

  /// Cria um novo usuário
  Future<void> createUser(String userId, Map<String, dynamic> data) async {
    try {
      await _usersCollection.doc(userId).set(data);
      debugPrint('✅ Usuário criado: $userId');
    } catch (e) {
      debugPrint('❌ Erro ao criar usuário $userId: $e');
      rethrow;
    }
  }

  /// Verifica se usuário existe
  Future<bool> userExists(String userId) async {
    try {
      final doc = await _usersCollection.doc(userId).get();
      return doc.exists;
    } catch (e) {
      debugPrint('❌ Erro ao verificar existência do usuário $userId: $e');
      return false;
    }
  }
}
