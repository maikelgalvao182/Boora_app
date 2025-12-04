# 📦 Guia de Refatoração: Repositories Centralizados

## ✅ O que foi criado

### 1. **UserRepository** (`lib/shared/repositories/user_repository.dart`)
Centraliza todas as queries da coleção `Users`.

### 2. **EventRepository** (`lib/features/home/data/repositories/event_repository.dart`)
Centraliza todas as queries da coleção `events`.

### 3. **EventApplicationRepository** (refatorado)
Agora usa `UserRepository` para buscar dados de usuários, evitando duplicação.

---

## 🎯 Benefícios

✅ **Elimina duplicação**: Uma única fonte de verdade para queries  
✅ **Otimização de batch**: `getUsersByIds()` usa `whereIn` para buscar múltiplos usuários  
✅ **Manutenibilidade**: Mudanças em queries afetam apenas um lugar  
✅ **Testabilidade**: Repositories podem ser mockados facilmente  
✅ **Consistência**: Todas as queries retornam dados no mesmo formato  

---

## 📚 Como usar os novos Repositories

### **UserRepository**

#### Buscar um usuário
```dart
final userRepo = UserRepository();
final userData = await userRepo.getUserById('userId123');

// Retorna:
// {
//   'id': 'userId123',
//   'fullName': 'João Silva',
//   'photoUrl': 'https://...',
//   // ... outros campos
// }
```

#### Buscar múltiplos usuários (batch otimizado)
```dart
final userIds = ['user1', 'user2', 'user3'];
final usersMap = await userRepo.getUsersByIds(userIds);

// Retorna Map<userId, userData>
// { 'user1': {...}, 'user2': {...}, 'user3': {...} }
```

#### Buscar dados básicos (photoUrl + fullName)
```dart
// Um usuário
final basicInfo = await userRepo.getUserBasicInfo('userId123');

// Múltiplos usuários
final userIds = ['user1', 'user2'];
final basicInfoList = await userRepo.getUsersBasicInfo(userIds);

// Retorna List<Map> mantendo ordem original
// [
//   { 'userId': 'user1', 'photoUrl': '...', 'fullName': '...' },
//   { 'userId': 'user2', 'photoUrl': '...', 'fullName': '...' }
// ]
```

---

### **EventRepository**

#### Buscar um evento
```dart
final eventRepo = EventRepository();
final eventData = await eventRepo.getEventById('event123');
```

#### Buscar dados básicos de um evento
```dart
final basicInfo = await eventRepo.getEventBasicInfo('event123');

// Retorna campos já parseados:
// {
//   'id': 'event123',
//   'emoji': '🏀',
//   'activityText': 'jogar basquete',
//   'locationName': 'Quadra do Parque',
//   'scheduleDate': DateTime(...),  // Já convertido de Timestamp
//   'privacyType': 'open',
//   'createdBy': 'userId123'
// }
```

#### Buscar dados completos
```dart
final fullInfo = await eventRepo.getEventFullInfo('event123');

// Retorna todos os campos originais + campos parseados
```

#### Buscar múltiplos eventos (batch)
```dart
final eventIds = ['event1', 'event2', 'event3'];
final eventsMap = await eventRepo.getEventsByIds(eventIds);
```

---

## 🔄 Como migrar código existente

### ❌ ANTES (código duplicado)
```dart
// Em 20+ arquivos diferentes:
final userDoc = await FirebaseFirestore.instance
    .collection('Users')
    .doc(userId)
    .get();

if (userDoc.exists) {
  final userData = userDoc.data()!;
  final fullName = userData['fullName'] as String?;
  final photoUrl = userData['photoUrl'] as String?;
}
```

### ✅ DEPOIS (reutilizável)
```dart
final userRepo = UserRepository();
final basicInfo = await userRepo.getUserBasicInfo(userId);

final fullName = basicInfo?['fullName'];
final photoUrl = basicInfo?['photoUrl'];
```

---

### ❌ ANTES (N+1 queries)
```dart
final results = <Map<String, dynamic>>[];

for (final userId in userIds) {
  final userDoc = await FirebaseFirestore.instance
      .collection('Users')
      .doc(userId)
      .get();
  
  if (userDoc.exists) {
    results.add(userDoc.data()!);
  }
}
```

### ✅ DEPOIS (batch otimizado)
```dart
final userRepo = UserRepository();
final results = await userRepo.getUsersBasicInfo(userIds);

// Uma única query (ou múltiplas de 10 em 10 se necessário)
```

---

### ❌ ANTES (parsing manual)
```dart
final eventDoc = await FirebaseFirestore.instance
    .collection('events')
    .doc(eventId)
    .get();

final eventData = eventDoc.data()!;
final locationData = eventData['location'] as Map<String, dynamic>?;
final locationName = locationData?['locationName'] as String?;

final scheduleData = eventData['schedule'] as Map<String, dynamic>?;
final dateTimestamp = scheduleData?['date'] as Timestamp?;
final scheduleDate = dateTimestamp?.toDate();
```

### ✅ DEPOIS (campos já parseados)
```dart
final eventRepo = EventRepository();
final basicInfo = await eventRepo.getEventBasicInfo(eventId);

final locationName = basicInfo?['locationName'];
final scheduleDate = basicInfo?['scheduleDate']; // Já é DateTime
```

---

## 🔍 Arquivos que devem ser migrados

### Alta prioridade (muita duplicação)
- `lib/services/location/location_query_service.dart`
- `lib/shared/stores/avatar_store.dart`
- `lib/shared/stores/user_store.dart`
- `lib/shared/services/auth/social_auth.dart`
- `lib/features/profile/presentation/viewmodels/image_upload_view_model.dart`
- `lib/features/profile/presentation/controllers/profile_controller.dart`

### Busca padrão a substituir
```dart
// Buscar por estas queries:
FirebaseFirestore.instance.collection('Users')
FirebaseFirestore.instance.collection('events')
_firestore.collection('Users')
_firestore.collection('events')
```

---

## 🧪 Exemplo de uso em um Controller

```dart
import 'package:partiu/shared/repositories/user_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';

class MyController extends ChangeNotifier {
  final UserRepository _userRepo;
  final EventRepository _eventRepo;

  MyController({
    UserRepository? userRepo,
    EventRepository? eventRepo,
  })  : _userRepo = userRepo ?? UserRepository(),
        _eventRepo = eventRepo ?? EventRepository();

  Future<void> loadData() async {
    // Buscar evento
    final eventData = await _eventRepo.getEventBasicInfo(eventId);
    
    // Buscar criador
    final creatorData = await _userRepo.getUserBasicInfo(
      eventData?['createdBy']
    );
    
    // Buscar participantes em batch
    final participantIds = ['user1', 'user2', 'user3'];
    final participants = await _userRepo.getUsersBasicInfo(participantIds);
  }
}
```

---

## 📊 Métricas de impacto

**Antes da refatoração:**
- 30+ locais com `collection('Users')`
- N+1 queries em loops
- Parsing manual repetido

**Depois da refatoração:**
- 1 único local para queries de Users
- Batch queries otimizadas
- Parsing centralizado

---

## ⚡ Performance: N+1 → Batch Queries

### Cenário: Buscar 50 participantes de um evento

#### ❌ ANTES (N+1)
```dart
// 1 query para applications + 50 queries para users = 51 queries
for (final app in applications) {
  final userDoc = await firestore.collection('Users').doc(app.userId).get();
}
```
**Tempo estimado:** ~5-10 segundos (depende de latência)

#### ✅ DEPOIS (Batch)
```dart
// 1 query para applications + 5 queries para users (10 por vez) = 6 queries
final users = await userRepo.getUsersBasicInfo(userIds);
```
**Tempo estimado:** ~1-2 segundos

**Melhoria: 5x mais rápido** 🚀

---

## 🎓 Boas práticas

1. **Sempre injete o repository no construtor** para facilitar testes
2. **Use batch queries** quando buscar múltiplos documentos
3. **Prefira `getBasicInfo()`** se só precisa de photoUrl + fullName
4. **Use `watch*()` streams** para dados em tempo real
5. **Não crie instâncias inline**, passe via DI ou construtor

---

## ✅ Checklist de migração

- [x] UserRepository criado
- [x] EventRepository criado
- [x] EventApplicationRepository refatorado
- [x] EventCardController refatorado
- [ ] Migrar `location_query_service.dart`
- [ ] Migrar `avatar_store.dart`
- [ ] Migrar `user_store.dart`
- [ ] Migrar `social_auth.dart`
- [ ] Migrar viewmodels de profile
- [ ] Atualizar testes unitários

---

## 🧪 Como testar

```dart
// Mock para testes
class MockUserRepository extends Mock implements UserRepository {}

test('should load user data', () async {
  final mockUserRepo = MockUserRepository();
  
  when(mockUserRepo.getUserBasicInfo(any))
      .thenAnswer((_) async => {
        'userId': 'test123',
        'fullName': 'Test User',
        'photoUrl': 'test.jpg',
      });

  final controller = MyController(userRepo: mockUserRepo);
  await controller.loadData();
  
  expect(controller.userName, 'Test User');
});
```

---

## 📝 Próximos passos

1. Migrar arquivos de alta prioridade
2. Adicionar testes unitários para repositories
3. Criar repository para outras coleções se necessário (Messages, Chats, etc)
4. Documentar padrões de uso no onboarding da equipe
