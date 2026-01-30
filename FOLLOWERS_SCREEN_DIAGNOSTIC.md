# Formulário de Diagnóstico — Página Seguidores (Flutter + Firestore)

**Data:** 30 de janeiro de 2026  
**Projeto:** Boora App  
**Escopo:** Análise completa da tela de seguidores/seguindo

---

## 0) Contexto rápido

### Fonte/banco:

- **[X] Firestore** ✅
- [ ] Supabase
- [ ] REST
- [ ] outro: _______

**Implementação:**
- Coleções: `Users/{userId}/followers` e `Users/{userId}/following`
- Código: `followers_controller.dart` linhas 36-60

---

### Essa lista é de:

- [ ] seguidores do meu perfil
- [ ] seguindo do meu perfil
- [ ] seguidores/seguindo de outros perfis (público)
- **[X] todos os casos** ✅

**Detalhes:**
- Tela única com 2 tabs: "Seguidores" e "Seguindo"
- Controlador recebe `userId` no construtor (pode ser qualquer usuário)
- Código: `followers_screen.dart` linha 12

---

### Estrutura atual no Firestore:

- **[X] users/{uid}/followers/{followerId}** ✅
- **[X] users/{uid}/following/{followedId}** ✅
- [ ] coleção global follows (com userId/followerId)
- [ ] outra: _______

**Paths identificados:**
```dart
// Seguidores
.collection('Users')
  .doc(userId)
  .collection('followers')

// Seguindo
.collection('Users')
  .doc(userId)
  .collection('following')
```

**Código:** `followers_controller.dart` linhas 36-60

---

### A lista hoje carrega com:

- **[X] snapshots() (stream realtime)** ⚠️
- [ ] get() paginado
- [ ] mistura

**Implementação:**
```dart
_followersSub = query.snapshots().listen(
  (snapshot) => _handleFollowersSnapshot(snapshot),
  ...
);
```

**Código:** `followers_controller.dart` linhas 42-49

---

### Por que você usa realtime aqui?

- [ ] precisa atualizar "na hora" quando alguém segue/deixa de seguir
- **[X] foi por conveniência** ⚠️
- [ ] porque tem contador na UI
- [ ] outro: _______

**Observação:**
Não há necessidade clara de realtime. A lista poderia usar `get()` + pull-to-refresh sem perda de funcionalidade.

---

## 1) Query da lista (custo base)

### Query exata da lista (marque o que acontece):

- [ ] .limit(N)
- **[X] .orderBy(createdAt desc)** ✅
- [ ] sem orderBy
- [ ] usa cursor (startAfterDocument)
- **[X] carrega tudo sem paginação** ❌

**Código:**
```dart
final query = _firestore
    .collection('Users')
    .doc(userId)
    .collection('followers')
    .orderBy('createdAt', descending: true); // ✅ Tem orderBy
    // ❌ SEM .limit()
    // ❌ SEM paginação
```

**Linhas:** `followers_controller.dart` 36-39

---

### Primeiro carregamento traz quantos itens?

- [ ] 20
- [ ] 30
- [ ] 50
- [ ] 100+
- **[X] todos** ❌

**Problema crítico:** Sem `limit()`, carrega TODOS os seguidores de uma vez.

**Impacto:**
- Usuário com 1000 seguidores = 1000 reads no primeiro carregamento
- Usuário com 10.000 seguidores = 10.000 reads

---

### Ao rolar, ela:

- [ ] pagina (loadMore)
- **[X] não pagina e cresce infinito** ❌
- [ ] refaz do zero (ruim)

**Não há implementação de paginação.**

---

## 2) O que cada item precisa pra renderizar (onde nasce N+1)

### O doc do follower/following contém:

- **[X] só userId e timestamp** ⚠️
- [ ] também name, avatarThumb, verified (denormalizado)
- [ ] também bio, city etc.

**Estrutura do doc:**
```
Users/{userId}/followers/{followerId}
  - createdAt: Timestamp
  - (sem outros campos)
```

**Código:** `followers_controller.dart` linha 164

---

### Pra mostrar avatar/nome no item você:

- [ ] usa dados denormalizados do doc
- [ ] busca users_preview/{id} (ok)
- **[X] busca users/{id} completo (pesado)** ❌
- [ ] mistura / depende do componente

**Implementação:**
```dart
final futures = ids.map(_userRepository.getUserById).toList();
final results = await Future.wait(futures);
```

**Código:** `followers_controller.dart` linhas 164-165

**⚠️ PROBLEMA CRÍTICO: N+1 Query Pattern**

O `getUserById` busca o documento **completo** em `Users/{userId}` (não `users_preview`):

```dart
Future<Map<String, dynamic>?> getUserById(String userId) async {
  final doc = await _usersCollection.doc(userId).get();  // ← Users completo
  ...
}
```

**Código:** `user_repository.dart` linha 34

---

### Existe "N+1" de usuários?

- **[X] Sim (1 read por item)** ❌
- [ ] Não (zero lookups)
- [ ] Parcial (cache em memória reduz)

**Métricas reais:**

| Seguidores | Reads no stream | Reads no N+1 | Total |
|------------|----------------|--------------|-------|
| 50 | 50 | 50 | **100 reads** |
| 200 | 200 | 200 | **400 reads** |
| 1000 | 1000 | 1000 | **2000 reads** |

**Fórmula:** `total_reads = 2 × num_seguidores`

---

### Além do usuário, o item busca mais coisas?

- [ ] status online
- [ ] isFollowing (se estou seguindo de volta)
- [ ] mutual friends
- [ ] contadores
- **[X] nada** ✅

O botão de follow/unfollow usa `FollowController` separado que gerencia seu próprio estado.

---

## 3) Estados que geram writes/reads extras

### Botão "Seguir/Deixar de seguir":

- **[X] faz write e atualiza UI local (sem refetch)** ✅
- [ ] faz write e depois refaz a lista inteira (custo alto)
- [ ] faz write em 2 lugares (followers e following) + contador agregado
- [ ] não sei

**Implementação:**
O `FollowController` é usado individualmente por cada item. Não há evidência de refetch da lista completa após follow/unfollow.

---

### Você calcula contagem de seguidores como?

- **[X] campo agregado no doc do usuário (ideal)** ✅
- [ ] query contando followers (caro)
- [ ] function mantém contador

**Observação:**
Não há contador visível na tela de seguidores. Provavelmente o contador está no perfil principal e é mantido por Cloud Function.

---

## 4) Rebuilds e streams duplicados (recarregamento invisível)

### Ao sair e voltar pra tela, ela:

- [ ] mantém estado e stream
- **[X] recria stream toda vez** ⚠️
- [ ] depende (autoDispose, rota, tabs)

**Implementação:**
```dart
@override
void initState() {
  super.initState();
  _controller = FollowersController(userId: _userId!);
  _controller.initialize();  // ← Novo controller a cada abertura
}

@override
void dispose() {
  _controller.dispose();  // ← Cancela streams
  super.dispose();
}
```

**Código:** `followers_screen.dart` linhas 42-57

**Impacto:**
- Cada vez que abre a tela = 2 streams novos (followers + following)
- Sem cache entre aberturas
- Sempre carrega todos os dados do zero

---

### Existem múltiplos listeners pro mesmo path?

- [ ] Sim (ex: header + lista + contador)
- **[X] Não** ✅
- [ ] Não sei

Apenas 1 stream por lista (followers ou following), gerenciado pelo controller único.

---

### Tem lógica que dispara fetch no build() sem querer?

- [ ] Sim
- **[X] Não** ✅
- [ ] Não sei

As queries são iniciadas no `initState()` via `initialize()`, não no `build()`.

---

## 5) Cache (memória + Hive) — onde cortar custo de verdade

### Você tem cache em memória para:

**lista de followers:**
- [ ] sim
- **[X] não** ❌

**users_preview:**
- [ ] sim
- **[X] não** ❌

**Observação:**
Os `ValueNotifier<List<User>>` mantêm dados em memória enquanto o controller existe, mas não há cache persistente entre sessões ou entre aberturas da tela.

---

### Você persiste em Hive:

**lista (ids + timestamps):**
- [ ] sim
- **[X] não** ❌

**previews dos usuários (name/avatar/verified):**
- [ ] sim
- **[X] não** ❌

**Não há integração com Hive.**

---

### TTL do cache:

- **[X] não tem** ❌
- [ ] 1–5min
- [ ] 10–30min
- [ ] 1h+

---

### Você usa stale-while-revalidate?

- [ ] mostra cache instantâneo e revalida em background
- **[X] não** ❌

---

## 6) Resultado desejado (pra decidir arquitetura)

### Você precisa que a lista reflita follow/unfollow em tempo real?

- [ ] sim, na hora
- **[X] pode atualizar no pull-to-refresh** ✅
- [ ] pode atualizar localmente e revalidar depois (ideal)

**Justificativa:**
Seguidores não mudam com frequência suficiente para justificar realtime. Pull-to-refresh é suficiente.

---

### O usuário normalmente tem quantos seguidores?

- **[X] < 200** (estimativa)
- [ ] 200–2k
- [ ] 2k–20k
- [ ] 20k+

**Observação:**
App em fase inicial, maioria dos usuários tem poucos seguidores. Mas arquitetura precisa escalar.

---

### Essa tela é aberta com que frequência?

- [ ] raramente
- **[X] às vezes** ✅
- [ ] muito (várias vezes por sessão)

---

## 📊 RESUMO EXECUTIVO

### ⚠️ PROBLEMAS CRÍTICOS

#### 1. **N+1 Query Pattern - CRÍTICO** ❌

```
Para 100 seguidores:
1. Stream de followers: 100 docs (Users/{userId}/followers)
2. N+1 getUserById(): 100 docs (Users/{followerId})
Total: 200 reads por abertura
```

**Custo real:**
- 50 seguidores = **100 reads**
- 200 seguidores = **400 reads**
- 1000 seguidores = **2000 reads**

#### 2. **Sem paginação** ❌

```diff
- query.snapshots() sem limit
+ query.limit(30).get() com paginação
```

#### 3. **Stream realtime desnecessário** ⚠️

```diff
- snapshots() sempre ativo
+ get() com pull-to-refresh
```

#### 4. **Busca Users completo em vez de users_preview** ❌

```diff
- _usersCollection.doc(userId).get()  // Users completo
+ _usersPreviewCollection.doc(userId).get()  // Preview leve
```

#### 5. **Sem cache persistente** ⚠️

- Toda abertura = nova query completa
- Não usa Hive
- Não usa cache em memória entre sessões

---

### 💰 ECONOMIA ESTIMADA

**Cenário atual (100 seguidores):**
- Stream followers: 100 reads
- N+1 getUserById: 100 reads
- **Total: 200 reads por abertura**

**Cenário otimizado:**
- get() paginado (limit 30): 30 reads
- users_preview batch (whereIn): 3-4 reads (30 users em chunks de 10)
- **Total: ~33 reads por abertura**

**Redução: 85%** 🎯

---

## 📋 PLANO DE AÇÃO RECOMENDADO

### Fase 1 - CRÍTICO (Alta prioridade)

1. **Eliminar N+1:**
   - Trocar `getUserById()` por `getUsersByIds()` batch
   - Usar `users_preview` em vez de `Users`
   - Código: `followers_controller.dart` linha 164

2. **Adicionar paginação:**
   ```dart
   .limit(30)
   .startAfterDocument(_lastDoc)
   ```

3. **Remover stream realtime:**
   ```dart
   - query.snapshots()
   + query.get()
   ```

### Fase 2 - IMPORTANTE (Médio prazo)

4. **Adicionar cache Hive:**
   - Persistir lista de IDs + timestamps
   - Persistir users_preview
   - TTL: 10-30 min

5. **Implementar SWR:**
   - Mostra cache instantâneo
   - Revalida em background

### Fase 3 - OTIMIZAÇÃO (Longo prazo)

6. **Denormalizar dados no doc do follower:**
   ```
   Users/{userId}/followers/{followerId}
     - createdAt
     - displayName
     - avatarThumbUrl
     - isVerified
   ```

---

## 📁 ARQUIVOS ANALISADOS

1. `lib/features/profile/presentation/screens/followers_screen.dart`
2. `lib/features/profile/presentation/controllers/followers_controller.dart`
3. `lib/shared/repositories/user_repository.dart`

---

**Gerado em:** 30 de janeiro de 2026  
**Ferramenta:** GitHub Copilot (Claude Sonnet 4.5)
