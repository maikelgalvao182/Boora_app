# 📦 Relatório: Oportunidades de Cache Local com Hive

> **Objetivo**: Identificar dados que poderiam ser persistidos localmente usando Hive para melhorar a percepção de velocidade no app Partiu, especialmente no DiscoverScreen.

---

## 📊 Resumo Executivo

| Métrica | Valor |
|---------|-------|
| **Banco de dados local atual** | ❌ Nenhum (apenas SharedPreferences para sessão) |
| **Cache em memória** | ✅ Múltiplos serviços (GlobalCache, UserCache, LocationCache) |
| **Oportunidades identificadas** | 11 itens |
| **Impacto potencial no cold start** | Redução de 1-3s no tempo de carregamento inicial |
| **TTL recomendado para eventos** | 20 minutos (com invalidação ativa) |
| **Limite conversas** | 30-50 itens |
| **Limite notificações** | 50-100 itens |
| **Limite mensagens/chat** | 20-30 por conversa |

---

## 🧠 Filosofia Central

> **Hive não é um banco local. É um acelerador de UI.**

Sempre que ficar na dúvida:

| Pergunta | Resposta |
|----------|----------|
| "Isso ajuda o app a **parecer rápido**?" | → **Hive** |
| "Isso define a **verdade**?" | → **Firestore** |

---

## 🏆 Regras de Ouro para Cache com Hive

> Antes de implementar, grave estas regras:

| # | Regra | Motivo |
|---|-------|--------|
| 1 | **TTL longo (15-30 min) > TTL curto** | Dados stale são melhores que loading vazio |
| 2 | **Quadkey = chave, Lista = valor** | Hive não indexa. Mantenha O(1) de leitura |
| 3 | **Limites obrigatórios** | 30-50 conversas, 50-100 notificações, 20-30 msgs |
| 4 | **Dois níveis de perfil** | UserSession (estável) + UserExtended (volátil) |
| 5 | **Stream sempre soberano** | Cache é só para leitura inicial |
| 6 | **Invalidação ativa > TTL passivo** | Invalide quando: bounds mudam, stream chega, ação do usuário |

---

## 1. 🔍 Arquitetura Atual de Cache

### 1.1 Sistemas de Cache Existentes (TODOS EM MEMÓRIA)

| Serviço | Arquivo | TTL | Problema |
|---------|---------|-----|----------|
| `GlobalCacheService` | lib/core/services/global_cache_service.dart | 2-10 min | **Perdido ao fechar app** |
| `UserCacheService` | lib/core/services/user_cache_service.dart | 10 min | **Perdido ao fechar app** |
| `LocationCache` | lib/features/location/services/location_cache.dart | 15 min | **Perdido ao fechar app** |
| `MapDiscoveryService` | lib/features/home/presentation/services/map_discovery_service.dart | 30 seg | **Perdido ao fechar app** |
| `AvatarCacheService` | lib/core/services/avatar_cache_service.dart | 1h | **Perdido ao fechar app** |
| `ConversationCacheService` | lib/core/services/conversation_cache_service.dart | N/A | **Perdido ao fechar app** |

### 1.2 Único Dado Persistente Atual

| Dado | Armazenamento | Arquivo |
|------|---------------|---------|
| Sessão do usuário (UID, email, nome) | SharedPreferences | lib/core/services/session_manager.dart |
| Idioma | SharedPreferences | lib/core/services/locale_service.dart |

---

## 2. 🔴 PRIORIDADE ALTA - Impacto Crítico na UX

### 2.1 Eventos do Mapa (DiscoverScreen)

**Problema atual:**
- Cold start mostra mapa vazio por 1-3 segundos
- Toda vez que o app é reaberto, precisa buscar eventos do Firestore
- Cache LRU em memória (30s TTL) é perdido ao fechar app

**Arquivos relacionados:**
- [lib/features/home/presentation/services/map_discovery_service.dart](lib/features/home/presentation/services/map_discovery_service.dart)
- [lib/features/home/presentation/viewmodels/map_viewmodel.dart](lib/features/home/presentation/viewmodels/map_viewmodel.dart)
- [lib/features/home/presentation/widgets/google_map_view.dart](lib/features/home/presentation/widgets/google_map_view.dart)

**Dados a persistir:**
```dart
// EventLocation - dados mínimos para markers
{
  'eventId': String,
  'latitude': double,
  'longitude': double,
  'emoji': String,
  'category': String,
  'activityText': String,
  'creatorId': String,
  'timestamp': DateTime,      // Para expiração
  'quadkey': String,          // Para indexação por tile
}
```

**Estratégia sugerida:**
1. Salvar eventos por quadkey (tile do mapa)
2. **TTL de 20 minutos** com invalidação ativa
3. Mostrar cache imediatamente → atualizar com dados do Firestore
4. Limpeza agressiva apenas para eventos realmente expirados

> 💡 **Por que TTL longo?** Eventos não mudam de lugar. Mapa vazio no cold start é **muito pior** do que marker levemente desatualizado. Invalidação natural ocorre quando: bounds mudam, usuário mexe no mapa, ou stream Firestore chega.

**⚠️ Quadkey + Hive: Cuidado com performance**

Hive **não indexa** internamente. A estratégia correta é:
```dart
// ✅ CORRETO: O(1) de leitura
box.put('quadkey_123', List<EventLocation>);
final events = box.get('quadkey_123');

// ❌ ERRADO: Nunca filtrar ou varrer dentro do box
box.values.where((e) => e.quadkey == 'xyz'); // O(n) - LENTO
```

**Regra:** chave = quadkey, valor = lista pronta, TTL por quadkey.

**Impacto:** ⭐⭐⭐⭐⭐ (Elimina loading no mapa ao abrir app)

---

### 2.2 Perfil Completo do Usuário Atual

**Problema atual:**
- `SessionManager` salva apenas dados básicos (uid, name, email)
- Dados completos do perfil são buscados do Firestore a cada abertura
- Causa flicker em componentes que dependem de `AppState.currentUser`

**Arquivos relacionados:**
- [lib/core/services/session_manager.dart](lib/core/services/session_manager.dart)
- [lib/core/state/app_state.dart](lib/core/state/app_state.dart)
- [lib/features/profile/data/repositories/user_repository.dart](lib/features/profile/data/repositories/user_repository.dart)

**Dados a persistir (dois níveis):**

```dart
// 🔵 UserSession - SEMPRE em cache (crítico para UI)
{
  'uid': String,
  'name': String,
  'email': String,
  'avatarUrl': String?,
  'verified': bool,
  'radiusKm': double,
  'interests': List<String>,
}

// 🟡 UserExtended - TTL curto (5-10 min), menos crítico
{
  'bio': String?,
  'geoLocation': GeoPoint?,
  'createdAt': DateTime,
  'advancedFilters': Map<String, dynamic>,
  // ... dados menos acessados
}
```

> 💡 **Por que dois níveis?**
> - Reduz risco de inconsistência visual (UserSession é estável)
> - Evita rewrite frequente no Hive (UserExtended muda mais)
> - UI crítica sempre tem dados, dados secundários carregam async

**Impacto:** ⭐⭐⭐⭐⭐ (Evita loading em Profile tab e componentes de usuário)

---

### 2.3 Lista de Conversas

**Problema atual:**
- Tab Conversations mostra skeleton/loading toda vez que é aberta
- Usa `GlobalCacheService` com TTL curto
- Lista é buscada do Firestore mesmo que não tenha mudado

**Arquivos relacionados:**
- [lib/features/conversations/presentation/viewmodels/conversations_viewmodel.dart](lib/features/conversations/presentation/viewmodels/conversations_viewmodel.dart)
- [lib/features/conversations/data/repositories/chat_repository.dart](lib/features/conversations/data/repositories/chat_repository.dart)

**Dados a persistir:**
```dart
// ConversationItem
{
  'eventId': String,
  'eventName': String,
  'emoji': String,
  'lastMessage': String?,
  'lastMessageTime': DateTime?,
  'unreadCount': int,
  'participants': List<String>,
}
```

> ⚠️ **LIMITE OBRIGATÓRIO: 30-50 conversas**
> - Não cacheie lista inteira sem limite
> - Mais do que isso: ocupa disco, não melhora UX, vira dívida técnica
> - Ordenar por `lastMessageTime` e manter apenas as mais recentes

**Impacto:** ⭐⭐⭐⭐ (Tab Conversations carrega instantaneamente)

---

### 2.4 Notificações

**Problema atual:**
- Tab Notifications mostra loading toda abertura
- Stream Firestore traz todas as notificações novamente
- Não há cache local

**Arquivos relacionados:**
- [lib/features/notifications/data/repositories/notifications_repository.dart](lib/features/notifications/data/repositories/notifications_repository.dart)
- [lib/features/notifications/presentation/viewmodels/notifications_view_model.dart](lib/features/notifications/presentation/viewmodels/notifications_view_model.dart)

**Dados a persistir:**
```dart
// NotificationModel
{
  'id': String,
  'type': String,
  'title': String,
  'body': String,
  'createdAt': DateTime,
  'read': bool,
  'data': Map<String, dynamic>,
}
```

> ⚠️ **LIMITE OBRIGATÓRIO: 50-100 notificações**
> - Não cacheie todas as notificações históricas
> - Ordenar por `createdAt` e manter apenas as mais recentes
> - Notificações antigas raramente são acessadas

**Impacto:** ⭐⭐⭐⭐ (Tab Notifications carrega instantaneamente)

---

## 3. 🟡 PRIORIDADE MÉDIA - Melhorias Significativas

### 3.1 Cache de Perfis de Outros Usuários

**Problema atual:**
- `UserCacheService` mantém perfis em memória (TTL 10 min)
- Ao reabrir app, precisa buscar novamente perfis de criadores de eventos
- Causa delay ao abrir EventCard

**Arquivos relacionados:**
- [lib/core/services/user_cache_service.dart](lib/core/services/user_cache_service.dart)

**Dados a persistir:**
```dart
// User básico (outros usuários)
{
  'uid': String,
  'name': String,
  'avatarUrl': String?,
  'verified': bool,
  'cachedAt': DateTime,  // TTL de 24h
}
```

**Impacto:** ⭐⭐⭐ (EventCards mostram avatar/nome instantaneamente)

---

### 3.2 Rankings de Locais

**Problema atual:**
- Tab Rankings busca do Firestore toda abertura
- Dados mudam pouco (rankings semanais/mensais)
- Poderia ter TTL de 1-2 horas

**Arquivos relacionados:**
- [lib/features/home/presentation/viewmodels/ranking_viewmodel.dart](lib/features/home/presentation/viewmodels/ranking_viewmodel.dart)
- [lib/features/home/data/services/locations_ranking_service.dart](lib/features/home/data/services/locations_ranking_service.dart)

**Impacto:** ⭐⭐⭐ (Rankings carregam instantaneamente)

---

### 3.3 Preferências do Usuário

**Problema atual:**
- Raio de busca (`radiusKm`) vem do Firestore
- Filtros avançados vêm do Firestore
- Causa delay na configuração inicial do mapa

**Arquivos relacionados:**
- [lib/features/home/presentation/controllers/radius_controller.dart](lib/features/home/presentation/controllers/radius_controller.dart)
- [lib/features/profile/data/repositories/profile_repository.dart](lib/features/profile/data/repositories/profile_repository.dart)

**Dados a persistir:**
```dart
// UserPreferences
{
  'radiusKm': double,
  'advancedFilters': Map<String, dynamic>,
  'lastCategoryFilter': String?,
  'distanceUnit': String,
}
```

**Impacto:** ⭐⭐⭐ (Configurações aplicadas instantaneamente no cold start)

---

### 3.4 Última Localização do Usuário

**Problema atual:**
- `LocationCache` guarda localização em memória (TTL 15 min)
- Cold start precisa esperar GPS
- Mapa fica sem posição inicial por alguns segundos

**Arquivos relacionados:**
- [lib/features/location/services/location_cache.dart](lib/features/location/services/location_cache.dart)
- [lib/features/location/services/location_service.dart](lib/features/location/services/location_service.dart)

**Dados a persistir:**
```dart
// LastKnownLocation
{
  'latitude': double,
  'longitude': double,
  'accuracy': double,
  'timestamp': DateTime,  // TTL de 24h
}
```

**Impacto:** ⭐⭐⭐ (Mapa centraliza instantaneamente na última posição conhecida)

---

## 4. 🟢 PRIORIDADE BAIXA - Nice to Have

### 4.1 Mensagens de Chat (Últimas 20-30)

**Problema atual:**
- Streams Firestore carregam mensagens em tempo real
- Ao abrir conversa, há delay até carregar mensagens

**Arquivos relacionados:**
- [lib/features/conversations/data/repositories/chat_repository.dart](lib/features/conversations/data/repositories/chat_repository.dart)

> ⚠️ **AVISO IMPORTANTE: Mensagem + Hive + Stream = COMPLEXO PRA CARALHO**
>
> **Só implemente se:**
> - Limite estrito: últimas **20-30 mensagens** por conversa
> - Apenas para **leitura inicial** (mostrar algo enquanto stream carrega)
> - **Stream sempre soberano** (nunca confie só no cache)
>
> **Se não conseguir garantir isso, NÃO FAÇA AGORA.**

**Estratégia (se implementar):**
1. Cache das últimas 20-30 mensagens por conversa
2. Mostrar cache imediatamente ao abrir chat
3. Stream sobrescreve cache assim que chega
4. Nunca exibir mensagem do cache como "enviada" se stream não confirmou

**Impacto:** ⭐⭐ (Complexo de implementar devido a natureza realtime)

---

### 4.2 Categorias de Eventos

**Problema atual:**
- Lista de categorias vem hardcoded ou do Firebase Remote Config
- Dados são relativamente estáticos

**Arquivos relacionados:**
- [lib/features/home/presentation/widgets/category_drawer.dart](lib/features/home/presentation/widgets/category_drawer.dart)

**Impacto:** ⭐⭐ (Já funciona bem, melhoria marginal)

---

### 4.3 Draft de Criação de Atividade

**Problema atual:**
- Se usuário sair do fluxo de criação sem publicar, perde o rascunho
- `ActivityDraft` existe apenas em memória

**Arquivos relacionados:**
- [lib/features/home/create_flow/create_flow_coordinator.dart](lib/features/home/create_flow/create_flow_coordinator.dart)

**Dados a persistir:**
```dart
// ActivityDraft
{
  'activityText': String?,
  'emoji': String?,
  'category': String?,
  'scheduledDate': DateTime?,
  'location': GeoPoint?,
  'savedAt': DateTime,
}
```

**Impacto:** ⭐ (Feature de conveniência, não velocidade)

---

## 5. 📐 Plano de Implementação Sugerido

### Fase 1: Fundação (1-2 dias)

1. **Adicionar dependências no `pubspec.yaml`:**
```yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0

dev_dependencies:
  hive_generator: ^2.0.1
  build_runner: ^2.4.6
```

2. **Inicializar Hive no `main.dart`:**
```dart
await Hive.initFlutter();
Hive.registerAdapter(EventLocationAdapter());
Hive.registerAdapter(UserAdapter());
// ... outros adapters
```

3. **Criar service base para cache:**
```dart
// lib/core/services/hive_cache_service.dart
abstract class HiveCacheService<T> {
  Future<void> save(String key, T value);
  Future<T?> get(String key);
  Future<void> delete(String key);
  Future<void> clear();
  bool isExpired(String key, Duration ttl);
}
```

### Fase 2: Cache de Eventos (2-3 dias)

1. Criar `EventLocationAdapter` para Hive
2. Criar `EventCacheBox` com indexação por quadkey
3. Modificar `MapDiscoveryService`:
   - Ler do Hive no `initialize()`
   - Salvar no Hive após fetch do Firestore
   - Estratégia "stale-while-revalidate"

### Fase 3: Cache de Perfil e Preferências (1-2 dias)

1. Criar `UserAdapter` para modelo completo
2. Modificar `SessionManager` para persistir User completo
3. Persistir preferências (raio, filtros)

### Fase 4: Cache de Conversas e Notificações (2-3 dias)

1. Criar adapters para `ConversationItem` e `NotificationModel`
2. Implementar cache com invalidação por stream
3. UI mostra cache → atualiza com dados frescos

---

## 6. 📈 Impacto Esperado

| Cenário | Tempo Atual | Tempo Esperado | Melhoria |
|---------|-------------|----------------|----------|
| Cold start → Mapa com markers | 1-3s | < 500ms | **70-85%** |
| Abrir tab Conversations | 500ms-1s | < 100ms | **80-90%** |
| Abrir tab Notifications | 500ms-1s | < 100ms | **80-90%** |
| Abrir EventCard (avatar) | 200-500ms | < 50ms | **75-90%** |
| Reabrir app após background | 1-2s | < 300ms | **70-85%** |

---

## 7. ⚠️ Considerações Importantes

### Cuidados na Implementação

1. **Sincronização com Firestore:**
   - Cache local pode ficar desatualizado
   - Usar estratégia "stale-while-revalidate"
   - Implementar invalidação por eventos (FCM, streams)

2. **Tamanho do Cache:**
   - Definir limites máximos por box
   - Implementar LRU eviction
   - Monitorar uso de storage

3. **Migração de Dados:**
   - Versionar adapters Hive
   - Tratar mudanças de schema
   - Fallback para Firestore se cache corrompido

4. **Testes:**
   - Testar cenários de cache hit/miss
   - Testar invalidação
   - Testar comportamento offline

### Alternativas ao Hive

| Banco | Prós | Contras |
|-------|------|---------|
| **Hive** | Rápido, simples, bom para Flutter | Sem queries complexas |
| **Isar** | Queries avançadas, type-safe | Mais complexo |
| **Drift (SQLite)** | SQL completo, migrations | Mais overhead |
| **SharedPreferences** | Já disponível | Limitado a key-value simples |

**Recomendação:** Hive é a melhor escolha para este caso de uso (cache de objetos simples com TTL).

---

## 8. 🎯 Quick Wins (Sem Hive)

Melhorias imediatas que podem ser feitas sem adicionar Hive:

1. **Aumentar TTL do MapDiscoveryService:**
   - De 30s para 2-5 minutos
   - Arquivo: [lib/features/home/presentation/services/map_discovery_service.dart](lib/features/home/presentation/services/map_discovery_service.dart)

2. **Persistir raio/filtros em SharedPreferences:**
   - Evita fetch do Firestore para preferências
   - Arquivo: [lib/features/home/presentation/controllers/radius_controller.dart](lib/features/home/presentation/controllers/radius_controller.dart)

3. **Cache última localização em SharedPreferences:**
   - Permite centralizar mapa instantaneamente
   - Arquivo: [lib/features/location/services/location_cache.dart](lib/features/location/services/location_cache.dart)

---

## 9. 📋 Checklist de Implementação

### Fase 1: Fundação ✅ COMPLETA
- [x] Adicionar `hive` e `hive_flutter` ao pubspec.yaml
- [x] ~~Adicionar `hive_generator`~~ (incompatível com freezed, adapters manuais)
- [x] Criar `HiveCacheService` base → [lib/core/services/cache/hive_cache_service.dart](lib/core/services/cache/hive_cache_service.dart)
- [x] Criar `HiveListCacheService` para listas com limite
- [x] Criar `HiveInitializer` → [lib/core/services/cache/hive_initializer.dart](lib/core/services/cache/hive_initializer.dart)
- [x] Inicializar Hive no `main.dart`
- [x] Criar `EventLocationCache` modelo → [lib/features/home/data/models/event_location_cache.dart](lib/features/home/data/models/event_location_cache.dart)
- [x] Criar `EventLocationCacheAdapter` manual

### Fase 2: Cache de Eventos (Alta Prioridade)
- [x] Criar `EventCacheRepository` → [lib/features/home/data/repositories/event_cache_repository.dart](lib/features/home/data/repositories/event_cache_repository.dart)
- [x] Modificar `MapDiscoveryService` para usar cache
- [x] Implementar estratégia stale-while-revalidate
- [ ] Testar cold start com cache

### Fase 3: Perfil e Preferências (Alta Prioridade)
- [ ] Criar `UserAdapter` completo
- [ ] Modificar `SessionManager` para persistir User
- [ ] Persistir `radiusKm` e filtros localmente
- [ ] Persistir última localização

### Fase 4: Conversas e Notificações (Alta Prioridade)
- [ ] Criar `ConversationItemAdapter`
- [ ] Criar `NotificationModelAdapter`
- [ ] Implementar cache com invalidação por stream
- [ ] Testar tab Conversations com cache
- [ ] Testar tab Notifications com cache

### Fase 5: Perfis de Terceiros (Média Prioridade)
- [ ] Migrar `UserCacheService` para Hive
- [ ] Implementar TTL de 24h
- [ ] Testar EventCards com cache de avatares

---

## 10. 📚 Referências

- [Hive Documentation](https://docs.hivedb.dev/)
- [Flutter Hive Tutorial](https://pub.dev/packages/hive_flutter)
- [Stale-While-Revalidate Pattern](https://web.dev/stale-while-revalidate/)

---

*Relatório gerado em: 23 de janeiro de 2026*
*Versão: 1.0*
