# Auditoria Técnica de Custos – Cloud Functions (Top 5)

**Data:** 15/02/2026  
**Escopo:** `getPeople`, `onUserStatusChange`, `onUserWriteUpdatePreview` (equivale ao pedido `onUserProfileUpdatePreview`), `onUserLocationUpdated`, `onActivityNotificationCreated`.

---

## 1) Priorização (top 5 suspeitas)

Ordem de ataque sugerida (custo real = invocações × duração × fan-out):

1. **getPeople**
2. **onActivityNotificationCreated**
3. **onUserWriteUpdatePreview** (`onUserProfileUpdatePreview` no pedido)
4. **onUserLocationUpdated**
5. **onUserStatusChange**

> Observação: `onUserStatusChange` tende a ter fan-out alto por execução de negócio (blacklist por device), porém volume funcional costuma ser menor. Já `onUserWriteUpdatePreview` e `onUserLocationUpdated` têm volume alto por compartilharem o gatilho `Users/{userId}`.

---

## 2) Checklist A–F por function

## 2.1 `getPeople`

- **A) O que dispara?**
  - HTTP callable (`functions.https.onCall`).
- **B) Gatilho/collection**
  - Sem trigger Firestore; chamada direta do app.
  - Lê `users_preview/{userId}` (VIP) e consulta `users_preview` por bbox/filtros.
- **C) Frequência por usuário**
  - Alta: chamada em carregamento inicial e em refresh por bounds no fluxo de descobrir pessoas.
  - Há debounce/cache de 5s no controller, mas em pan/zoom e trocas de filtro ainda pode gerar múltiplas chamadas por minuto.
- **D) Fan-out (writes por execução)**
  - **Writes:** 0.
  - **Reads:** alto fan-out de leitura (scan limit 100→400 free e 600→1500 VIP, com possíveis consultas de fallback).
- **E) Loop/cascata**
  - Sem loop de trigger (não escreve no Firestore).
- **F) Escreve sem mudança?**
  - Não se aplica (não escreve).

**Risco de custo:** **Muito alto** por volume + amplificação de reads.

---

## 2.2 `onUserStatusChange`

- **A) O que dispara?**
  - Firestore `onWrite`.
- **B) Gatilho/collection**
  - Trigger em `Users/{userId}`.
  - Lê `Users/{userId}/clients`.
  - Escreve em `BlacklistDevices/{deviceIdHash}`.
- **C) Frequência por usuário**
  - A função dispara em **todo write de `Users/{userId}`**, mas só executa lógica pesada quando `status` muda para `inactive`.
- **D) Fan-out (writes por execução)**
  - 0..N writes (1 por device/client encontrado).
- **E) Loop/cascata**
  - Não escreve em `Users`, então não re-dispara o próprio trigger.
- **F) Escreve sem mudança?**
  - Não: faz short-circuit se `status` não mudou e se novo status != `inactive`.

**Risco de custo:** **Médio** (invocações em massa por `Users.onWrite`, fan-out pontual no caso de inativação).

---

## 2.3 `onUserWriteUpdatePreview` (pedido: `onUserProfileUpdatePreview`)

- **A) O que dispara?**
  - Firestore `onWrite`.
- **B) Gatilho/collection**
  - Trigger em `Users/{userId}`.
  - Escreve em `users_preview/{userId}`.
- **C) Frequência por usuário**
  - Alta: qualquer update em `Users` (perfil, preferências, localização etc.) dispara.
- **D) Fan-out (writes por execução)**
  - Até 1 write (`set merge`) por execução, ou 1 delete em remoção de usuário.
- **E) Loop/cascata**
  - Não há loop direto (escreve em `users_preview`, trigger é em `Users`).
- **F) Escreve sem mudança?**
  - **Tem proteção:** diff guard (compara campos relevantes before/after) e faz skip idempotente.

**Risco de custo:** **Alto** por volume de disparo em `Users.onWrite`.

---

## 2.4 `onUserLocationUpdated`

- **A) O que dispara?**
  - Firestore `onWrite`.
- **B) Gatilho/collection**
  - Trigger em `Users/{userId}`.
  - Escreve em `users_preview/{userId}` (`interestBuckets`, `gridId`, `geohash`, `updatedAt`).
- **C) Frequência por usuário**
  - Invocado a cada write em `Users`; writes de localização no app podem ocorrer por scheduler/background e por update manual.
- **D) Fan-out (writes por execução)**
  - Até 1 write (`set merge`) quando há mudança relevante.
- **E) Loop/cascata**
  - Não há loop direto (destino `users_preview`).
- **F) Escreve sem mudança?**
  - **Tem proteção:** retorna sem write se não mudou interesse, grid ou geohash.

**Risco de custo:** **Alto** por volume + concorrência com outros triggers no mesmo path.

---

## 2.5 `onActivityNotificationCreated`

- **A) O que dispara?**
  - Firestore `onCreate`.
- **B) Gatilho/collection**
  - Trigger em `Notifications/{notificationId}`.
  - Chama `sendPush` (lê `Users/{receiverId}`, consulta `DeviceTokens`, usa `push_receipts`).
  - Atualiza a própria notificação com `push_sent: true`.
- **C) Frequência por usuário**
  - 1 execução para cada documento novo em `Notifications`.
  - Pode ocorrer em burst (ex.: criação em lote de até ~100 notificações por evento em flows de activity notification).
- **D) Fan-out (writes por execução)**
  - Writes típicos:
    - 1 update em `Notifications` (`push_sent`).
    - 1 upsert em `push_receipts` (transação/merge).
    - 0..N deletes em `DeviceTokens` inválidos.
- **E) Loop/cascata**
  - Sem loop direto de trigger (`onCreate` não re-dispara por update).
  - Há **cascata arquitetural**: funções que criam muitos docs em `Notifications` multiplicam invocações desta função.
- **F) Escreve sem mudança?**
  - Evita duplicação com guard de `push_sent` e controle de idempotência em `push_receipts`.

**Risco de custo:** **Muito alto** quando upstream cria notificações em lote.

---

## 3) Diagnóstico rápido de causa-raiz

- `Users/{userId}` concentra múltiplos triggers: qualquer write no usuário dispara várias functions (efeito multiplicador).
- `getPeople` tem custo de leitura alto por execução (scan/fallback/requery).
- `onActivityNotificationCreated` sofre de cascata por bulk create em `Notifications`.
- Existe dedupe em partes importantes (preview diff guard, location guard, push idempotency), mas ainda há alto volume estrutural.

---

## 4) Cortes imediatos (throttle/dedupe/batch/mover para client/reduzir writes)

## 4.1 `getPeople` (P0)

1. **Throttle client hard**: mínimo 2–3s por usuário em pan/zoom + cancelar requests em voo.
2. **Debounce por bounds**: só chamar se bbox mudou acima de limiar (não a cada micro-pan).
3. **Cap de scan menor por plano**: reduzir tetos de `fetchLimit` quando zoom aberto.
4. **Sem fallback agressivo em sequência**: limitar para no máximo 1 fallback por chamada.

## 4.2 `onActivityNotificationCreated` (P0)

1. **Batch de push upstream**: reduzir criação massiva de docs individuais quando possível.
2. **Rate limit por evento/tipo**: janela de dedupe por `n_type + n_related_id + receiver`.
3. **Short-circuit precoce**: validar tipo/origem antes de qualquer operação cara.

## 4.3 `onUserWriteUpdatePreview` + `onUserLocationUpdated` (P1)

1. **Separar writes em `Users`**: evitar updates frequentes com campos cosméticos e timestamp desnecessário.
2. **Coalescer updates de localização**: agrupar e gravar menos vezes.
3. **Escrever apenas campos mudados** no client para reduzir triggers em cascata.

## 4.4 `onUserStatusChange` (P2)

1. **Evitar write em `Users` de status sem mudança real**.
2. **Limitar/normalizar quantidade de `clients` ativos por usuário** para controlar fan-out em blacklist.

---

## 5) Medição de custo real (sem achismo)

Métricas obrigatórias por função:

1. **invocations**
2. **duration média / p95**
3. **reads/writes por execução (fan-out)**

## 5.1 Invocations + Duration (Cloud Monitoring)

Usar métricas por função (janela 24h e 7d):
- `cloudfunctions.googleapis.com/function/execution_count`
- `cloudfunctions.googleapis.com/function/execution_times`

Extrair:
- média, p95 de duração
- ranking por custo aproximado: `invocations × avg_duration_ms`

## 5.2 Fan-out real (logs estruturados por execução)

Padronizar log JSON por função com:
- `functionName`
- `executionId`
- `durationMs`
- `readsCount`
- `writesCount`
- `candidatesScanned` (no `getPeople`)
- `queryPath/fallbackUsed` (no `getPeople`)

> `getPeople` já possui logs úteis (`scannedDocs`, `queryPath`, `durationMs`), faltando padronizar para export analítico.

## 5.3 Fonte única para relatório

Exportar logs para BigQuery e montar visão diária:
- `invocations`
- `avg_duration_ms`
- `p95_duration_ms`
- `avg_reads_per_exec`
- `avg_writes_per_exec`
- `estimated_firestore_ops_per_day`

Exemplo de saída final esperada por função:

| function | invocations_24h | avg_ms | p95_ms | avg_reads_exec | avg_writes_exec | ops_dia_estimado |
|---|---:|---:|---:|---:|---:|---:|
| getPeople | ... | ... | ... | ... | ... | ... |
| onActivityNotificationCreated | ... | ... | ... | ... | ... | ... |

---

## 6) Plano de execução (48h)

### Dia 1
- Medir baseline das 5 funções (invocations + duração + fan-out).
- Confirmar hot paths por usuário/sessão para `getPeople`.

### Dia 2
- Aplicar cortes P0 (`getPeople` + `onActivityNotificationCreated`).
- Recoletar mesmas métricas e comparar deltas (%).

Critério de sucesso inicial:
- **-30% a -60%** em invocações efetivas de `getPeople` por sessão ativa.
- **-20% a -50%** em invocações de `onActivityNotificationCreated` por evento criado.
- Redução de p95 nas duas funções.

---

## 7) Evidências de código auditadas

- `functions/src/get_people.ts`
- `functions/src/devices/deviceBlacklist.ts`
- `functions/src/users/usersPreviewSync.ts`
- `functions/src/events/usersGridSync.ts`
- `functions/src/activityPushNotifications.ts`
- `functions/src/services/pushDispatcher.ts`
- `functions/src/activityNotifications.ts`
- `lib/services/location/location_query_service.dart`
- `lib/features/home/presentation/screens/find_people/find_people_controller.dart`
- `lib/core/services/location_background_updater.dart`
- `lib/features/location/data/repositories/location_repository.dart`

---

## 8) Conclusão

As 5 funções selecionadas explicam custo por **combinação de volume + cascata + amplificação de leitura**. O maior ganho rápido está em:

1. **Reduzir chamadas de `getPeople` no client** (throttle/debounce/cancelamento).
2. **Conter cascata de `Notifications` → `onActivityNotificationCreated`**.
3. **Reduzir writes frequentes em `Users`** para diminuir gatilhos em cadeia.

Com isso, o custo cai sem refatoração estrutural grande no primeiro ciclo.