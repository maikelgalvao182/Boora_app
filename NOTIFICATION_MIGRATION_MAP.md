# 🔔 MAPA DE MIGRAÇÃO - SISTEMA DE NOTIFICAÇÕES

## 📋 Índice
1. [Visão Geral](#visão-geral)
2. [Estrutura de Pastas](#estrutura-de-pastas)
3. [Arquivos Core (Obrigatórios)](#arquivos-core-obrigatórios)
4. [Arquivos de UI (Widgets)](#arquivos-de-ui-widgets)
5. [Arquivos de Negócio (Services)](#arquivos-de-negócio-services)
6. [Arquivos de Dados (Repository Firestore)](#arquivos-de-dados-repository-firestore)
7. [Arquivos de Models](#arquivos-de-models)
8. [Dependências](#dependências)
9. [Configurações](#configurações)
10. [Plano de Execução](#plano-de-execução)

---

## 🎯 Visão Geral

Este documento mapeia TODOS os arquivos relacionados ao sistema de notificações push e locais do projeto **Advanced-Dating** para migração ao projeto **Partiu**.

### Características do Sistema
- ✅ **MVVM Architecture** - Separação clara View/ViewModel/Model
- ✅ **Push Notifications** - Firebase Cloud Messaging (FCM)
- ✅ **Local Notifications** - flutter_local_notifications
- ✅ **Notificações Semânticas** - Tipos estruturados com parâmetros
- ✅ **Tradução Client-Side** - Multi-idioma via i18n
- ✅ **Mascaramento VIP** - Paywall para notificações premium
- ✅ **Paginação Eficiente** - Scroll infinito com cache
- ✅ **Background Handler** - Notificações em background
- ✅ **Firestore Direto** - Sem camada API, acesso direto ao Firestore

### ⚠️ IMPORTANTE: Triggers Limpos
Os triggers específicos do Advanced-Dating (like, visit, wedding, application) **NÃO serão migrados**. Manteremos apenas a infraestrutura genérica para que você possa implementar seus próprios triggers.

---

## 📁 Estrutura de Pastas

```
lib/
├── screens/
│   └── notifications/
│       ├── controllers/                    # MVVM Controllers
│       ├── repositories/                   # Data Layer (Firestore direto)
│       ├── services/                       # Business Logic
│       ├── helpers/                        # Utilities
│       ├── viewmodels/                     # MVVM ViewModels
│       ├── widgets/                        # UI Components
│       └── simplified_notification_screen_wrapper.dart
├── models/
│   └── notification_event.dart            # Semantic Models
├── services/
│   ├── push_notification_manager.dart     # Push Manager
│   └── notification_masking_service.dart  # VIP Masking
└── widgets/
    └── skeletons/
        └── notification_list_skeleton.dart
```

**Nota:** Não haverá pasta `api/`. O Repository acessará Firestore diretamente via `cloud_firestore` package.

---

## 📦 FASE 1: Arquivos Core (Obrigatórios)

### 1.1 Models & Events
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_event.dart` | `lib/models/` | `lib/models/` | 🔴 P0 | **LIMPAR** tipos específicos (like, visit, wedding) |

**Tipos a REMOVER:**
- `like`, `visit`, `match`, `wedding_like`, `event_visit`
- `applicationSubmitted`, `applicationAccepted`, `applicationRejected`
- `newAnnouncement`, `announcementUpdated`

**Tipos a MANTER:**
- `message` (mensagens básicas)
- `alert` (alertas do sistema)
- `custom` (tipo genérico para novos eventos)

---

## 📦 FASE 2: Data Layer (Repository)

### 2.1 Repository Pattern (Firestore Direto)
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notifications_repository_interface.dart` | `lib/screens/notifications/repositories/` | `lib/screens/notifications/repositories/` | 🔴 P0 | **LIMPAR** método `sendPushNotification` |
| `notifications_repository.dart` | `lib/screens/notifications/repositories/` | `lib/screens/notifications/repositories/` | 🔴 P0 | **REESCREVER** - Acessar Firestore diretamente |

**Mudanças importantes em `notifications_repository.dart`:**

❌ **REMOVER:**
```dart
// Dependency injection da API
NotificationsRepository({NotificationsApi? notificationsApi})
    : _notificationsApi = notificationsApi ?? NotificationsApi();
final NotificationsApi _notificationsApi;

// Todos os métodos que delegam para _notificationsApi
```

✅ **ADICIONAR:**
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsRepository implements INotificationsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Implementar métodos acessando Firestore diretamente
  // Exemplo:
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> getNotificationsPaginated({
    int limit = 20,
    DocumentSnapshot? lastDocument,
    String? filterKey,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('User not authenticated');

    var query = _firestore
        .collection('Notifications')
        .where('n_receiver_id', isEqualTo: userId);
    
    if (filterKey != null) {
      query = query.where('n_type', isEqualTo: filterKey);
    }
    
    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    
    query = query.orderBy('timestamp', descending: true).limit(limit);
    
    return await query.get();
  }
}
```

**Métodos a implementar diretamente:**
- `getNotifications()` → `_firestore.collection('Notifications').where(...).snapshots()`
- `getNotificationsPaginated()` → Com paginação e filtros
- `getNotificationsPaginatedStream()` → Stream real-time
- `saveNotification()` → `_firestore.collection('Notifications').add(...)`
- `deleteUserNotifications()` → Batch delete
- `deleteNotification()` → `_firestore.collection('Notifications').doc(id).delete()`
- `readNotification()` → `_firestore.collection('Notifications').doc(id).update({'n_read': true})`

**Método a REMOVER da interface:**
- ❌ `sendPushNotification()` → Não será usado (push será feito via Cloud Functions/backend)

---

## 📦 FASE 3: Business Logic (Services)

### 3.1 Push Notification Manager
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `push_notification_manager.dart` | `lib/services/` | `lib/services/` | 🔴 P0 | **LIMPAR** tipos no switch do `translateNotificationLocally` |

**Switch cases a REMOVER:**
```dart
case 'event_visit':
case 'wedding_like':
case 'application_submitted':
case 'application_accepted':
case 'application_rejected':
case 'wedding_announcement':
case 'new_announcement':
```

**Switch cases a MANTER:**
```dart
case 'visit':      // genérico
case 'like':       // genérico
case 'message':
case 'new_message':
default:           // fallback
```

### 3.2 Notification Masking (VIP)
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_masking_service.dart` | `lib/services/` | `lib/services/` | 🟡 P1 | **LIMPAR** tipos mascaráveis ou **REMOVER** se não usar VIP |

**Se manter VIP, ajustar `maskableTypes`:**
```dart
const maskableTypes = [
  'visit',
  'like',
  // REMOVER: 'event_visit', 'wedding_like', 'new_announcement'
];
```

**Se NÃO usar VIP:** Deletar este arquivo + `notification_masking_view_model.dart`

---

## 📦 FASE 4: Presentation Layer (UI)

### 4.1 Controllers (MVVM)
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `simplified_notification_controller.dart` | `lib/screens/notifications/controllers/` | `lib/screens/notifications/controllers/` | 🔴 P0 | **LIMPAR** `mapFilterIndexToKey` |

**Filtros a REMOVER:**
```dart
case 1: return 'wedding_announcement';
case 2: return 'application';
case 3: return 'like';
case 4: return 'visit';
case 5: return 'message';
```

**Filtros a MANTER:**
```dart
case 0: return null;  // All
case 1: return 'message';  // Messages only
// Adicionar novos filtros conforme seu app
```

**Labels a AJUSTAR em `filterLabelKeys`:**
```dart
static const List<String> filterLabelKeys = [
  'filter_all',
  'filter_messages',
  // Adicionar seus filtros aqui
];
```

### 4.2 Screen Wrapper
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `simplified_notification_screen_wrapper.dart` | `lib/screens/notifications/` | `lib/screens/notifications/` | 🔴 P0 | ⚠️ Verificar DI (`DependencyProvider`) |

**Ajuste necessário:**
```dart
// Verificar se existe DependencyProvider no Partiu
// Se não, instanciar direto:
_controller ??= SimplifiedNotificationController(
  repository: NotificationsRepository(),
);
```

### 4.3 Main Screen
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `simplified_notification_screen.dart` | `lib/screens/notifications/widgets/` | `lib/screens/notifications/widgets/` | 🔴 P0 | ⚠️ Verificar `SubscriptionMonitoringService` |

**Se NÃO usar VIP:**
```dart
// Remover import e simplificar initialize:
widget.controller.initialize(true); // sempre true
```

### 4.4 Notification Items
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_item_widget.dart` | `lib/screens/notifications/widgets/` | `lib/screens/notifications/widgets/` | 🔴 P0 | **CRÍTICO** - Limpar navegação |
| `masked_notification_item_widget.dart` | `lib/screens/notifications/widgets/` | `lib/screens/notifications/widgets/` | 🟡 P1 | **OPCIONAL** - Apenas se usar VIP |

**Ajustes em `notification_item_widget.dart`:**
- Verificar `StableAvatar` (se não existir no Partiu, substituir por widget próprio)
- Verificar `ReactiveUserNameWithBadge` (mesmo caso)

### 4.5 Filters
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_horizontal_filters.dart` | `lib/screens/notifications/widgets/` | `lib/screens/notifications/widgets/` | 🔴 P0 | ✅ OK (genérico) |
| `notification_filter.dart` | `lib/screens/notifications/widgets/` | `lib/screens/notifications/widgets/` | 🔴 P0 | ✅ OK (genérico) |

### 4.6 Skeleton Loading
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_list_skeleton.dart` | `lib/widgets/skeletons/` | `lib/widgets/skeletons/` | 🔴 P0 | ✅ OK |

---

## 📦 FASE 5: Helpers & Utilities

### 5.1 Notification Routing
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `app_notifications.dart` | `lib/screens/notifications/helpers/` | `lib/screens/notifications/helpers/` | 🔴 P0 | **CRÍTICO** - Reescrever switch |

**Switch `onNotificationClick` a LIMPAR:**
```dart
// REMOVER CASES:
case 'like':
case 'visit':
case 'event_visit':
case 'wedding_like':
case 'application_submitted':
case 'application_accepted':
case 'application_rejected':
case 'targeted_announcement':
case 'wedding_announcement':
case 'new_announcement':

// MANTER:
case 'message':
case 'alert':
case 'call':  // se usar videochamada
default:
```

**Reescrever navegação para suas telas:**
```dart
case 'message':
  // Navegar para sua tela de mensagens
  break;
default:
  // Lógica genérica ou nada
  break;
```

### 5.2 Message Translator
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_message_translator.dart` | `lib/screens/notifications/helpers/` | `lib/screens/notifications/helpers/` | 🔴 P0 | **LIMPAR** switch de tipos |

**Switch `translate` a LIMPAR:**
```dart
// REMOVER:
case NOTIF_TYPE_LIKE:
case NOTIF_TYPE_VISIT:
case 'event_visit':
case NOTIF_TYPE_MATCH:
case NOTIF_TYPE_APPLICATION_SUBMITTED:
case NOTIF_TYPE_APPLICATION_ACCEPTED:
case NOTIF_TYPE_APPLICATION_REJECTED:
case NOTIF_TYPE_APPLICATION_UPDATED:
case NOTIF_TYPE_NEW_ANNOUNCEMENT:
case NOTIF_TYPE_ANNOUNCEMENT_UPDATED:
case 'announcement_deadline':
case 'review_received':

// MANTER:
case NOTIF_TYPE_MESSAGE:
case NOTIF_TYPE_ALERT:
default:
```

### 5.3 Text Sanitizer
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_text_sanitizer.dart` | `lib/screens/notifications/helpers/` | `lib/screens/notifications/helpers/` | 🔴 P0 | ✅ OK (utility genérico) |

### 5.4 VIP Access Service
| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_access_service.dart` | `lib/screens/notifications/services/` | `lib/screens/notifications/services/` | 🟡 P1 | **OPCIONAL** - Apenas se usar VIP |

---

## 📦 FASE 6: ViewModels

| Arquivo | Origem | Destino | Prioridade | Ajustes |
|---------|--------|---------|------------|---------|
| `notification_masking_view_model.dart` | `lib/viewmodels/notifications/` | `lib/viewmodels/notifications/` | 🟡 P1 | **OPCIONAL** - Apenas se usar VIP |

---

## 🔗 Dependências

### Packages Necessários (pubspec.yaml)

```yaml
dependencies:
  # Firebase Core
  firebase_core: ^3.10.0
  firebase_messaging: ^15.1.6
  firebase_auth: ^5.3.4
  cloud_firestore: ^5.5.1
  
  # Local Notifications
  flutter_local_notifications: ^18.0.1
  
  # State Management
  provider: ^6.1.2  # ou seu gerenciador preferido
  
  # Utils
  shared_preferences: ^2.3.5
  
  # UI
  google_fonts: ^6.2.1
  iconsax: ^0.0.8
  
  # Opcional (VIP)
  # purchases_flutter: ^8.2.3  # Se usar RevenueCat
```

### Verificar Compatibilidade
- ✅ Verificar se `AppLocalizations` existe no Partiu
- ✅ Verificar se `NavigationService` existe no Partiu
- ✅ Verificar se `AppState.currentUserId` existe (ou usar Firebase Auth direto)

---

## ⚙️ Configurações

### 1. Firebase Setup
```bash
# Android: google-services.json
android/app/google-services.json

# iOS: GoogleService-Info.plist
ios/Runner/GoogleService-Info.plist
```

### 2. Android Manifest
```xml
<!-- android/app/src/main/AndroidManifest.xml -->

<!-- Permissões -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.VIBRATE"/>

<!-- Meta-data -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="glimpse_high_importance" />
```

### 3. iOS Info.plist
```xml
<!-- ios/Runner/Info.plist -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### 4. Firestore Indexes
```json
// firestore.indexes.json
{
  "indexes": [
    {
      "collectionGroup": "Notifications",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "n_receiver_id", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "Notifications",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "n_receiver_id", "order": "ASCENDING" },
        { "fieldPath": "n_type", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    }
  ]
}
```

**Deploy indexes:**
```bash
firebase deploy --only firestore:indexes
```

---

## 🚀 Plano de Execução

### ETAPA 1: Preparação (1h)
1. ✅ Criar estrutura de pastas em `partiu/lib/screens/notifications/`
2. ✅ Adicionar dependências no `pubspec.yaml`
3. ✅ Configurar Firebase (google-services.json + GoogleService-Info.plist)
4. ✅ Deploy de Firestore indexes

### ETAPA 2: Models & Data (2h)
1. 🔴 Copiar `notification_event.dart` → **LIMPAR** tipos específicos
2. 🔴 Copiar `notifications_repository_interface.dart` → **LIMPAR** `sendPushNotification`
3. 🔴 **REESCREVER** `notifications_repository.dart` → Acessar Firestore diretamente (sem API layer)

### ETAPA 3: Services (2h)
1. 🔴 Copiar `push_notification_manager.dart` → **LIMPAR** switch
2. 🟡 Copiar `notification_masking_service.dart` → **OPCIONAL** (se VIP)

### ETAPA 4: Helpers (1h)
1. 🔴 Copiar `notification_message_translator.dart` → **LIMPAR** switch
2. 🔴 Copiar `notification_text_sanitizer.dart` → OK
3. 🔴 Copiar `app_notifications.dart` → **REESCREVER** switch
4. 🟡 Copiar `notification_access_service.dart` → **OPCIONAL** (se VIP)

### ETAPA 5: Controllers (1h)
1. 🔴 Copiar `simplified_notification_controller.dart` → **LIMPAR** filtros

### ETAPA 6: UI Widgets (2h)
1. 🔴 Copiar `simplified_notification_screen_wrapper.dart` → Ajustar DI
2. 🔴 Copiar `simplified_notification_screen.dart` → Ajustar VIP check
3. 🔴 Copiar `notification_item_widget.dart` → Ajustar widgets reativos
4. 🟡 Copiar `masked_notification_item_widget.dart` → **OPCIONAL** (se VIP)
5. 🔴 Copiar `notification_horizontal_filters.dart` → OK
6. 🔴 Copiar `notification_filter.dart` → OK
7. 🔴 Copiar `notification_list_skeleton.dart` → OK

### ETAPA 7: ViewModels (30min)
1. 🟡 Copiar `notification_masking_view_model.dart` → **OPCIONAL** (se VIP)

### ETAPA 8: Integração (2h)
1. ⚠️ Adicionar `PushNotificationManager.initialize()` no `main.dart`
2. ⚠️ Configurar background handler no `main.dart`
3. ⚠️ Testar permissões iOS/Android
4. ⚠️ Testar notificações foreground/background/terminated

### ETAPA 9: Traduções (1h)
1. 📝 Adicionar keys no `assets/lang/en.json`:
```json
{
  "notifications": "Notifications",
  "filter_all": "All",
  "filter_messages": "Messages",
  "notification_message": "{senderName} sent you a message",
  "notification_alert": "System notification",
  "notification_default": "New notification",
  "someone": "Someone",
  "masked_someone": "Someone",
  "no_notifications_yet": "No notifications yet"
}
```

2. 📝 Replicar para `pt.json` (português)

### ETAPA 10: Testes (2h)
1. 🧪 Testar notificação em foreground
2. 🧪 Testar notificação em background
3. 🧪 Testar notificação com app fechado (terminated)
4. 🧪 Testar navegação ao tocar notificação
5. 🧪 Testar paginação e filtros
6. 🧪 Testar refresh (pull-to-refresh)
7. 🧪 Testar delete all
8. 🧪 Testar mark as read

---

## ✅ Checklist de Migração

### Core (Obrigatório)
- [ ] `notification_event.dart` → LIMPAR tipos
- [ ] `notifications_repository_interface.dart` → LIMPAR sendPushNotification
- [ ] `notifications_repository.dart` → REESCREVER para Firestore direto
- [ ] `push_notification_manager.dart` → LIMPAR switch
- [ ] `simplified_notification_controller.dart` → LIMPAR filtros
- [ ] `notification_message_translator.dart` → LIMPAR switch
- [ ] `app_notifications.dart` → REESCREVER switch
- [ ] `notification_text_sanitizer.dart` → OK
- [ ] `simplified_notification_screen_wrapper.dart` → Ajustar DI
- [ ] `simplified_notification_screen.dart` → Ajustar VIP
- [ ] `notification_item_widget.dart` → Ajustar widgets
- [ ] `notification_horizontal_filters.dart` → OK
- [ ] `notification_filter.dart` → OK
- [ ] `notification_list_skeleton.dart` → OK

### VIP/Masking (Opcional)
- [ ] `notification_masking_service.dart` → LIMPAR tipos ou DELETAR
- [ ] `notification_masking_view_model.dart` → DELETAR se não usar VIP
- [ ] `masked_notification_item_widget.dart` → DELETAR se não usar VIP
- [ ] `notification_access_service.dart` → DELETAR se não usar VIP

### Configuração
- [ ] Firebase setup (google-services.json + GoogleService-Info.plist)
- [ ] AndroidManifest.xml (permissões)
- [ ] Info.plist (background modes)
- [ ] Firestore indexes deploy
- [ ] Dependências no pubspec.yaml
- [ ] Traduções (en.json + pt.json)

### Integração
- [ ] `main.dart` → Adicionar `PushNotificationManager.initialize()`
- [ ] `main.dart` → Adicionar background handler
- [ ] Verificar NavigationService
- [ ] Verificar AppLocalizations
- [ ] Verificar AppState/UserService

### Testes
- [ ] Foreground notification
- [ ] Background notification
- [ ] Terminated notification
- [ ] Tap navigation
- [ ] Paginação
- [ ] Filtros
- [ ] Pull-to-refresh
- [ ] Delete all
- [ ] Mark as read

---

## 🎨 Customização Futura

### Adicionar Novo Tipo de Notificação

1. **Model** (`notification_event.dart`):
```dart
enum NotificationEventType {
  // ... existentes
  customEvent('custom_event'),
}
```

2. **Translator** (`notification_message_translator.dart`):
```dart
switch (type) {
  // ... existentes
  case 'custom_event':
    translationKey = 'notification_custom_event';
    break;
}
```

3. **Push Manager** (`push_notification_manager.dart`):
```dart
switch (type) {
  // ... existentes
  case 'custom_event':
    key = 'notification_custom_event';
    break;
}
```

4. **Routing** (`app_notifications.dart`):
```dart
switch (nType) {
  // ... existentes
  case 'custom_event':
    // Sua navegação customizada
    Navigator.push(context, ...);
    break;
}
```

5. **Tradução** (`en.json`):
```json
{
  "notification_custom_event": "{senderName} triggered custom event"
}
```

---

## 📞 Suporte

### Problemas Comuns

#### 1. "Index not found" no Firestore
**Solução:** Deploy dos indexes e aguardar construção (pode levar minutos)
```bash
firebase deploy --only firestore:indexes
```

#### 2. Notificação não aparece em foreground
**Solução:** Verificar iOS presentation options no `push_notification_manager.dart`
```dart
await _messaging.setForegroundNotificationPresentationOptions(
  alert: true,
  badge: false,
  sound: true,
);
```

#### 3. Background handler não funciona
**Solução:** Verificar se handler está no top-level (fora de classes)
```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ...
}
```

#### 4. Navegação não funciona ao tocar notificação
**Solução:** Verificar se `NavigationService` está inicializado e tem context
```dart
final context = NavigationService.instance.context;
if (context != null) {
  // navegar
}
```

---

## 🏁 Conclusão

Este mapa cobre **TODOS** os arquivos relacionados a notificações push e locais. Os arquivos marcados como 🔴 **P0** são obrigatórios. Os marcados 🟡 **P1** são opcionais (VIP).

**Tempo estimado total:** 12-15 horas

**Recomendação:** Migrar em etapas, testando cada fase antes de avançar.

**Próximo passo:** Começar pela ETAPA 1 (Preparação) e seguir o plano sequencialmente.

---

**Última atualização:** 2 de dezembro de 2025
**Versão:** 1.0
**Status:** ✅ Completo e revisado
