import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/helpers/time_ago_helper.dart';
import 'package:partiu/core/models/user.dart';
import 'package:partiu/screens/chat/services/chat_service.dart';

/// Widget que exibe localização (locality, state) e time ago do usuário
/// Usado no ChatAppBar para chats 1x1
class UserLocationTimeWidget extends StatelessWidget {
  const UserLocationTimeWidget({
    required this.user,
    required this.chatService,
    super.key,
    this.showTime = true,
  });

  final User user;
  final ChatService chatService;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    debugPrint('🔍 [UserLocationTimeWidget] Buscando dados para userId: ${user.userId}');
    
    // Buscar dados de localização na coleção Users
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Users')
          .where('userId', isEqualTo: user.userId)
          .limit(1)
          .snapshots(),
      builder: (context, userSnapshot) {
        debugPrint('🔍 [UserLocationTimeWidget] User Stream state: hasData=${userSnapshot.hasData}, hasError=${userSnapshot.hasError}');
        
        String locality = '';
        String state = '';
        
        if (userSnapshot.hasData && userSnapshot.data!.docs.isNotEmpty) {
          final doc = userSnapshot.data!.docs.first;
          final data = doc.data() as Map<String, dynamic>?;
          
          if (data != null) {
            locality = data['locality'] as String? ?? '';
            state = data['state'] as String? ?? '';
            debugPrint('✅ [UserLocationTimeWidget] Dados de localização: locality="$locality", state="$state"');
          }
        } else {
          // Fallback para dados do objeto User
          locality = user.userLocality;
          state = user.userState ?? '';
          debugPrint('📦 [UserLocationTimeWidget] Usando localização do objeto User');
        }
        
        // Buscar timestamp da última mensagem na coleção Connections (igual ao conversation_tile.dart)
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: chatService.getConversationSummary(user.userId),
          builder: (context, messageSnapshot) {
            debugPrint('🔍 [UserLocationTimeWidget] Message Stream state: hasData=${messageSnapshot.hasData}');
            
            DateTime? lastMessageTime;
            if (messageSnapshot.hasData && messageSnapshot.data!.data() != null) {
              final data = messageSnapshot.data!.data()!;
              
              // Buscar timestamp igual ao conversation_tile.dart
              final timestampValue = data['last_message_timestamp']
                  ?? data['last_message_at']
                  ?? data['lastMessageAt']
                  ?? data['timestamp'];
              
              debugPrint('🔍 [UserLocationTimeWidget] timestampValue raw: $timestampValue (tipo: ${timestampValue.runtimeType})');
              
              if (timestampValue != null) {
                try {
                  if (timestampValue is Timestamp) {
                    lastMessageTime = timestampValue.toDate();
                    debugPrint('✅ [UserLocationTimeWidget] lastMessageTime parseado: $lastMessageTime');
                  } else if (timestampValue is DateTime) {
                    lastMessageTime = timestampValue;
                    debugPrint('✅ [UserLocationTimeWidget] lastMessageTime já é DateTime: $lastMessageTime');
                  }
                } catch (e) {
                  debugPrint('❌ [UserLocationTimeWidget] Erro ao parsear timestamp: $e');
                }
              } else {
                debugPrint('⚠️ [UserLocationTimeWidget] Nenhum timestamp encontrado nos campos esperados');
              }
            }
            
            debugPrint('🎯 [UserLocationTimeWidget] Chamando _buildRow com lastMessageTime=$lastMessageTime');
            return _buildRow(locality, state, lastMessageTime);
          },
        );
      },
    );
  }

  /// Fallback: constrói row usando dados do objeto User
  Widget _buildFromUserObject() {
    debugPrint('📦 [UserLocationTimeWidget] Usando dados do objeto User: locality="${user.userLocality}", state="${user.userState}"');
    
    return _buildRow(
      user.userLocality,
      user.userState ?? '',
      null, // Sem timestamp no fallback
    );
  }

  /// Constrói a row com localização e time ago
  Widget _buildRow(String locality, String state, DateTime? lastMessageTime) {
    debugPrint('🏗️ [UserLocationTimeWidget] _buildRow: locality="$locality", state="$state", lastMessageTime=$lastMessageTime');
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Locality, State
        Flexible(
          child: _buildLocationText(locality, state),
        ),
        if (showTime) ...[
          const SizedBox(width: 8),
          // Last message time ago
          _buildLastMessageTimeText(lastMessageTime),
        ],
      ],
    );
  }

  /// Widget de localização
  Widget _buildLocationText(String locality, String state) {
    String locationText = '';
    if (locality.isNotEmpty && state.isNotEmpty) {
      locationText = '$locality, $state';
    } else if (locality.isNotEmpty) {
      locationText = locality;
    } else if (state.isNotEmpty) {
      locationText = state;
    }

    if (locationText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      locationText,
      style: GoogleFonts.getFont(
        FONT_PLUS_JAKARTA_SANS,
        fontSize: 12,
        color: GlimpseColors.textSubTitle,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Widget de last seen - Reativo usando o lastLogin já disponível
  /// Widget de time ago da última mensagem (igual ao conversation_tile.dart)
  Widget _buildLastMessageTimeText(DateTime? lastMessageTime) {
    debugPrint('🕐 [UserLocationTimeWidget] _buildLastMessageTimeText chamado: lastMessageTime=$lastMessageTime');
    
    if (lastMessageTime == null) {
      debugPrint('❌ [UserLocationTimeWidget] lastMessageTime é null');
      return const SizedBox.shrink();
    }
    
    return Builder(
      builder: (context) {
        debugPrint('🔄 [UserLocationTimeWidget] Formatando lastMessageTime: $lastMessageTime');
        final timeAgoText = TimeAgoHelper.format(
          context,
          timestamp: lastMessageTime,
        );
        
        debugPrint('📝 [UserLocationTimeWidget] timeAgoText formatado: "$timeAgoText"');
        
        if (timeAgoText.isEmpty) {
          debugPrint('⚠️ [UserLocationTimeWidget] timeAgoText está vazio após formatação');
          return const SizedBox.shrink();
        }
        
        debugPrint('✅ [UserLocationTimeWidget] Exibindo time ago: "$timeAgoText"');
        
        return Text(
          timeAgoText,
          style: GoogleFonts.getFont(
            FONT_PLUS_JAKARTA_SANS,
            fontSize: 11,
            color: GlimpseColors.textSubTitle,
          ),
        );
      },
    );
  }
}
