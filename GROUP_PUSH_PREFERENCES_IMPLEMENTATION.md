# 🔔 Implementação de Preferências Push por Grupo

## 📋 Visão Geral

Sistema para permitir que usuários silenciem notificações push específicas por grupo/evento, mantendo controle granular sobre diferentes tipos de notificações.

## 🎯 Estrutura Atual vs. Nova

### ❌ Atual
```
push_preferences: {
  global: true,
  chat_event: true,
  activity_updates: true
}
```

### ✅ Nova Estrutura
```typescript
push_preferences: {
  // Globais (existentes)
  global: true,
  chat_event: true,
  activity_updates: true,
  
  // Por grupo específico (NOVO)
  groups: {
    "{eventId}": {
      muted: false,        // Silencia TUDO do grupo
      chat: true,          // Chat específico do grupo
      activities: true     // Atividades específicas do grupo
    }
  }
}
```

## 🔄 Lógica de Prioridade

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Global OFF    │ -> │   Bloqueia TUDO  │ -> │   Não envia     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
           │
           ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Categoria OFF  │ -> │ Bloqueia tipo X  │ -> │   Não envia     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
           │
           ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Grupo Muted   │ -> │ Bloqueia grupo Y │ -> │   Não envia     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
           │
           ▼
┌─────────────────┐
│   Envia Push    │
└─────────────────┘
```

## 🏗️ Implementações Necessárias

### 1. Backend (Cloud Functions)

#### A. Atualizar `pushDispatcher.ts`

```typescript
export async function sendPush({
  userId,
  event,
  data,
  silent = false,
}: SendPushParams): Promise<void> {
  try {
    // Determinar preferenceType automaticamente baseado no event
    const preferenceType = getPreferenceTypeForEvent(event);
    
    // ... código existente de validação global e categoria ...
    
    // 🆕 NOVA VALIDAÇÃO: Verificar se grupo está mutado
    const eventId = data.event_id || data.activity_id;
    if (eventId && await isGroupMuted(userId, eventId, preferenceType)) {
      console.log(`🔕 [PushDispatcher] Grupo ${eventId} mutado para ${userId}`);
      return;
    }
    
    // ... continua com o envio ...
  } catch (error) {
    // ... tratamento de erro ...
  }
}

/**
 * 🔕 Verifica se as notificações do grupo estão silenciadas
 */
async function isGroupMuted(
  userId: string, 
  eventId: string, 
  type: PushPreferenceType
): Promise<boolean> {
  try {
    const userDoc = await admin.firestore()
      .collection("Users")
      .doc(userId)
      .get();
      
    const groupPrefs = userDoc.data()?.advancedSettings?.push_preferences?.groups?.[eventId];
    
    if (!groupPrefs) return false; // Não mutado se não existir configuração
    
    // Verificar se grupo está completamente mutado
    if (groupPrefs.muted === true) return true;
    
    // Verificar categoria específica do grupo
    if (type === "chat_event" && groupPrefs.chat === false) return true;
    if (type === "activity_updates" && groupPrefs.activities === false) return true;
    
    return false;
  } catch (error) {
    console.warn(`⚠️ [PushDispatcher] Erro ao verificar grupo mutado: ${error}`);
    return false; // Em caso de erro, não bloqueia
  }
}
```

### 2. Flutter Services

#### A. Criar `group_push_preferences_service.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/managers/session_manager.dart';

/// Categorias de notificações por grupo
enum GroupPushCategory { chat, activities }

/// Service para gerenciar preferências de push por grupo específico
class GroupPushPreferencesService {
  static const String _collectionPath = 'Users';
  static const String _preferencesPath = 'advancedSettings.push_preferences.groups';
  
  /// Silencia/desilencia todas as notificações de um grupo
  static Future<void> setGroupMuted(String eventId, bool muted) async {
    final userId = SessionManager.instance.currentUserId;
    if (userId == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection(_collectionPath)
          .doc(userId)
          .update({
        '$_preferencesPath.$eventId.muted': muted,
      });
      
      debugPrint('🔔 [GroupPushPrefs] Grupo $eventId ${muted ? 'silenciado' : 'reativado'}');
    } catch (e) {
      debugPrint('❌ [GroupPushPrefs] Erro ao atualizar mute: $e');
      rethrow;
    }
  }
  
  /// Verifica se grupo está completamente mutado
  static bool isGroupMuted(String eventId, Map<String, dynamic>? preferences) {
    return preferences?['groups']?[eventId]?['muted'] ?? false;
  }
  
  /// Silencia categoria específica de um grupo (chat ou atividades)
  static Future<void> setGroupCategoryEnabled(
    String eventId, 
    GroupPushCategory category, 
    bool enabled
  ) async {
    final userId = SessionManager.instance.currentUserId;
    if (userId == null) return;
    
    final categoryKey = category == GroupPushCategory.chat ? 'chat' : 'activities';
    
    try {
      await FirebaseFirestore.instance
          .collection(_collectionPath)
          .doc(userId)
          .update({
        '$_preferencesPath.$eventId.$categoryKey': enabled,
      });
      
      debugPrint('🔔 [GroupPushPrefs] $categoryKey do grupo $eventId: $enabled');
    } catch (e) {
      debugPrint('❌ [GroupPushPrefs] Erro ao atualizar categoria: $e');
      rethrow;
    }
  }
  
  /// Verifica se categoria específica está habilitada
  static bool isGroupCategoryEnabled(
    String eventId, 
    GroupPushCategory category,
    Map<String, dynamic>? preferences
  ) {
    final categoryKey = category == GroupPushCategory.chat ? 'chat' : 'activities';
    return preferences?['groups']?[eventId]?[categoryKey] ?? true; // Default: habilitado
  }
  
  /// Remove todas as preferências de um grupo (quando sai do grupo)
  static Future<void> removeGroupPreferences(String eventId) async {
    final userId = SessionManager.instance.currentUserId;
    if (userId == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection(_collectionPath)
          .doc(userId)
          .update({
        '$_preferencesPath.$eventId': FieldValue.delete(),
      });
      
      debugPrint('🔔 [GroupPushPrefs] Preferências do grupo $eventId removidas');
    } catch (e) {
      debugPrint('❌ [GroupPushPrefs] Erro ao remover preferências: $e');
      // Não re-throw, pois é operação de limpeza
    }
  }
}
```

### 3. Atualizar Controller do Grupo

#### A. Modificar `group_info_controller.dart`

```dart
class GroupInfoController extends ChangeNotifier {
  // ... código existente ...
  
  /// Verifica se notificações do grupo estão silenciadas
  bool get isMuted => GroupPushPreferencesService.isGroupMuted(
    eventId, 
    SessionManager.instance.currentUser?.pushPreferences
  );
  
  /// Toggle do switch de silenciar notificações
  Future<void> toggleMute(bool value) async {
    try {
      // 1. Atualizar no Firestore
      await GroupPushPreferencesService.setGroupMuted(eventId, value);
      
      // 2. Atualizar usuário local (Optimistic Update)
      final user = SessionManager.instance.currentUser;
      if (user != null) {
        final newPrefs = Map<String, dynamic>.from(user.pushPreferences ?? {});
        newPrefs['groups'] ??= <String, dynamic>{};
        newPrefs['groups'][eventId] ??= <String, dynamic>{};
        newPrefs['groups'][eventId]['muted'] = value;
        
        final updatedUser = user.copyWith(pushPreferences: newPrefs);
        await SessionManager.instance.saveUser(updatedUser);
      }
      
      // 3. Atualizar UI
      notifyListeners();
      
      // 4. Feedback visual
      final i18n = AppLocalizations.of(context);
      ToastService.showSuccess(
        message: value 
          ? (i18n.translate('group_notifications_muted') ?? 'Notificações silenciadas para este grupo')
          : (i18n.translate('group_notifications_unmuted') ?? 'Notificações reativadas para este grupo')
      );
      
      debugPrint('🔔 [GroupInfo] Notificações do grupo $eventId ${value ? 'silenciadas' : 'reativadas'}');
      
    } catch (e) {
      debugPrint('❌ [GroupInfo] Erro ao atualizar preferências: $e');
      
      final i18n = AppLocalizations.of(context);
      ToastService.showError(
        message: i18n.translate('error_updating_preferences') ?? 'Erro ao atualizar preferências'
      );
    }
  }
  
  /// Limpa preferências ao sair do grupo
  Future<void> _cleanupGroupPreferences() async {
    try {
      await GroupPushPreferencesService.removeGroupPreferences(eventId);
    } catch (e) {
      debugPrint('⚠️ [GroupInfo] Erro ao limpar preferências: $e');
      // Não bloqueia operação principal
    }
  }
  
  /// Método de sair do grupo (atualizar existente)
  Future<void> leaveGroup() async {
    try {
      // ... código existente de sair do grupo ...
      
      // Limpar preferências específicas do grupo
      await _cleanupGroupPreferences();
      
      // ... resto da lógica ...
    } catch (e) {
      // ... tratamento de erro ...
    }
  }
}
```

### 4. Estrutura de Validação no Backend

```typescript
/**
 * 🎯 Fluxo completo de validação de preferências
 */
function shouldSendPush(
  userId: string,
  event: PushEvent,
  eventId?: string,
  preferenceType: PushPreferenceType,
  globalPreferences: any,
  groupPreferences: any
): boolean {
  // 1. ❌ Global desabilitado?
  if (globalPreferences?.global === false) {
    console.log('🔕 Global push desabilitado');
    return false;
  }
  
  // 2. ❌ Categoria desabilitada?
  if (globalPreferences?.[preferenceType] === false) {
    console.log(`🔕 Categoria ${preferenceType} desabilitada`);
    return false;
  }
  
  // 3. ❌ Grupo existe e está completamente mutado?
  if (eventId && groupPreferences?.[eventId]?.muted === true) {
    console.log(`🔕 Grupo ${eventId} completamente mutado`);
    return false;
  }
  
  // 4. ❌ Categoria específica do grupo desabilitada?
  if (eventId && groupPreferences?.[eventId]) {
    if (preferenceType === 'chat_event' && groupPreferences[eventId].chat === false) {
      console.log(`🔕 Chat do grupo ${eventId} silenciado`);
      return false;
    }
    
    if (preferenceType === 'activity_updates' && groupPreferences[eventId].activities === false) {
      console.log(`🔕 Atividades do grupo ${eventId} silenciadas`);
      return false;
    }
  }
  
  // ✅ Pode enviar
  console.log(`✅ Push autorizado para ${userId} (${event})`);
  return true;
}
```

## 📊 Exemplos de Uso

### Cenário 1: Usuário silencia grupo específico
```dart
// User silencia notificações do evento "party123"
await GroupPushPreferencesService.setGroupMuted("party123", true);

// Resultado: Não recebe NENHUMA notificação deste grupo
// ❌ chat_message (party123)
// ❌ activity_join_request (party123)  
// ❌ activity_heating_up (party123)
```

### Cenário 2: Usuário silencia apenas chat do grupo
```dart
// User mantém atividades mas silencia chat
await GroupPushPreferencesService.setGroupCategoryEnabled(
  "party123", 
  GroupPushCategory.chat, 
  false
);

// Resultado:
// ❌ chat_message (party123)
// ✅ activity_join_request (party123)  
// ✅ activity_heating_up (party123)
```

### Cenário 3: Configuração global desabilitada
```dart
// User desabilita globalmente chat
await PushPreferencesService.setEnabled(PushType.chatEvent, false);

// Resultado: Não recebe chat de NENHUM grupo
// ❌ chat_message (todos os grupos)
// ✅ activity_* (todos os grupos ainda funcionam)
```

## 🎯 Benefícios da Implementação

### ✅ Vantagens
- **Controle granular**: Global → Categoria → Grupo específico
- **UX intuitiva**: Switch simples por grupo na tela de info
- **Performance**: Validação rápida no backend com early returns
- **Flexibilidade**: Usuário escolhe o nível de controle desejado
- **Compatibilidade**: Mantém estrutura existente intacta
- **Limpeza automática**: Remove preferências ao sair do grupo

### 📋 Estrutura Final de Configurações

```
Configurações de Push
├── 🌍 Globais (app_section_card.dart)
│   ├── global: true/false
│   ├── chat_event: true/false
│   └── activity_updates: true/false
│
└── 🎯 Por Grupo (group_info_screen.dart)
    └── groups: {
          "event123": {
            muted: false,        // Switch principal da tela
            chat: true,          // Futuro: configuração avançada
            activities: true     // Futuro: configuração avançada
          }
        }
```

## 🚀 Próximos Passos

1. **Implementar backend**: Atualizar `pushDispatcher.ts` com validação por grupo
2. **Criar service**: Implementar `GroupPushPreferencesService`
3. **Atualizar controller**: Modificar `GroupInfoController` 
4. **Testar fluxos**: Validar todos os cenários de preferências
5. **Adicionar i18n**: Incluir strings de tradução necessárias
6. **Documentar**: Atualizar documentação de notificações

## ⚠️ Considerações Técnicas

- **Migration**: Estrutura é aditiva, não quebra dados existentes
- **Performance**: Usar índices no Firestore para queries rápidas
- **Cleanup**: Remover preferências ao usuário sair do grupo
- **Fallbacks**: Em caso de erro, não bloquear notificações (fail-open)
- **Cache**: Considerar cache local para preferências frequentes

---
*Documento criado em: 14 de dezembro de 2025*