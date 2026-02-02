# PeopleMapDiscoveryService — Questionário Respondido

## 1) Objetivo e escopo da consulta

**Qual é exatamente a responsabilidade do PeopleMapDiscoveryService?**
- Responsável por buscar pessoas dentro do *bounding box* atual do mapa, calcular lista e contagem (totalCandidates), alimentar a UI com `nearbyPeople` e `nearbyPeopleCount`, e manter cache (memória + persistente). Também controla `isViewportActive` e `isLoading`.

**Qual é o “SLA” esperado pra essa info no mapa?**
- Não está explicitamente definido no código. Há cache em memória (TTL 180s) e persistente (TTL 6h) com soft refresh em 45 min, indicando tolerância de minutos em alguns cenários.

**O resultado é usado só pra UI ou influencia lógica?**
- Usado para UI (botão “Perto de você”, contagem, cards). Não há lógica de ranking/segurança/match baseada nesse resultado no serviço.

## 2) Gatilhos de execução

**Quais eventos disparam `_executeQuery()` hoje?**
- `loadPeopleCountInBounds()` (chamado no `onCameraIdle` quando zoom > threshold)
- `forceRefresh()`
- `refreshCurrentBounds()`
- `refreshCurrentBoundsIfStale()`
- `preloadForBounds()` (com `publishToNotifiers: false`)

**Existe cenário em que `onCameraIdle` é disparado “sozinho”?**
- Sim, o Google Maps pode disparar `onCameraIdle` após animações programáticas (fitBounds, recenter, animateCamera).

**`onCameraIdle` pode disparar em sequência sem o usuário mexer? Com que frequência?**
- Sim. Em animações múltiplas/ajustes de câmera, pode ocorrer em sequência. O debounce de 300ms agrupa chamadas próximas; além disso, há throttle global de 2s.

## 3) Controle de frequência (debounce/throttle)

**O debounce de 300ms é por instância ou global?**
- Global efetivo: `PeopleMapDiscoveryService` é singleton. Um único debounce para o app.

**Há throttle por tempo (ex: no máximo 1 query a cada X s)?**
- Sim. Throttle global de 2s para chamadas via `onCameraIdle` (mantém `forceRefresh` sem atraso).

**Existe “gate” por mudança mínima de câmera?**
- Não. Não há verificação de deslocamento mínimo, nem bucket de zoom para evitar consultas.

**Existe single-flight por key?**
- Sim. Requisições em voo por `cacheKey` são deduplicadas (single-flight).

## 4) Formato da query no banco

**A consulta real no banco é:**
- Cloud Function via `PeopleCloudService.getPeopleNearby()`.

**Algoritmo híbrido (geohash/quadkey)?**
- A consulta usa bounding box + radius (calculado para cobrir o bounds). Não há geohash no client.

**Campos/índices usados?**
- Não visível no client (depende da Cloud Function). No client, são enviados filtros: gênero, idade, verificação, interesses, orientação.

**A query retorna:**
- Lista de usuários com dados completos (payload do cloud), além de `totalCandidates`.

**Existe paginação/limit?**
- O limit é controlado pela Cloud Function; no client não há paginação explícita.

**A query é barata?**
- Não dá para afirmar; depende do backend. Em regiões densas, tende a ser custosa.

## 5) Chave de cache (cache key) e estabilidade

**Como é calculado `bounds.toQuadkey()`?**
- Usa centro do bounds arredondado (precision 2) + bucket de span (baseado no tamanho do bounds). Não depende diretamente do zoom.

**Qual é o “zoom bucket”?**
- `z0` ≤ 11.0, `z1` ≤ 13.0, `z2` ≤ 15.0, `z3` > 15.0. Total: 4 buckets + `unknown`.

**Pequenas variações de bounds mudam a key com frequência?**
- Sim. Mudanças pequenas no centro ou span podem alterar o quadkey e gerar cache miss.

**A key inclui filtros?**
- Sim. Inclui gênero, min/max age, isVerified, sexualOrientation, radiusKm e interesses (ordenados). Não inclui userId, locale nem ordenação.

**Amostra/log das últimas keys?**
- Não existe logging nativo para keys no serviço.

## 6) Cache em memória (TTL 180s)

**Cache por sessão ou por tela?**
- Por sessão (singleton).

**É LRU?**
- Sim, LRU simples com limite de 24 itens.

**TTL é sliding ou absoluto?**
- Absoluto (baseado em `fetchedAt`); porém o cache é “tocado” no LRU em cada acesso.

**Guarda payload inteiro?**
- Sim. Guarda lista de usuários completa e contagem.

**Guarda metadados?**
- Guarda timestamp (`fetchedAt`). Não guarda bounds expandido nem containment.

## 7) Cache persistente (TTL 6h) + “soft refresh”

**Onde fica?**
- Hive (`people_map_tiles`).

**Chave é a mesma do cache em memória?**
- Sim.

**O que significa “soft refresh 45 min”?**
- Se o item do cache persistente tiver idade ≥ 45 min, dispara refresh em background **somente** quando:
	- `isViewportActive == true`
	- não houve movimento de câmera nos últimos ~4s
	- não existe request em voo para a mesma key
	- respeita cooldown de 10 min por key
	- não é preload/background (`publishToNotifiers: false`)

**Roda se usuário saiu da tela?**
- Não, pois exige `isViewportActive == true`.

**Roda mesmo com request em voo?**
- Não. Há bloqueio por request em voo (single-flight) e cooldown por key.

**Quantos refreshes paralelos?**
- Limitado por single-flight + cooldown por key.

**Existe dedupe por key?**
- Sim, single-flight por key.

## 8) Reuso de resultados (histerese / bounds expandido)

**Usam bounds expandido?**
- Não no PeopleMapDiscoveryService.

**Existe regra de containment (não consultar se viewport contido)?**
- Sim. Existe bounds expandido com containment estrito; enquanto o viewport estiver dentro do coverage, não há nova query.

**Barreira para implementar?**
- Já implementado: coverage bounds + checagem de contenção + margem menor em zoom alto.

**Tolerância de “desatualização espacial”?**
- Não definida no código.

## 9) Invalidadores (o que derruba o cache)

**Quais mudanças invalidam cache hoje?**
- Mudança de filtros (pois compõe a key), mudança de bounds (quadkey), mudança de zoom bucket.
- `forceRefresh()` remove a key atual do cache.

**Invalidadores poderiam ser separados?**
- Sim, algumas dimensões poderiam ser cacheadas separadamente (ex.: filtro de verificação vs interests).

**`forceRefresh()` é usado onde?**
- Chamado via `refreshCurrentBounds()` e potencialmente por fluxos de UI; depende do uso externo.

## 10) Indicadores de “requisições exageradas”

**Há logging/analytics?**
- Há logging local e `AnalyticsService` para `find_people_query`, além de contadores locais:
	- `calls_total`
	- `calls_by_trigger` (idle/refresh/preload/stale)
	- `cache_hit_memory`
	- `cache_hit_hive`
	- `cache_miss`
	- `in_flight_joined`
	- Log amostral (1% das sessões) com últimas 10 cache keys + trigger + idade + movimento.

**Mediana/p95 por sessão?**
- Não disponível no código.

## 11) Custos e impacto no Firestore

**Cada query lê quantos documentos?**
- Determinado pela Cloud Function (não visível no client).

**Fan-out?**
- O client não faz fan-out; depende do backend.

**get() ou streams?**
- É request pontual para Cloud Function.

**Existe listener em paralelo?**
- Não no client. Apenas a chamada da Cloud Function.

## 12) UX e tolerâncias para cache mais agressivo

**Aceitam não atualizar imediatamente?**
- O código atual já aceita (debounce + TTL). Não há regra explícita.

**Risco real de mostrar pessoas fora do bounds?**
- Não definido. Atualmente o backend recebe bounds, então o retorno tende a ser correto.

**Aceitam contagem aproximada?**
- Não definido no código.

**Precisão por zoom?**
- O cache key muda por bucket, mas não existe regra formal de precisão. Em zoom alto, maior sensibilidade de bounds gera mais miss.

**Cenário de segurança/privacidade?**
- Não há regra explícita no client.

## 13) Propostas de cache agressivo

**Possíveis de implementar com baixo impacto:**
- Cache estável por tiles (quadkey menos sensível)

**Qual mais fácil hoje?**
- Cache estável por tiles (quadkey menos sensível).

**Risco mais temido?**
- Hoje o maior risco observado é “cache miss” em pan leve gerando chamadas frequentes e instabilidade de UI.
