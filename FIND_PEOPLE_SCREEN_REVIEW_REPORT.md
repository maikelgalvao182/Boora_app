# Revisão Find People — Relatório

**Arquivos analisados:**
- [lib/features/home/presentation/screens/find_people_screen.dart](lib/features/home/presentation/screens/find_people_screen.dart)
- [lib/features/home/data/services/people_map_discovery_service.dart](lib/features/home/data/services/people_map_discovery_service.dart)
- [lib/features/home/presentation/widgets/map_controllers/map_people_controller.dart](lib/features/home/presentation/widgets/map_controllers/map_people_controller.dart)
- [lib/services/location/people_cloud_service.dart](lib/services/location/people_cloud_service.dart)
- [functions/src/get_people.ts](functions/src/get_people.ts)

---

## 1) Gatilhos de atualização da lista

### 1.1) A lista atualiza quando:
- **Apenas em cameraIdle** ✅
  - Fluxo: `MapPeopleController.onCameraIdle()` → `loadPeopleCountInBounds()` → `_executeQuery()`
  - Fonte: [lib/features/home/presentation/widgets/map_controllers/map_people_controller.dart](lib/features/home/presentation/widgets/map_controllers/map_people_controller.dart)
- **Ação manual** (pull‑to‑refresh e filtros) ✅
  - Pull‑to‑refresh chama `refreshCurrentBounds()`
  - Filtros aplicados chamam `refreshCurrentBounds()`
  - Fonte: [lib/features/home/presentation/screens/find_people_screen.dart](lib/features/home/presentation/screens/find_people_screen.dart)

**Não** atualiza em `onCameraMove`.

### 1.2) Existe debounce antes de refazer a query?
- **300–600ms** ✅ (exato: **300ms**)
  - `debounceTime = 300ms`
  - Fonte: [lib/features/home/data/services/people_map_discovery_service.dart](lib/features/home/data/services/people_map_discovery_service.dart)

### 1.3) Existe distância mínima para considerar “nova área”?
- **Sim (mudança de quadkey/tile)** ✅
  - Cache key = `bounds.toQuadkey()` + assinatura de filtros.
  - Fonte: [lib/features/home/data/services/people_map_discovery_service.dart](lib/features/home/data/services/people_map_discovery_service.dart)

---

## 2) Estratégia de busca no Firestore

### 2.1) A query busca:
- **Preview leve** ✅
  - Campos retornados incluem `fullName`, `photoUrl`, `age`, `isVerified`, `overallRating`, `locality`, `state`, etc.
  - Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L280-L360)

### 2.2) Você usa .get() ou .snapshots()?
- **get pontual** ✅
  - Cloud Function `getPeople` usa `.get()`.
  - Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L188-L206)

### 2.3) A query tem limit()?
- **Sim**
  - Firestore query (dinâmica): **base 200/400**, sobe para **400/800** se não atingir mínimo
  - Resultado final retornado: **17 (Free)** / **300 (VIP)**
  - Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L160-L215), [functions/src/get_people.ts](functions/src/get_people.ts#L360-L399)

### 2.4) Existe paginação real (startAfterDocument)?
- **Não**
  - Não há paginação no backend nem no client.

---

## 3) Reconsultas invisíveis

### 3.1) Ao voltar de um perfil para a lista, a query roda de novo?
- **Às vezes** ✅
  - `refreshCurrentBoundsIfStale(ttl: 10min)`
  - Se TTL não expirou → **não** recarrega.

### 3.2) Ao mover o mapa pouco (ex: 100m), refaz a lista?
- **Depende do quadkey**
  - Mesmo quadkey → cache (não refaz)
  - Quadkey diferente → refaz

### 3.3) Ao mudar zoom, refaz a lista inteira?
- **Só se área mudou** (novo quadkey/bounds)
  - E apenas em `cameraIdle`.

---

## 4) Cache da Find People

### 4.1) Existe cache em memória por área/tile?
- **Sim (TTL maior + LRU)** ✅
  - TTL memória: **180s**
  - LRU: **12 tiles**

### 4.2) Existe cache persistente (Hive)?
- **Não**

### 4.3) TTL atual (se existir)
- Memória: **180s**
- Persistente: **—**

---

## 5) Peso dos documentos

### 5.1) Campos trazidos na lista:
- **Apenas preview** ✅
  - `userId`, `fullName`, `photoUrl`, `age`, `isVerified`, `overallRating`, `locality`, `state`, `distanceInKm`
  - Sem bio longa, sem múltiplas fotos, sem preferências completas.

### 5.2) Imagens:
- **Thumbnails** (via `photoUrl` em `users_preview`)
  - Não há indicação de full‑size.

---

## 6) Relação com o mapa

### 6.1) A Find People usa a MESMA query do mapa?
- **Não**
  - Pessoas usam Cloud Function `getPeople` (collection `users_preview`).
  - Eventos usam `events_map`.

### 6.2) Ela recalcula toda vez que markers mudam?
- **Não**
  - Deriva de `bounds` e cache; não depende do render.

---

## 7) Métricas (se existem)

### 7.1) Você mede:
- **docs retornados** ✅
  - `AnalyticsService.logEvent('find_people_query', users_returned, total_candidates)`
- **telemetria de desperdício no backend** ✅
  - `scanLimitUsed`, `scannedDocs`
  - `discarded_by_longitude`, `discarded_by_radius`, `discarded_by_tags`, `discarded_by_age_gender`, `discarded_by_verified`, `discarded_by_status`
  - `cacheHit`, `cacheKey`, `durationMs`
  - `gridQueryUsed`, `gridIdsCount`
- **queries por sessão** ❌

Fonte: [lib/features/home/data/services/people_map_discovery_service.dart](lib/features/home/data/services/people_map_discovery_service.dart)

---

## 8) Comportamento real do usuário

### 8.1) Usuário médio por sessão:
- **Não há telemetria direta** no código analisado.

### 8.2) Tempo médio nessa tela:
- **Não instrumentado**.

---

## Observações objetivas

- A lista **atualiza em cameraIdle** + debounce de **300ms**.
- Há **cache por quadkey + filtros + zoom bucket**, TTL de **180s** e LRU 12.
- Não há **paginação** — o limite é controlado no backend.
- Backend tem **cache em memória (120s)** por bounds+filtros+bucket+plano.
- A fonte primária é **users_preview**, com fallback `Users`.

---

# ✅ Gargalo atual (Find People)

## 1) Backend “escaneia demais”

- `users_preview` é consultado com **scan_limit dinâmico** (200/400 → 400/800).
- Depois disso, aplica filtros **em memória**:
  - longitude
  - radiusKm
  - interesses (hard filter)
  - sexo/idade
- Ranking final: **VIP → rating → distância**.

Resultado: mesmo retornando 17/300, o backend paga leitura de centenas.

## 2) Cache do client é fraco

- TTL atual: **180s**
- **LRU 12 tiles**
- Zoom bucket reduz misses por zoom.

---

# ✅ Melhorias aplicadas (últimas)

## Backend
- **Cache em memória** na Cloud Function (TTL 120s).
- **Scan_limit dinâmico** (base 200/400, sobe para 400/800 se não atinge mínimos).
- **GridId por bucket** (0.02°) para reduzir descarte por longitude.

## Client
- **LRU 12 tiles** + **TTL 180s**.
- **Zoom bucket** na cache key.

---

# ✅ Otimizações recomendadas (ordem de ROI)

## 1) LRU + TTL maior (client)

✅ **Aplicado:** **LRU 12 tiles + TTL 180s (3 min)**

## 2) Zoom bucket

✅ **Aplicado:** cache key inclui zoom bucket para reduzir misses por zoom.

---

# ✅ Questionário de Diagnóstico — Find People (reduzir requests)

## Bloco A — Tamanho e custo da query (principal)

**A1) Por que o backend usa limit(400) (free) e limit(800) (VIP)?**
- ✅ Para poder ordenar/filtrar melhor antes de escolher os 17/300.
- ✅ Por segurança (não faltar resultado após filtros de distância/longitude/interesses).

**A2) O Firestore está lendo users_preview com algum filtro geográfico?**
- ✅ Sim, por **latitude range**.
  - Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L188-L206)

**A3) Você realmente precisa retornar 300 pessoas no VIP em uma única resposta?**
- ❓ Não sei (UX não está documentado no código).
  - Hoje retorna até 300 por chamada.

**A4) Você exibe o total_candidates no UI?**
- ❓ Não sei.
  - O backend retorna `totalCandidates`, mas não há uso explícito na tela.

## Bloco B — Frequência de refetch (mapa → lista)

**B1) A Find People refaz query ao mudar só o zoom (mesma região visual)?**
- **Sim, quase sempre** quando o quadkey muda.
  - Cache depende de `bounds.toQuadkey()`.

**B2) TTL em memória de 30s é suficiente ou você vê revisita frequente?**
- ❓ Não sei (sem telemetria de usuário).
  - TTL atual = 30s.

**B3) Você tem refreshCurrentBoundsIfStale(10min) no retorno de perfil. Esse TTL é por tile ou global?**
- ✅ Por tile + filtros.
  - Cache key = quadkey + assinatura de filtros.

## Bloco C — Paginação e UX (o maior corte de custo)

**C1) Por que ainda não tem paginação?**
- ❓ Não estava no escopo (não há implementação).

**C2) Você consegue aceitar esse UX no VIP?**
- ❓ Não sei.
  - Hoje retorna até 300 por chamada.

## Bloco D — Cache (onde você ainda perde requests)

**D1) Cache atual (30s) não tem LRU. Quando muda de área, você perde tiles antigos?**
- ✅ Agora mantém **12 tiles** via LRU.

**D2) Você quer cache persistente (Hive) também na Find People?**
- ❓ Depende do custo (não implementado).

## Bloco E — “Vazamento invisível”: fallback em Users

**E1) Em que situação o get_people.ts cai para Users?**
- ✅ Quando `users_preview` retorna vazio para o bounds.

**E2) Qual % dos resultados exige fallback?**
- ❓ Não sei (não mede).

## Bloco F — Observabilidade (sem isso você otimiza no escuro)

**F1) Você quer logar estas métricas por chamada?**
- ✅ Recomendo **Sim**.
- Hoje já registra: `users_returned` e `total_candidates`.

---

# ✅ Questionário Cirúrgico — Find People (cortar requests)

## 1) Backend: por que você precisa escanear 400/800?

### 1.1) Quais filtros são aplicados depois do Firestore (em memória) e fazem você “perder muita gente”?
- ✅ distância (km) calculada no backend (Haversine)
- ✅ filtros de interesse (tags)
- ✅ verificado / rating mínimo (verificado; rating só ordenação)
- ❌ “excluir bloqueados” (não encontrado)
- ❌ “excluir já vistos” (não encontrado)
- ✅ sexo/idade
- outros: **status != active**, **longitude** e **radiusKm**

Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L205-L280)

### 1.2) Você ordena a lista por quê?
- ✅ mistura: **VIP priority → rating → distância**

Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L360-L390)

### 1.3) Quanto é o “waste” do scan?
- ❓ Não sei (não instrumentado)
  - scan_limit: **400/800**
  - total_candidates: **retornado** pelo backend, mas sem média no app
  - users_returned: **17/300**

## 2) Geoquery: latitude range está trazendo “gente de longe” (igual eventos)?

### 2.1) Você filtra longitude também no Firestore?
- ✅ Não (só latitude range) → longitude é filtrada em memória.

Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L188-L230)

### 2.2) Você mede quantos candidatos foram descartados por longitude?
- ❌ Não

## 3) UX: VIP precisa mesmo de 300 de uma vez?

### 3.1) O usuário realmente rola 300 cards com frequência?
- ❓ Não sei (sem telemetria)

### 3.2) Você aceitaria VIP assim?
- ❓ Não sei (decisão de produto)

## 4) Cache no client: hoje você está “jogando fora” tiles

### 4.1) Quantos tiles você quer manter em memória?
- ✅ **12 (LRU aplicado)**

### 4.2) TTL de memória (30s) deve virar:
- ✅ **180s aplicado**

### 4.3) Você quer Hive na Find People?
- ❓ Não sei (não implementado)

## 5) Quadkey/zoom: seu cache está instável por “mudança de chave”

### 5.1) Seu bounds.toQuadkey() muda facilmente ao mudar zoom 1 nível?
- ✅ Sim (quadkey muda com bounds/zoom)

### 5.2) Você aceitaria travar a Find People para atualizar só quando:
- ❓ Não sei (não implementado)

## 6) Fallback em Users: ainda pode existir vazamento

### 6.1) users_preview já cobre 100% dos usuários que devem aparecer?
- ❓ Não sei (depende do sync/backfill)

---

# ✅ Questionário Final — Find People (decidir arquitetura e cortar requests)

## A) Produto/UX (define se você pode paginar e cortar scan)

**A1) No VIP, você realmente precisa entregar 300 na primeira resposta?**
- ❓ Não sei (decisão de produto; não está no código).

**A2) No Free, 17 é fixo por UX ou pode ser “até 20/30”?**
- ❓ Não sei (decisão de produto; limite é aplicado no backend).

**A3) Você aceita trocar “auto atualizar sempre” por “Buscar nesta área” (botão)?**
- ❓ Não sei (não implementado no código atual).

## B) Ranking (define se você precisa do scan alto)

**B1) O ranking VIP priority → rating → distância precisa ser “perfeito” ou pode ser “aproximado”?**
- ✅ Precisa ser **perfeito** (ranking aplicado no backend com VIP → rating → distância).

**B2) Interesses/tags são “hard filter” (exigir match) ou “soft boost”?**
- ✅ **Hard filter** (exige intersecção).

Fonte: [functions/src/get_people.ts](functions/src/get_people.ts#L240-L280)

## C) Geo (define se você vai precisar de geohash/tiles de verdade)

**C1) Você aceitaria armazenar no users_preview um campo geohash (ou tileId) e consultar por prefixos?**
- ❓ Não sei (decisão técnica/produto).

**C2) O radiusKm típico do Find People é:**
- ❓ Não sei (depende do filtro do usuário; há cap por plano no backend).

## D) Cache (define quanto você reduz refetch com revisita)

**D1) Você quer cache por tile com LRU?**
- ✅ Sim (LRU 12 aplicado).

**D2) TTL de cache para Find People pode ser:**
- ✅ **180s aplicado**.

