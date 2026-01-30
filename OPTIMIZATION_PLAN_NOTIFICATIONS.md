# Especificação Técnica Revisada: Otimização de Performance (Notifications & User Store)

## Objetivo
Reduzir leituras excessivas (N+1) no Firestore e uso de recursos na tela de Notificações, mantendo dados sempre frescos via estratégia **Stale-While-Revalidate (SWR)** com cache persistente (Hive) e revalidação sob demanda (`get`) em vez de streams, com controle de concorrência.

---

## 1. Arquitetura de Dados (`users_preview`)

**Entidade de Negócio:** `UserPreviewModel`
**Source:** `users_preview/{uid}`
**Local Cache:** Hive (Box: `user_previews`)
**Envelope de Cache:** `CachedUserPreview`

### Estrutura do Envelope (Hive)
O envelope separa o dado do metadado de controle.
```dart
class CachedUserPreview {
  final UserPreviewModel data;
  final DateTime cachedAt;         // Data de gravação no disco (controle SWR local)
  final DateTime? remoteUpdatedAt; // Data de atualização do documento no server (opcional)
}

// Modelo leve apenas para preview
class UserPreviewModel {
  final String uid;
  final String? fullName; 
  final String? avatarUrl;
  final bool isVerified;
  final bool isVip;
  final String? city;
  final String? state;
  final String? country;
  // outros campos leves...
}
```

---

## 2. Implementação do Cache Persistente

### 2.1. Serviço de Cache (`UserPreviewCacheService`)
Serviço responsável por IO no Hive.

```dart
class UserPreviewCacheService {
  // ... singleton ...
  
  CachedUserPreview? getEnvelope(String uid) {
    // Retorna o envelope completo para verificar cachedAt na Store
    return _box.get(uid);
  }

  Future<void> put(String uid, UserPreviewModel user) async {
    final envelope = CachedUserPreview(
      data: user, 
      cachedAt: DateTime.now(),
      remoteUpdatedAt: null // Preencher se disponível no doc
    );
    await _cache.put(uid, envelope);
  }
}
```

---

## 3. Lógica do `UserStore` (Upgrade)

### 3.1. Modos de Operação
Distinção vital para economizar conexões/listeners.

```dart
enum UserLoadMode { 
  stream, // Mantém listener aberto (Chat 1x1, Perfil, Header)
  once    // Busca única (Listas, Notificações, Comments)
}
```

### 3.2. Fluxo SWR com Janelas de Tempo
Definição das janelas de frescor baseadas em `cachedAt`:
- **Fresh Window (0-15 min):** Usa cache sem revalidar (Zero Reads).
- **Stale Window (15-60 min):** Usa cache instantâneo e revalida em background (`get`).
- **Expired (> 60 min):** Cache considerado velho demais, força tentativa de fetch (mas pode mostrar cache enquanto carrega).

### 3.3. Algoritmo de Resolução Inteligente (`resolveUser`)

```dart
void resolveUser(String uid, {UserLoadMode mode = UserLoadMode.once}) {
  bool memoryHit = _users.containsKey(uid);
  if (memoryHit) return; // ✅ Memória é soberana

  // 1. Tenta Cache Disco (Hive)
  final envelope = UserPreviewCacheService.instance.getEnvelope(uid);
  
  if (envelope != null) {
    // ✅ Cache Hit: Populate memória imediatamente (UX Instantânea)
    _populateMemory(uid, envelope.data);
    
    // Verificação SWR
    final age = DateTime.now().difference(envelope.cachedAt);
    
    if (age.inMinutes < 15) {
       return; // ✅ Fresh! Economiza read.
    }
    // Se chegou aqui, está Stale ou Expired -> Revalidar
  }

  // 2. Revalidação (Cache Stale, Expired ou Miss)
  if (mode == UserLoadMode.stream) {
    _startPreviewListener(uid); // Comportamento legado/realtime
  } else {
    // Novo comportamento otimizado para listas
    _scheduleOneTimeFetch(uid); 
  }
}
```

---

## 4. Gerenciamento de Concorrência (Throttling)

Para evitar "Tempestade de Gets" com 20-50 usuários simultâneos no Cold Start.

### 4.1. Fila de Revalidação
No `UserStore` (ou helper class), criar fila com limite.

```dart
// Queue com limite de concorrência (ex: 4-6)
final _fetchQueue = AsyncQueue(maxConcurrent: 6);

Future<void> _scheduleOneTimeFetch(String uid) async {
  // Evitar duplicar requests em voo para mesmo UID
  if (_pendingFetches.contains(uid)) return;
  _pendingFetches.add(uid);

  _fetchQueue.add(() async {
    try {
      final doc = await firestore.collection('users_preview').doc(uid).get();
      if (doc.exists) {
         final newData = UserPreviewModel.fromFirestore(doc);
         
         // Otimização de Escrita: Só salva no Hive se mudou algo relevante
         if (envelope == null || hasChanged(envelope.data, newData)) {
             await UserPreviewCacheService.instance.put(uid, newData);
         }
         
         _populateMemory(uid, newData);
      }
    } finally {
      _pendingFetches.remove(uid);
    }
  });
}
```

---

## 5. Integração com Notificações

No `SimplifiedNotificationController`, a chamada deve ser estratégica.

```dart
// Após fetch e parsing da lista...
final senderIds = notifications.map((n) => n.senderId).toSet().toList();

// ✅ Disparar em Microtask para não competir com build da UI
Future.microtask(() {
  // Limitar prefetch aos visíveis/primeira página (ex: max 20)
  final idsToWarmup = senderIds.take(20).toList();
  UserStore.instance.warmingUpUsers(idsToWarmup);
});
```

No `UserStore`:
```dart
void warmingUpUsers(List<String> uids) {
  // Loop simples, o throttling é gerenciado pelo _scheduleOneTimeFetch
  for (final uid in uids) {
    resolveUser(uid, mode: UserLoadMode.once);
  }
}
```

---

## Próximos Passos (Checklist Final)

1.  [ ] **Modelagem:** Criar `UserPreviewModel` e `CachedUserPreview` (envelope) + Adapters Hive.
2.  [ ] **Service:** `UserPreviewCacheService` com métodos `getEnvelope` e `put`.
3.  [ ] **UserStore Core:**
    *   Implementar `resolveUser` com lógica de janelas SWR.
    *   Implementar `_scheduleOneTimeFetch` com fila de concorrência (Queue).
    *   Refatorar `getAvatarEntryNotifier` para usar `resolveUser(mode: once)` por padrão (ou parametrizável).
4.  [ ] **UserStore Optimization:**
    *   Lógica de comparação antes do update (evitar IO desnecessário no Hive).
5.  [ ] **Controller:** Aplicar `warmingUpUsers` no fetch de notificações, em microtask.
