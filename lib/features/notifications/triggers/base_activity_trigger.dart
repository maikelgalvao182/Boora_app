import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/home/domain/models/activity_model.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository_interface.dart';

/// Interface base para triggers de notificação de atividades
/// 
/// Padrão Strategy: cada trigger implementa lógica específica
/// de quando e para quem disparar notificações.
abstract class BaseActivityTrigger {
  const BaseActivityTrigger({
    required this.notificationRepository,
    required this.firestore,
  });

  final INotificationsRepository notificationRepository;
  final FirebaseFirestore firestore;

  /// Executa o trigger
  /// 
  /// @param activity - Modelo da atividade que disparou o evento
  /// @param context - Dados contextuais do evento (ex: requesterId, currentCount)
  Future<void> execute(
    ActivityModel activity,
    Map<String, dynamic> context,
  );

  /// Helper: Obtém dados do usuário (nome + foto)
  Future<Map<String, String>> getUserInfo(String userId) async {
    print('🔍 [BaseActivityTrigger.getUserInfo] Buscando user: $userId');
    try {
      final userDoc = await firestore.collection('Users').doc(userId).get();
      if (!userDoc.exists) {
        print('⚠️ [BaseActivityTrigger.getUserInfo] Usuário não encontrado: $userId');
        return {'fullName': 'Usuário', 'photoUrl': ''};
      }

      final data = userDoc.data()!;
      
      print('📊 [BaseActivityTrigger.getUserInfo] === DADOS DO DOCUMENTO ===');
      print('📊 [BaseActivityTrigger.getUserInfo] Campos disponíveis: ${data.keys.toList()}');
      print('📊 [BaseActivityTrigger.getUserInfo] fullName: ${data['fullName']}');
      print('📊 [BaseActivityTrigger.getUserInfo] fullname: ${data['fullname']}');
      print('📊 [BaseActivityTrigger.getUserInfo] userName: ${data['userName']}');
      print('📊 [BaseActivityTrigger.getUserInfo] photoUrl: ${data['photoUrl']}');
      
      // Tentar múltiplos campos possíveis para nome
      final fullName = data['fullName'] as String? ?? 
                      data['fullname'] as String? ?? 
                      data['userName'] as String? ?? 
                      'Usuário';
      
      // Tentar múltiplos campos possíveis para foto
      final photoUrl = data['photoUrl'] as String? ?? 
                      data['user_profile_photo'] as String? ?? 
                      data['profilePhotoUrl'] as String? ?? 
                      '';
      
      final result = {
        'fullName': fullName,
        'photoUrl': photoUrl,
      };
      
      print('✅ [BaseActivityTrigger.getUserInfo] === RESULTADO FINAL ===');
      print('   • fullName selecionado: $fullName');
      print('   • photoUrl selecionado: $photoUrl');
      return result;
    } catch (e, stackTrace) {
      print('❌ [BaseActivityTrigger.getUserInfo] ERRO: $e');
      print('❌ [BaseActivityTrigger.getUserInfo] StackTrace: $stackTrace');
      return {'fullName': 'Usuário', 'photoUrl': ''};
    }
  }

  /// Helper: Cria notificação padronizada
  Future<void> createNotification({
    required String receiverId,
    required String type,
    required Map<String, dynamic> params,
    String? senderId,
    String? senderName,
    String? senderPhotoUrl,
    String? relatedId,
  }) async {
    print('📝 [BaseActivityTrigger.createNotification] INICIANDO');
    print('📝 [BaseActivityTrigger.createNotification] ReceiverId: $receiverId');
    print('📝 [BaseActivityTrigger.createNotification] Type: $type');
    print('📝 [BaseActivityTrigger.createNotification] Params: $params');
    print('📝 [BaseActivityTrigger.createNotification] SenderId: $senderId');
    print('📝 [BaseActivityTrigger.createNotification] RelatedId: $relatedId');
    
    try {
      // Usa o novo método específico para atividades
      print('📝 [BaseActivityTrigger.createNotification] Chamando notificationRepository.createActivityNotification...');
      await notificationRepository.createActivityNotification(
        receiverId: receiverId,
        type: type,
        params: params,
        senderId: senderId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        relatedId: relatedId,
      );
      print('✅ [BaseActivityTrigger.createNotification] CONCLUÍDO');
    } catch (e, stackTrace) {
      print('❌ [BaseActivityTrigger.createNotification] ERRO: $e');
      print('❌ [BaseActivityTrigger.createNotification] StackTrace: $stackTrace');
    }
  }
}
