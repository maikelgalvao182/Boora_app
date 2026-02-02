# Mapa — Frame, Pipeline, Cache e Clusters (baseado no código atual)

> Escopo: comportamento observado no app hoje com base em [lib/features/home/presentation/widgets/google_map_view.dart](lib/features/home/presentation/widgets/google_map_view.dart), [lib/features/home/presentation/widgets/map_controllers/map_bounds_controller.dart](lib/features/home/presentation/widgets/map_controllers/map_bounds_controller.dart), [lib/features/home/presentation/widgets/map_controllers/map_render_controller.dart](lib/features/home/presentation/widgets/map_controllers/map_render_controller.dart), [lib/features/home/presentation/services/marker_cluster_service.dart](lib/features/home/presentation/services/marker_cluster_service.dart), [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart) e [lib/features/home/data/services/people_map_discovery_service.dart](lib/features/home/data/services/people_map_discovery_service.dart).

---

## 1) Objetivo e regra do “frame”

**O que exatamente significa “renderizamos apenas dentro do frame”?**
- Na prática, o render usa **bounds expandidos do viewport** (não apenas o viewport estrito). O `MapRenderController` lê `lastExpandedVisibleBounds` do `MapBoundsController` e consulta clusters apenas dessa área.

**É um bounding box do viewport atual?**
- Sim, mas **expandido**: o `MapBoundsController` calcula `expandedBounds` a partir do `visibleRegion`.

**É um raio em torno do centro?**
- Não. O cálculo é por bounding box, não raio.

**Tem margem extra (buffer) além da tela?**
- Sim. O buffer do viewport é **3.0x** (`viewportBoundsBufferFactor`). Além disso existe um prefetch mais amplo **4.0x** para eventos (`_prefetchBoundsBufferFactor`).

**Qual é o SLA que você considera aceitável?**
- **Não há SLA explícito no código**. Pelo pipeline atual, o tempo típico é dominado por:
  - debounce do idle no mapa: **600 ms**
  - debounce do render: **150 ms**
  - debounce/query do serviço de eventos: **600 ms**
  - rede/Firestore/Cloud Function (variável)

**Ao mover o mapa, em quantos ms/seg os markers devem aparecer?**
- **No estado atual**, o render tende a aparecer **~750 ms a 1.2 s** após o `onCameraIdle`, dependendo da resposta de rede.

**Você aceita “carregar progressivo” (primeiro clusters, depois markers)?**
- Sim, a implementação atual já é **progressiva** por design:
  - clusters aparecem com base no dataset atual
  - markers individuais aparecem conforme o zoom e o render de ícones (bitmap) termina

**O mapa serve só pra descoberta ou também é crítico pra ações imediatas?**
- Atualmente ele é **misto**: descoberta + ações imediatas (abrir evento, rota, etc.). Isso é evidente pela presença de `EventCardPresenter` e `onMarkerTap`.

**Isso muda o nível de agressividade do cache/pré-fetch?**
- Sim. O código já usa:
  - cache em memória + cache persistente (Hive)
  - bounds expandido para reduzir “buracos”
  - fallback de clusterização global quando o bounds retorna vazio

---

## 2) Fonte dos dados e volume

**Os dados dos markers vêm de onde?**
- Eventos vêm do **Firestore** via `MapDiscoveryService`.
- Pessoas vêm de **Cloud Function** via `PeopleCloudService`.

**Os markers são:**
- Principalmente **eventos** (clusters + markers individuais).
- Pessoas não geram markers no mapa, mas alimentam contagem no `PeopleButton`.

**Volume real:**
- **Não definido no código**. O serviço aceita até **1500 eventos por query** no mapa (ver `maxEventsPerQuery`).

**No zoom out máximo, quantos pontos entram no viewport?**
- **Não há valor fixo no código**. Existe limite lógico pelo `maxEventsPerQuery` e pela própria query do Firestore.

**Os dados são “pré-indexados por geohash/tiles”?**
- Sim, existe **cache por quadkey** (tile lógico) no `MapDiscoveryService`.

**Query é por bounds direto?**
- Sim, a query é **por bounding box** (bounds). O cache organiza por quadkey derivado do bounds.

---

## 3) Pipeline de carregamento (o ponto mais importante)

**Quais eventos disparam a query hoje?**
- `onCameraIdle` do mapa (depois do debounce de 600 ms) chama `MapBoundsController.onCameraIdle`.
- `onCameraMove` apenas faz lookahead (cache), não executa query real.

**Existe debounce?**
- Sim:
  - `GoogleMapView` aplica debounce de **600 ms** no `onCameraIdle`.
  - `MapDiscoveryService` aplica debounce de **600 ms** antes da query real.
  - O render de markers tem debounce de **150 ms**.

**Você faz cancelamento de requisições antigas?**
- Sim, existe **last-write-wins** no `MapDiscoveryService` via `requestSeq`.

**Você controla concorrência?**
- Sim, a query é **sequenciada** e o serviço ignora resposta antiga.

**O que acontece quando a query retorna vazia?**
- **Não limpa imediatamente**. `MapViewModel` mantém markers antigos se a query ainda está `isLoading`. Só limpa quando o vazio é “confirmado”.

---

## 4) Cache e persistência

**Você usa cache?**
- Sim.

**Memória:**
- Cache LRU por quadkey no `MapDiscoveryService`.
- Cache em memória de clusters por zoom e bounds no `MarkerClusterService`.

**Persistente:**
- Hive para eventos (`events_map_tiles`) com TTL de **10 min**.
- Hive para pessoas (`people_map_tiles`) com TTL de **2 horas**.

**Existe stale‑while‑revalidate?**
- Sim. O `MapDiscoveryService` tenta cache (memória → Hive) e faz refresh em background.

**Chave do cache:**
- Eventos: **quadkey** do bounds.
- Pessoas: **quadkey + filtros + zoom bucket**.

**Quando você “sai do frame e volta”, por que não recarrega?**
- Possíveis causas **no código atual**:
  - bounds contido + janela mínima de 2s (`_minIntervalBetweenContainedBoundsQueries`)
  - cache por quadkey ainda válido
  - flags de cobertura (people) impedindo novas queries

---

## 5) Estado da UI e ciclo de vida

**Onde o estado dos markers vive?**
- Em `MapRenderController` e `MapViewModel` (estado do dataset + render).

**Ao navegar entre telas ou rebuild:**
- O `GoogleMapView` recria controllers no `initState` e limpa no `dispose`.
- O dataset pode persistir no `MapViewModel` (singleton). O render é refeito.

**Existe dispose limpando algo que não deveria?**
- O fluxo atual limpa apenas controllers/streams e o GoogleMapController. Não há limpeza agressiva de cache global.

**Você usa `setState` em alta frequência?**
- Não diretamente. O render usa `Listenable` e debounce.

**Você tem logs úteis?**
- Sim, existem logs em:
  - `MapBoundsController` (camera idle)
  - `MapDiscoveryService` (cache HIT/MISS)
  - `MapRenderController` (rebuild)

---

## 6) Cluster: estratégia e implementação

**Clusterização é feita onde?**
- **No cliente** (Dart), em runtime.

**Qual lib/abordagem?**
- **Fluster** (Supercluster port).

**Quando você dá zoom:**
- Recalcula clusters por zoom e usa cache por zoom/bounds.

**O que aparece primeiro?**
- Por padrão, clusters aparecem primeiro e depois markers individuais em zoom alto.

---

## 7) Renderização e performance (Flutter/Google Maps)

**Como você cria ícones?**
- `BitmapDescriptor` gerado por canvas (`MarkerBitmapGenerator`).
- Ícones de avatar são carregados via cache manager.

**Você gera bytes uma vez e cacheia?**
- Sim, há cache em memória em `MapMarkerAssets`.

**Update substitui o Set inteiro?**
- Sim. O `MapRenderController` gera `nextMarkers` e substitui o Set, mas usa “stale markers” por 2s para evitar flicker.

---

## 8) O bug “aparece, some, fica vazio”

**Possíveis causas (baseado no código):**
- Query retornou vazia após debounce e confirmou vazio → limpeza.
- `bounds` retornou vazio por corrida e caiu no fallback (clusterização global). Se o fallback também não renderiza, pode parecer vazio.
- `coverage`/`throttle` impedindo nova query (particularmente para people count).

### Diagnóstico provável (em ordem de chance)

1) **“Vazio confirmado” está limpando o mapa num momento errado**

Mesmo que o fluxo “não limpe imediatamente”, o sintoma clássico é:
- resposta vazia chegando atrasada (ou de um bounds intermediário)
- o sistema tratando como “vazio válido” → aplica `nextMarkers = {}`

No pipeline atual há **3 debounces em cascata**:
- 600 ms no `onCameraIdle`
- 600 ms no `MapDiscoveryService`
- 150 ms no render

Isso aumenta a chance de:
- usuário mexer de novo antes do pipeline estabilizar
- resposta “do passado” ainda ser tratada como válida em algum ponto

✅ **Como confirmar (log mínimo)**
Quando limpar markers, logar:
- `clearReason` (ex: `empty_confirmed`, `bounds_mismatch`, `coverage_throttle`, `dataset_reset`)
- `requestSeq` aplicado
- `boundsKey` aplicado
- `eventsCount` retornado
- `hadStaleMarkers` e quantidade

Se aparecer `empty_confirmed` logo depois de ter mostrado markers, é isso.

✅ **Correção prática (impacto imediato na UX)**

Regra anti‑vazio: **nunca aplicar set vazio** se:
- havia markers antes **e**
- o usuário ainda está dentro de uma região já coberta por cache **ou**
- o vazio veio de bounds contido/throttled/prefetch

Em vez de limpar:
- mantém stale markers
- mostra um loading discreto (ou nada)
- só limpa se for “vazio forte” (ex: 2 ciclos consecutivos de vazio para o mesmo `boundsKey`, ou vazio com confirmação de cobertura)

---

## 9) Observabilidade (pra fechar rápido)

**Logs recomendados (já existem em parte):**
- `camera idle` com bounds + zoom
- `fetch start/end` com request id + cache HIT/MISS
- `markers set count`
- `clear markers reason`
- flags: `isLoading`, `lastBoundsKey`, `lastFetchAt`

---

## 10) Resultado esperado

**Comportamento atual está mais próximo de:**
- **A)** Mantém markers antigos durante loading, e só limpa quando vazio é confirmado.
- **C)** Clusters primeiro, detalhes depois.

Se quiser mudar para B ou D, dá para ajustar:
- aumentar a “zona de gordura”
- forçar fallback de clusterização global
- pré-carregar tiles vizinhos (já existe base, dá para expandir)
