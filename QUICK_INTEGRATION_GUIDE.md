# ⚡ GUIA RÁPIDO DE INTEGRAÇÃO

> Como integrar os triggers de notificação no seu código existente

---

## 🎯 PASSO 1: INICIALIZAR SERVIÇOS (DI/Provider)

```dart
// lib/di/service_locator.dart ou similar

import 'package:get_it/get_it.dart';
import 'package:partiu/features/notifications/repositories/notifications_repository.dart';
import 'package:partiu/features/notifications/services/activity_notification_service.dart';
import 'package:partiu/features/profile/repositories/profile_view_repository.dart';

final getIt = GetIt.instance;

void setupServices() {
  // Repository de notificações
  getIt.registerLazySingleton<NotificationsRepository>(
    () => NotificationsRepository(),
  );
  
  // Service de notificações de atividades
  getIt.registerLazySingleton<ActivityNotificationService>(
    () => ActivityNotificationService(
      notificationRepository: getIt<NotificationsRepository>(),
    ),
  );
  
  // Repository de visualizações de perfil
  getIt.registerLazySingleton<ProfileViewRepository>(
    () => ProfileViewRepository(),
  );
}
```

---

## 🎯 PASSO 2: INTEGRAR COM CRIAÇÃO DE ATIVIDADES

```dart
// lib/features/activities/services/activity_service.dart

import 'package:partiu/features/notifications/services/activity_notification_service.dart';

class ActivityService {
  final ActivityNotificationService _notificationService;
  
  ActivityService({
    required ActivityNotificationService notificationService,
  }) : _notificationService = notificationService;
  
  Future<void> createActivity(ActivityModel activity) async {
    try {
      // 1. Salva atividade no Firestore
      await FirebaseFirestore.instance
          .collection('Events')
          .add(activity.toJson());
      
      // 2. ⚡ DISPARA NOTIFICAÇÃO PARA USUÁRIOS PRÓXIMOS
      await _notificationService.notifyActivityCreated(activity);
      
      print('✅ Atividade criada e notificações enviadas');
    } catch (e) {
      print('❌ Erro ao criar atividade: $e');
      rethrow;
    }
  }
}
```

---

## 🎯 PASSO 3: INTEGRAR COM PEDIDOS DE ENTRADA

```dart
// Quando usuário pede para entrar em atividade privada

Future<void> requestToJoinActivity(
  ActivityModel activity,
  String userId,
) async {
  // 1. Adiciona à lista de pending approvals
  await FirebaseFirestore.instance
      .collection('Events')
      .doc(activity.id)
      .update({
    'pendingApprovalIds': FieldValue.arrayUnion([userId]),
  });
  
  // 2. Busca dados do solicitante
  final userDoc = await FirebaseFirestore.instance
      .collection('Users')
      .doc(userId)
      .get();
  
  final userName = userDoc.data()?['fullname'] ?? 'Usuário';
  
  // 3. ⚡ NOTIFICA O DONO
  await getIt<ActivityNotificationService>().notifyJoinRequest(
    activity: activity,
    requesterId: userId,
    requesterName: userName,
  );
}
```

---

## 🎯 PASSO 4: INTEGRAR COM APROVAÇÃO/REJEIÇÃO

```dart
// Quando dono aprova pedido
Future<void> approveJoinRequest(
  ActivityModel activity,
  String userId,
) async {
  // 1. Move de pending para participants
  await FirebaseFirestore.instance
      .collection('Events')
      .doc(activity.id)
      .update({
    'pendingApprovalIds': FieldValue.arrayRemove([userId]),
    'participantIds': FieldValue.arrayUnion([userId]),
  });
  
  // 2. ⚡ NOTIFICA USUÁRIO APROVADO
  await getIt<ActivityNotificationService>().notifyJoinApproved(
    activity: activity,
    approvedUserId: userId,
  );
}

// Quando dono rejeita pedido
Future<void> rejectJoinRequest(
  ActivityModel activity,
  String userId,
) async {
  // 1. Remove de pending
  await FirebaseFirestore.instance
      .collection('Events')
      .doc(activity.id)
      .update({
    'pendingApprovalIds': FieldValue.arrayRemove([userId]),
  });
  
  // 2. ⚡ NOTIFICA USUÁRIO REJEITADO
  await getIt<ActivityNotificationService>().notifyJoinRejected(
    activity: activity,
    rejectedUserId: userId,
  );
}
```

---

## 🎯 PASSO 5: INTEGRAR COM ENTRADA EM ATIVIDADE ABERTA

```dart
// Quando alguém entra em atividade open
Future<void> joinOpenActivity(
  ActivityModel activity,
  String userId,
) async {
  // 1. Adiciona aos participantes
  await FirebaseFirestore.instance
      .collection('Events')
      .doc(activity.id)
      .update({
    'participantIds': FieldValue.arrayUnion([userId]),
  });
  
  // 2. Busca dados do participante
  final userDoc = await FirebaseFirestore.instance
      .collection('Users')
      .doc(userId)
      .get();
  
  final userName = userDoc.data()?['fullname'] ?? 'Usuário';
  
  // 3. ⚡ NOTIFICA O DONO
  await getIt<ActivityNotificationService>().notifyNewParticipant(
    activity: activity,
    participantId: userId,
    participantName: userName,
  );
  
  // 4. Verifica threshold "heating up"
  final updatedActivity = await _getActivity(activity.id);
  final newCount = updatedActivity.participantCount;
  
  if ([3, 5, 10].contains(newCount)) {
    await getIt<ActivityNotificationService>().notifyActivityHeatingUp(
      activity: updatedActivity,
      currentCount: newCount,
    );
  }
}
```

---

## 🎯 PASSO 6: INTEGRAR COM CANCELAMENTO

```dart
// Quando dono cancela atividade
Future<void> cancelActivity(String activityId) async {
  // 1. Busca atividade
  final activity = await _getActivity(activityId);
  
  // 2. Marca como cancelada no Firestore
  await FirebaseFirestore.instance
      .collection('Events')
      .doc(activityId)
      .update({
    'isCanceled': true,
    'canceledAt': FieldValue.serverTimestamp(),
  });
  
  // 3. ⚡ NOTIFICA TODOS OS PARTICIPANTES
  await getIt<ActivityNotificationService>().notifyActivityCanceled(activity);
}
```

---

## 🎯 PASSO 7: INTEGRAR VISUALIZAÇÕES DE PERFIL

```dart
// lib/features/profile/screens/profile_screen.dart

class ProfileScreen extends StatefulWidget {
  final String profileUserId;
  
  const ProfileScreen({required this.profileUserId});
  
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileViewRepo = ProfileViewRepository();
  
  @override
  void initState() {
    super.initState();
    
    // ⚡ REGISTRA VISUALIZAÇÃO AO ABRIR PERFIL
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordProfileView();
    });
  }
  
  Future<void> _recordProfileView() async {
    await _profileViewRepo.recordProfileView(
      viewedUserId: widget.profileUserId,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    // ... UI do perfil
  }
}
```

---

## 🎯 PASSO 8: DEPLOY DA CLOUD FUNCTION

```bash
# 1. Instalar dependências
cd functions
npm install

# 2. Testar localmente
npm run serve
# Acesse: http://localhost:5001/YOUR-PROJECT/us-central1/processProfileViewNotifications

# 3. Deploy para produção
npm run deploy

# 4. Verificar logs
firebase functions:log --only processProfileViewNotifications
```

---

## 🎯 PASSO 9: CONFIGURAR ÍNDICES FIRESTORE

Criar arquivo `firestore.indexes.json` na raiz do projeto:

```json
{
  "indexes": [
    {
      "collectionGroup": "ProfileViews",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "viewedUserId", "order": "ASCENDING" },
        { "fieldPath": "notified", "order": "ASCENDING" },
        { "fieldPath": "viewedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "ProfileViews",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "notified", "order": "ASCENDING" },
        { "fieldPath": "viewedAt", "order": "DESCENDING" }
      ]
    }
  ]
}
```

Deploy:
```bash
firebase deploy --only firestore:indexes
```

---

## 🎯 PASSO 10: TESTAR

### Teste 1: Criar Atividade
```dart
final activity = ActivityModel(
  id: 'test-123',
  name: 'Pizza e Conversa',
  emoji: '🍕',
  latitude: -23.5505,
  longitude: -46.6333,
  // ... outros campos
);

await getIt<ActivityNotificationService>().notifyActivityCreated(activity);

// ✅ Verificar: Usuários próximos receberam notificação?
```

### Teste 2: Visualização de Perfil
```dart
await getIt<ProfileViewRepository>().recordProfileView(
  viewedUserId: 'user-456',
);

// ✅ Verificar: View foi registrada em ProfileViews?
```

### Teste 3: Cloud Function Manual
```bash
curl -X POST http://localhost:5001/YOUR-PROJECT/us-central1/processProfileViewNotificationsHttp

# ✅ Verificar: Notificação agregada foi criada?
```

---

## 📝 CHECKLIST DE INTEGRAÇÃO

- [ ] Serviços registrados no DI
- [ ] Trigger de criação integrado
- [ ] Triggers de aprovação/rejeição integrados
- [ ] Trigger de entrada aberta integrado
- [ ] Trigger de cancelamento integrado
- [ ] Visualizações de perfil registradas
- [ ] Cloud Function deployada
- [ ] Índices Firestore criados
- [ ] Testes end-to-end realizados
- [ ] Logs verificados em produção

---

## 🐛 DEBUGGING

### Problema: Notificações não chegam

```dart
// Adicionar logs no trigger
print('[ActivityCreatedTrigger] Usuários próximos: ${nearbyUsers.length}');
print('[ActivityCreatedTrigger] Notificações enviadas');
```

### Problema: Cloud Function não roda

```bash
# Ver logs
firebase functions:log --only processProfileViewNotifications

# Testar localmente
npm run serve
```

### Problema: Query geoespacial lenta

```dart
// TODO: Implementar geoflutterfire
// Por enquanto usa query básica (OK para < 1000 usuários)
```

---

## 🎉 PRONTO!

Seu sistema de notificações está integrado e funcionando. 

**Próximo passo**: Monitorar métricas de engajamento! 📊

---

**Dúvidas?** Consulte `ACTIVITY_NOTIFICATIONS_IMPLEMENTATION.md`
