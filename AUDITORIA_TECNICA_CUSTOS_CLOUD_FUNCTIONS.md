# Auditoria Técnica de Custos — Cloud Functions (Firebase)

> **Data:** 15/02/2026  
> **Objetivo:** Identificar quais functions geram mais custo real (execuções + tempo + fan-out), por que disparam tanto, e aplicar cortes rápidos.  
> **Top 5 analisadas:** getPeople, onUserStatusChange, onUserLocationUpdated, onUserWriteUpdatePreview, onActivityCreatedNotification

---

## ⚠️ DESCOBERTA CRÍTICA: o "efeito cascata Users"

Antes de analisar cada function individualmente, precisa ficar claro o achado mais importante desta auditoria:

### Existem 7 Cloud Functions disparando no mesmo trigger: `Users/{userId}`

Toda vez que **qualquer campo** do documento `Users/{userId}` é escrito (`.set()`, `.update()`, `.merge()`), **7 Cloud Functions disparam simultaneamente**:

| # | Function | Tipo | O que faz | Custo por disparo |
|---|----------|------|-----------|-------------------|
| 1 | `onUserWriteUpdatePreview` | onWrite | Sincroniza → `users_preview` | 1 read + 1 write |
| 2 | `onUserLocationUpdated` | onWrite | Atualiza `gridId`, `geohash`, `interestBuckets` → `users_preview` | 1 read + 0-1 write |
| 3 | `onUserStatusChange` | onWrite | Blacklist devices se status=inactive | 1 read + 0-N writes |
| 4 | `onUserAvatarUpdated` | onUpdate | Sincroniza avatar → `users_preview` | 1 read + 0-1 write |
| 5 | `onUserProfileUpdateSyncEvents` | onUpdate | Propaga gender/age/interests → N `events_card_preview` | 1 read + 0-N writes |
| 6 | `onUserLocationUpdateCopyToPrivate` | onUpdate | Copia lat/lng → `Users/{uid}/private/location` | 1 read + 0-1 write |
| 7 | `onUserCreatedReferral` | onCreate | Registra referral (só na criação) | Só onCreate |

**O client escreve em `Users/{uid}` a partir de pelo menos 10 code paths diferentes:**

| Code path | Frequência | Campos escritos |
|-----------|------------|-----------------|
| Background location tracking (cada 2km) | **Automática** | `displayLatitude`, `displayLongitude`, `geohash`, `country`, `locality`, `state` |
| Salvar localização manualmente | Ação do usuário | Mesmos acima |
| Alterar raio de busca (slider) | Ação do usuário (500ms debounce) | `advancedSettings.radiusKm` |
| Alterar filtros avançados | Ação do usuário | `advancedSettings.*` |
| Alterar raio de notificações | Ação do usuário | `advancedSettings.eventNotificationRadiusKm` |
| Upload de foto de perfil | Ação do usuário | `photoUrl` |
| Upload de foto na galeria | Ação do usuário | `user_gallery` |
| Atualizar perfil (nome, bio, etc.) | Ação do usuário | Campos variados |
| Init location (primeiro login) | 1x por sessão | `latitude`, `longitude`, `radiusKm` |
| `updateUserRating` (Cloud Function!) | Review criada/deletada | `overallRating` **← cascata indireta** |

### Cálculo de custo do efeito cascata

**Cenário: usuário anda 10km durante uma sessão (5 location updates de 2km)**

```
5 writes no doc Users/{uid}
× 6 Cloud Functions disparadas por write (excluindo onCreate)
= 30 invocações de Cloud Functions

Cada invocação = 1 cold/warm start + CPU + memória
Dessas 30 invocações:
  - 25 fazem early-return (nada mudou para aquela function específica)
  - 5 executam lógica real (onUserLocationUpdated + onUserWriteUpdatePreview)
  - Mas as 25 que fazem early-return AINDA PAGAM invocação + ~100-200ms
```

**Cenário: usuário atualiza perfil (foto + nome + interesses)**

```
3 writes no doc Users/{uid} (foto, nome, interesses — podem ser 1-3 operações)
× 6 Cloud Functions disparadas
= 18 invocações

Dessas 18:
  - onUserWriteUpdatePreview: 3 execuções reais (sem early-return!)
  - onUserAvatarUpdated: 1 execução real (só foto mudou)
  - onUserProfileUpdateSyncEvents: 1 execução real (interests mudou) + N writes em events_card_preview
  - Resto: early-returns que ainda custam invocação
```

---

## Análise Individual — Checklist de 6 Perguntas

---

### 1) `getPeople`

#### A) O que dispara?
**HTTPS Callable** — chamada explícita do client via `FirebaseFunctions.instance.httpsCallable('getPeople')`

#### B) Qual collection/documento é o gatilho?
Não é trigger Firestore. É chamada HTTP do app Flutter. Dentro da function, lê:
- `Users/{userId}` — 1 read para VIP check
- `users_preview` — query por bounding box (200-1500 docs lidos)
- Fallback para `Users` se `users_preview` vazio

#### C) Frequência de disparo por usuário

| Situação | Frequência |
|----------|------------|
| Abrir aba mapa (primeira vez) | 1x |
| Cada pan/zoom no mapa (camera idle) | 1x por idle event |
| Warmup no app start | 1x |
| Abrir tela FindPeople | 1x |
| Mudar raio/filtro na FindPeople | 1x |

**Throttling existente no client (multi-camada):**
- GoogleMapView: debounce de 600ms no `onCameraIdle`
- PeopleMapDiscoveryService: debounce adicional de 300ms
- Throttle de 2000ms entre queries idle
- Cache LRU em memória: 24 tiles, TTL 180s
- Cache Hive persistente: TTL 24h, soft refresh 6h
- In-flight dedup: junta requests com mesma cacheKey
- Coverage check: pula se bounds já cobertos

**Estimativa:** ~5-15 chamadas por sessão ativa (com cache). Sem cache seriam ~30-50+.

#### D) Existe fan-out?
**NÃO.** Função é read-only (exceto cache em memória da instância).

**Reads por execução:**
- 1 read em `Users/{userId}` (VIP check) — **documento completo (~5-10KB)**
- 1 query em `users_preview` com `.limit(200-1500)` — até 1500 reads
- Máximo: **~1.502 reads por invocação**
- Writes: **0**

#### E) Existe loop/cascata?
**NÃO.** Não escreve em nenhuma collection.

#### F) Ela escreve mesmo quando nada mudou?
**N/A** — é read-only.

#### 📊 Custo real estimado

```
Por execução (cache miss):
  Reads: 1 (Users) + 200-1500 (users_preview) = até 1.501 reads
  Writes: 0
  CPU: ~200-800ms (Haversine filtering + sorting)
  Memória: 256MB default

Por execução (cache hit):
  Reads: 0
  CPU: ~5ms
```

#### 🔧 Recomendações para getPeople

| # | Ação | Impacto | Esforço |
|---|------|---------|---------|
| 1 | **VIP check: usar `users_preview` em vez de `Users`** | -1 read do doc completo (~5-10KB) por call | Baixo |
| 2 | **Reduzir `baseFetchLimit` free de 200→100** | -50% reads na maioria das queries | Baixo |
| 3 | **Aumentar cache TTL server-side de 90s→300s** | -60% de cache misses | Trivial |
| 4 | **Eliminar fallback para `Users` collection** | Remove query de 400+ docs no fallback | Baixo |
| 5 | **Migrar para Cloud Functions v2 (concurrency)** | Mesmo hardware serve 80 requests simultâneos vs 1 | Médio |

---

### 2) `onUserStatusChange`

#### A) O que dispara?
**Firestore onWrite** em `Users/{userId}` — dispara em TODA escrita no documento do usuário.

#### B) Qual collection/documento é o gatilho?
`Users/{userId}` — qualquer campo.

#### C) Frequência de disparo por usuário
**Mesma frequência que toda escrita em `Users/{uid}`**: ~5-15× por sessão (location tracking, profile updates, settings changes).

#### D) Existe fan-out?
**Condicional.** Na maioria dos disparos: **0 writes** (early-return porque status não mudou).

Quando status muda para "inactive" (raro — ação admin):
- 1 read da subcollection `Users/{uid}/clients` (N docs)
- N writes em `BlacklistDevices` (1 por device)
- Típico: 1-3 writes

#### E) Existe loop/cascata?
**NÃO.** Escreve em `BlacklistDevices`, collection completamente separada.

#### F) Ela escreve mesmo quando nada mudou?
**NÃO.** Tem guard:
```typescript
if (beforeStatus === afterStatus) {
  console.log("ℹ️ Status unchanged, skipping");
  return;
}
```

**MAS:** Embora faça early-return, a **invocação** é cobrada. A function é instanciada, o runtime faz bootstrap, monta o before/after diff — isso custa ~100-200ms de compute + memory.

#### 📊 Custo real estimado

```
Por invocação (99% dos casos — early return):
  Reads: 0 (dados vêm no change snapshot)
  Writes: 0
  CPU: ~100-200ms (bootstrap + comparação)
  
Por invocação (status→inactive, ~1% dos disparos):
  Reads: 1 query (clients subcollection)
  Writes: 1-3 (BlacklistDevices)
  CPU: ~300-500ms
```

**O custo real é o volume de invocações desperdiçadas.** A function dispara em toda escrita no Users, mas só faz trabalho útil em ~0.01% dos casos.

#### 🔧 Recomendações para onUserStatusChange

| # | Ação | Impacto | Esforço |
|---|------|---------|---------|
| 1 | **Trocar trigger para Firestore Events (eventarc) com filter no campo `status`** | Elimina 99% das invocações desperdiçadas | Médio (requer v2) |
| 2 | **Alternativa: mover lógica de blacklist para callable chamada pelo admin** | Função só roda quando admin realmente desativa conta | Baixo |

---

### 3) `onUserLocationUpdated`

#### A) O que dispara?
**Firestore onWrite** em `Users/{userId}` — toda escrita no documento do usuário.

#### B) Qual collection/documento é o gatilho?
`Users/{userId}` — qualquer campo.

#### C) Frequência de disparo por usuário
Mesma de toda escrita em `Users/{uid}`: ~5-15× por sessão.

**Frequência de execução efetiva (com early-return):**
O guard verifica se `latitude/longitude/interests` mudaram:
```typescript
if (!interestsChanged && !shouldUpdateGridId && !shouldUpdateGeohash) {
  return;
}
```
Execução real: ~1-5× por sessão (apenas quando localização muda de fato).

#### D) Existe fan-out?
**Mínimo.** 1 write em `users_preview/{userId}` quando executa.

```
Reads: 0 (dados vêm no change snapshot)
Writes: 1 (users_preview set/merge)
```

#### E) Existe loop/cascata?
**NÃO diretamente.** Escreve em `users_preview` (collection diferente). Mas atenção: `users_preview` NÃO tem triggers próprios, então sem cascata.

#### F) Ela escreve mesmo quando nada mudou?
**NÃO.** Guard eficiente — verifica mudança real em lat/lng/interests antes de escrever.

#### 📊 Custo real estimado

```
Por invocação (early return, ~70% dos disparos):
  Reads: 0
  Writes: 0
  CPU: ~100-200ms (bootstrap + comparação)

Por invocação (localização mudou, ~30%):
  Reads: 0 (dados vêm no snapshot)
  Writes: 1 (users_preview)
  CPU: ~200-400ms
```

#### 🔧 Recomendações para onUserLocationUpdated

| # | Ação | Impacto | Esforço |
|---|------|---------|---------|
| 1 | **Consolidar com `onUserWriteUpdatePreview` numa única function** | -1 invocação por write no Users | Médio |
| 2 | **Migrar para v2 com event filter em `displayLatitude`** | Elimina invocações quando campo não mudou | Médio |

---

### 4) `onUserWriteUpdatePreview`

#### A) O que dispara?
**Firestore onWrite** em `Users/{userId}` — toda escrita no documento do usuário.

#### B) Qual collection/documento é o gatilho?
`Users/{userId}` — qualquer campo.

#### C) Frequência de disparo por usuário
Mesma de toda escrita em `Users/{uid}`: ~5-15× por sessão.

#### D) Existe fan-out?
**1 write sempre** — não tem early-return baseado em diff de campos!

```
Reads: 0 (dados vêm no change snapshot)
Writes: 1 (users_preview set/merge) — SEMPRE
```

#### E) Existe loop/cascata?
**SIM — casual indireta:**

```
1. Review criada → Cloud Function `updateUserRating` 
   → escreve `overallRating` em Users/{uid} via .set({merge: true})
2. → Dispara onUserWriteUpdatePreview
   → Escreve em users_preview (duplicando o rating que já foi escrito)
3. → Dispara onUserLocationUpdated (early-return, mas paga invocação)
4. → Dispara onUserStatusChange (early-return, mas paga invocação)
5. → Dispara onUserAvatarUpdated (early-return, mas paga invocação)
6. → Dispara onUserProfileUpdateSyncEvents (early-return, mas paga invocação)
7. → Dispara onUserLocationUpdateCopyToPrivate (early-return, mas paga invocação)

Total: 1 review → 6 Cloud Function invocações extras (só 1 útil)
```

#### F) Ela escreve mesmo quando nada mudou?
**🔴 SIM — SEMPRE ESCREVE**, sem nenhum check de diff:

```typescript
// Código atual — NENHUM guard de diff
const previewData = {
  userId,
  fullName,
  displayName: fullName,
  username,
  photoUrl,
  avatarThumbUrl,
  isVerified,
  isVip,
  locality: userData.locality || null,
  state: userData.state || null,
  country: userData.country || null,
  flag: userData.flag || null,
  overallRating: userData.overallRating || 0,
  updatedAt: admin.firestore.FieldValue.serverTimestamp(), // ← força sempre-diferente
};

await db.collection("users_preview").doc(userId).set(previewData, { merge: true });
```

**Problema duplo:**
1. Não compara before vs after — escreve mesmo se nenhum campo preview mudou
2. `updatedAt: serverTimestamp()` garante que o documento é SEMPRE diferente, causando reads adicionais em qualquer listener de `users_preview`

#### 📊 Custo real estimado

```
Por invocação (TODAS — sem early-return):
  Reads: 0 (dados vêm no snapshot)
  Writes: 1 (users_preview) — SEMPRE
  CPU: ~200-400ms
  
Custo oculto: cada write em users_preview
  → atualiza qualquer stream/listener ativo em users_preview/{uid}
  → gera snapshot event para todos os clients conectados
  → multiplica egress de Firestore
```

**Esta é a function mais desperdiçadora das 5.** A cada slider de raio, a cada mudança de filtro, a cada location update — ela escreve desnecessariamente em `users_preview`.

#### 🔧 Recomendações para onUserWriteUpdatePreview

| # | Ação | Impacto | Esforço |
|---|------|---------|---------|
| 1 | **🔴 URGENTE: Adicionar diff check antes do write** | -70-80% dos writes em users_preview | **Trivial** |
| 2 | **Remover `updatedAt: serverTimestamp()`** do preview | Para de invalidar caches e listeners desnecessariamente | **Trivial** |
| 3 | **Consolidar com `onUserLocationUpdated` + `onUserAvatarUpdated`** | -2 invocações por write | Médio |

**Fix imediato sugerido:**

```typescript
export const onUserWriteUpdatePreview = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId;

    if (!change.after.exists) {
      await db.collection("users_preview").doc(userId).delete();
      return;
    }

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.data();
    if (!after) return;

    // ✅ CAMPOS QUE IMPORTAM PARA O PREVIEW
    const previewFields = [
      'fullName', 'displayName', 'username',
      'photoUrl', 'profilePhoto', 'photoThumbUrl', 'avatarThumbUrl',
      'user_is_verified', 'isVerified', 'verified',
      'user_is_vip', 'isVip', 'vip',
      'locality', 'state', 'country', 'flag',
      'overallRating',
    ];

    // ✅ EARLY-RETURN: só escreve se algum campo preview mudou
    if (before) {
      const hasChange = previewFields.some((field) => {
        return JSON.stringify(before[field] ?? null) !== JSON.stringify(after[field] ?? null);
      });
      if (!hasChange) {
        return; // Nada relevante mudou — economiza 1 write
      }
    }

    const previewData = {
      userId,
      fullName: after.fullName || after.displayName || null,
      // ... resto dos campos ...
      // ❌ REMOVER: updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users_preview").doc(userId).set(previewData, { merge: true });
  });
```

---

### 5) `onActivityCreatedNotification`

#### A) O que dispara?
**Firestore onCreate** em `events/{eventId}` — quando um evento novo é criado.

#### B) Qual collection/documento é o gatilho?
`events/{eventId}` — apenas criação (não update).

#### C) Frequência de disparo por usuário
**BAIXA** — apenas quando o usuário cria uma atividade. Típico: 0-5 vezes por dia por usuário.

#### D) Existe fan-out?
**🔴 SIM — MASSIVO:**

```
Por execução:
  Reads:
    1 read Users/{creatorId} (dados do criador — doc completo)
    2 queries paralelas em Users (bounding box latitude com limit 1000)
    = até 1.002 reads

  Writes:
    1 Notifications doc por usuário no raio
    Até 500 writes por evento criado
    = até 500 writes por invocação
```

**Fluxo completo de uma criação de evento:**

```
1. Client cria doc em events/{id}
   → Dispara onEventCreated (index.ts): 4 writes (application + chat + message + conversation)
   → Dispara onActivityCreatedNotification: 1 read + 2 geo-queries + até 500 writes
   → Dispara onEventWriteUpdateCardPreview: 1 read + 1 write (preview)
   → Dispara updateUserRanking: 1 read + 1 write (ranking)
   → Dispara updateLocationRanking: 1 read + N reads + 1 write

2. Os 500 writes em Notifications
   → Dispara onActivityNotificationCreated (activityPushNotifications.ts): 
      para cada notificação → 1 read (DeviceTokens) + 1 push FCM
   = até 500 invocações extras + 500 reads + 500 pushes

3. Total para 1 evento criado:
   Reads: ~1.500-2.500
   Writes: ~510-520
   Cloud Function invocações: ~505-510
   Push notifications: ~500
```

#### E) Existe loop/cascata?
**SIM — cascata (não loop):**

```
events.onCreate 
  → onActivityCreatedNotification 
    → escreve em Notifications
      → dispara onActivityNotificationCreated (activityPushNotifications.ts)
        → lê DeviceTokens + envia push FCM
```

São 2 levels de cascade: evento → notificações → push. Cada level multiplica o custo.

#### F) Ela escreve mesmo quando nada mudou?
**N/A** — onCreate dispara apenas 1x por documento. Não há risco de escrita redundante.

#### 📊 Custo real estimado

```
Por evento criado (cidade típica, ~100 users no raio):
  Reads: ~202 (1 creator + 2×100 geo-query)
  Writes: ~100 (Notifications)
  CPU: ~1-3s (geo-query + batch commit)
  Cascata: +100 invocações de activityPushNotifications

Por evento criado (cidade grande, ~500 users no raio):
  Reads: ~1.002
  Writes: ~500
  CPU: ~3-5s
  Cascata: +500 invocações
```

#### 🔧 Recomendações para onActivityCreatedNotification

| # | Ação | Impacto | Esforço |
|---|------|---------|---------|
| 1 | **Reduzir limit de 500→100 usuários notificados** | -80% writes e cascata push | **Trivial** |
| 2 | **Usar `users_preview` em vez de `Users` no geo-query** | -90% do tamanho do dado lido (500B vs 5-10KB) | Baixo |
| 3 | **Eliminar query dupla (displayLatitude + latitude legacy)** | -50% das reads no geo-query | Baixo |
| 4 | **Usar geohash prefix query em vez de bounding box range** | Menos docs escaneados, mais eficiente | Médio |
| 5 | **Consolidar notificação batch (1 doc com array de receivers) vs 1 doc por receiver** | -99% dos writes (500→1) | Alto (requer refactor de leitura) |

---

## Resumo Consolidado — Custo por Function

### Tabela de custo em uma sessão típica (1 usuário, 30 min)

| Function | Invocações/sessão | Early returns | Reads reais | Writes reais | Fan-out |
|----------|-------------------|---------------|-------------|--------------|---------|
| **getPeople** | 5-15 | 60% (cache hit) | 200-1500/call | 0 | Nenhum |
| **onUserStatusChange** | 5-15 | **99%** | 0 | 0 | Nenhum |
| **onUserLocationUpdated** | 5-15 | **70%** | 0 | 0-5 | 1 write/exec |
| **onUserWriteUpdatePreview** | 5-15 | **0% (sem guard!)** | 0 | **5-15** | 1 write SEMPRE |
| **onActivityCreatedNotification** | 0-2 | 0% | 200-1000 | 100-500 | **500 cascade** |

### Total de invocações geradas por 1 write em `Users/{uid}`

```
1 write no documento Users/{uid}
  → onUserWriteUpdatePreview       (1 invocação — SEMPRE escreve)
  → onUserLocationUpdated          (1 invocação — early return 70%)
  → onUserStatusChange             (1 invocação — early return 99%)
  → onUserAvatarUpdated            (1 invocação — early return 95%)
  → onUserProfileUpdateSyncEvents  (1 invocação — early return 90%)
  → onUserLocationUpdateCopyToPrivate (1 invocação — early return 80%)
  ─────────────────────────────────
  = 6 invocações por write
  
  Com 10 writes/sessão × 6 triggers = 60 invocações/sessão/usuário
  
  Com 1.000 users ativos/dia × 60 = 60.000 invocações/dia
  Dessas 60.000: ~50.000 são early-returns inúteis (83%)
```

---

## Plano de Cortes — Priorizado por Impacto/Esforço

### 🔴 Corte 1 — Imediato (1 hora): Adicionar diff guard em `onUserWriteUpdatePreview`

**O que:** Adicionar comparação before/after nos campos relevantes antes de escrever.

**Economia:** -70-80% dos writes em `users_preview` + elimina invalidação de caches/listeners downstream.

**Arquivo:** `functions/src/users/usersPreviewSync.ts`

**Mudança:**
```typescript
// ANTES do set(), adicionar:
if (before) {
  const previewFields = ['fullName','displayName','username','photoUrl','profilePhoto',
    'avatarThumbUrl','photoThumbUrl','user_is_verified','isVerified','verified',
    'user_is_vip','isVip','vip','locality','state','country','flag','overallRating'];
  const changed = previewFields.some(f => 
    JSON.stringify(before[f] ?? null) !== JSON.stringify(after[f] ?? null)
  );
  if (!changed) return;
}
// E REMOVER updatedAt: admin.firestore.FieldValue.serverTimestamp()
```

---

### 🔴 Corte 2 — Imediato (30 min): Consolidar onUserAvatarUpdated INTO onUserWriteUpdatePreview

**O que:** `onUserAvatarUpdated` faz a mesma coisa que `onUserWriteUpdatePreview` (sincronizar avatar para `users_preview`). Redundante.

**Economia:** -1 invocação por write = ~10.000 invocações/dia (1.000 users).

**Mudança:** Remover export de `onUserAvatarUpdated` do `index.ts`.

---

### 🔴 Corte 3 — Imediato (30 min): Remover `onUserLocationUpdateCopyToPrivate`

**O que:** Migração legacy que copia lat/lng para subcollection `private/location`. Se a migração já foi feita, não precisa mais rodar.

**Economia:** -1 invocação por write = ~10.000 invocações/dia.

**Mudança:** Remover export de `onUserLocationUpdateCopyToPrivate` do `index.ts`. Antes, confirmar que o client já escreve direto em `private/location`.

---

### 🔴 Corte 4 — 1 dia: Consolidar triggers de Users em 1 única function

**O que:** Juntar `onUserWriteUpdatePreview` + `onUserLocationUpdated` + `onUserAvatarUpdated` em UMA ÚNICA function que faz os 3 checks e escreve 1 vez.

**Economia:** De 6 invocações por write para **1 invocação** = -83% das invocações.

**Mudança:**
```typescript
export const onUserDocChanged = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    
    if (!change.after.exists) {
      await db.collection("users_preview").doc(userId).delete();
      return;
    }

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.data()!;
    
    // 1. Check preview fields (era onUserWriteUpdatePreview)
    const previewChanged = checkPreviewFieldsChanged(before, after);
    
    // 2. Check location/interests (era onUserLocationUpdated)  
    const locationChanged = checkLocationChanged(before, after);
    
    // 3. Check status (era onUserStatusChange)
    const statusChanged = before?.status !== after.status;
    
    // 4. Check profile filter fields (era onUserProfileUpdateSyncEvents)
    const filterFieldsChanged = checkFilterFieldsChanged(before, after);
    
    // Só escreve se algo mudou
    const updatePayload: Record<string, unknown> = {};
    
    if (previewChanged) {
      Object.assign(updatePayload, buildPreviewData(after));
    }
    if (locationChanged) {
      Object.assign(updatePayload, buildLocationData(after));
    }
    
    if (Object.keys(updatePayload).length > 0) {
      await db.collection("users_preview").doc(userId)
        .set(updatePayload, { merge: true });
    }
    
    if (statusChanged && after.status === "inactive") {
      await blacklistUserDevices(userId);
    }
    
    if (filterFieldsChanged) {
      await syncCreatorEventsPreview(userId, after);
    }
  });
```

---

### 🟡 Corte 5 — 2 horas: Reduzir fan-out de onActivityCreatedNotification

**O que:** Limitar de 500 para 100 notificações por evento. Usar `users_preview` em vez de `Users` para o geo-query. Eliminar query dupla (displayLatitude + latitude legacy).

**Economia:** -80% writes por evento criado + -80% cascade de push functions.

**Mudanças em** `functions/src/activityNotifications.ts` e `functions/src/services/geoService.ts`:
- `limit: 500` → `limit: 100`
- Geo-query em `Users` → `users_preview`
- Remover queryDef com `fieldPath: "latitude"` (legacy)
- Remover queryDef com `fieldPath: "lastLocation.latitude"` (legacy)

---

### 🟡 Corte 6 — 2 horas: Otimizar getPeople

**O que:**
1. VIP check com `users_preview` em vez de `Users` completo
2. Aumentar cache TTL server-side de 90s → 300s
3. Reduzir `baseFetchLimit` free de 200 → 100
4. Remover fallback para collection `Users`

**Economia:** -50% reads por cache miss + -60% de cache misses.

**Mudanças em** `functions/src/get_people.ts`:
```typescript
// VIP check (trocar Users → users_preview)
const userDoc = await admin.firestore()
  .collection("users_preview")  // era "Users"
  .doc(userId)
  .get();

// Cache TTL
const PEOPLE_CACHE_TTL_MS = 300 * 1000; // era 90s

// Fetch limit
const baseFetchLimit = isVip ? 600 : 100; // free era 200

// Remover bloco de fallback usersFallback para Users collection
```

---

### 🟡 Corte 7 — 1 dia: Migrar para Cloud Functions v2

**O que:** Migrar as 5 functions mais invocadas para v2 (gen2).

**Vantagens v2:**
- **Concurrency**: 1 instância serve 80 requests (vs 1 em v1) → -95% de instances para `getPeople`
- **Event filters**: `eventFilters: { "status": "inactive" }` → `onUserStatusChange` só dispara quando status muda
- **Min instances 0**: zero custo idle
- **Billing por request**: não por instance-hour

**Ordem de migração:**
1. `getPeople` (maior volume + maior benefício de concurrency)
2. Consolidar triggers de Users numa única v2 function
3. `onActivityCreatedNotification`

---

## Métricas para Validar os Cortes

### Antes dos cortes — baseline (coletar agora)

```bash
# No GCP Console > Cloud Functions > Metrics:

1. Invocations por function (24h):
   - getPeople: ___
   - onUserWriteUpdatePreview: ___
   - onUserLocationUpdated: ___
   - onUserStatusChange: ___
   - onUserAvatarUpdated: ___
   - onUserProfileUpdateSyncEvents: ___
   - onUserLocationUpdateCopyToPrivate: ___
   - onActivityCreatedNotification: ___

2. Execution time (p50, p95) por function:
   - getPeople: ___ ms / ___ ms
   - onUserWriteUpdatePreview: ___ ms / ___ ms

3. Firestore reads/writes totais (24h):
   - Reads: ___
   - Writes: ___

4. Cloud Functions active instances (peak, avg):
   - Peak: ___
   - Avg: ___

5. Billing "App Engine" (últimos 7 dias):
   - $___
```

### Após cada corte — comparar

```
Corte 1 (diff guard): esperar -15% writes Firestore, -10% invocações
Corte 2 (remover avatar sync): esperar -15% invocações de onWrite
Corte 3 (remover location copy): esperar -15% invocações de onWrite
Corte 4 (consolidar em 1 func): esperar -70% invocações totais de onWrite
Corte 5 (limitar notificações): esperar -10% writes (depende de quantos eventos criados)
Corte 6 (otimizar getPeople): esperar -30% reads em users_preview
Corte 7 (v2 migration): esperar -50%+ em "App Engine" billing
```

---

## Resposta Final — Por que App Engine é Caro

| Causa raiz | % do custo estimado | Corte |
|------------|---------------------|-------|
| 6 triggers simultâneos em Users (83% são early-return inútil) | **35-40%** | Cortes 1-4 |
| `getPeople` sem concurrency (v1 = 1 request/instance) | **20-25%** | Cortes 6-7 |
| `onUserWriteUpdatePreview` escreve SEMPRE (sem diff check) | **10-15%** | Corte 1 |
| Cascade de notificações (500 writes + 500 push per event) | **10-15%** | Corte 5 |
| Migrations/debug functions deployadas em produção | **5-8%** | Remover do index.ts |
| Cron jobs com frequência excessiva | **5-8%** | Já documentado na auditoria anterior |
