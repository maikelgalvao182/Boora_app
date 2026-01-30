# Questionário Técnico — Mapa (Firestore)

## 1) Arquitetura de carregamento do mapa (base)

**1.1) Como você carrega os eventos do mapa?**
**(A) .get() por bounds**
> O `MapDiscoveryService` executa `_queryFirestore` utilizando `.get()`, aplicando filtros `where` para latitude e limitando por `limit()`. A filtragem de longitude ocorre em memória (client-side) após o fetch.

**1.2) O disparo de busca acontece quando:**
**(B) cameraIdle com debounce**
> O `GoogleMapView` aguarda o evento `_onCameraIdle`, aplica um debounce de 200ms (`_handleCameraIdleDebounced`) e delega para o `MapBoundsController`, que valida se é necessário buscar novos dados.

**1.3) Qual é o debounce atual?**
**(A) < 300ms**
> Configurado exatamente em **200ms** tanto no `GoogleMapView` quanto no `MapDiscoveryService`.

**1.4) Você tem distância mínima para considerar “mudou de região”?**
**(A) Sim**
> O `MapBoundsController` implementa lógica de contenção (`isBoundsContained`). Se o novo viewport estiver totalmente contido no quadro da query anterior (e feito há menos de 2s) ou dentro de um "bounds pré-carregado" (prefetch), a busca é evitada.

**1.5) Quantas queries por sessão (estimativa)?**
**(B) 4–10**
> Graças ao debounce e à lógica de "bounds contido", o número de queries é controlado, ocorrendo majoritariamente quando o usuário explora novas áreas significantes.

---

## 2) Retorno por query e limites (paga em reads e em bytes)

**2.1) Quantos documentos você traz por query (média)?**
**(B) 30–100**
> O limite hardcoded (`maxEventsPerQuery`) é de **100** documentos.

**2.2) Você usa limit()?**
**(A) Sim (limit: 100)**
> Implementado via `.limit(maxEventsPerQuery)`.

**2.3) Quando estoura o limite, você:**
**(B) ignora o resto**
> O código não possui lógica de paginação visível no `_queryFirestore`. Retorna os 100 primeiros encontrados pelo índice de latitude.

**2.4) Você traz o doc do evento “inteiro” ou um preview?**
**(A) inteiro**
> O `EventLocation.fromFirestore` armazena o payload completo (`doc.data()`). Não há uso de `.select()` ou projeção (Collection Group 'events_map' é lida, se essa coleção não for uma versão 'lite', traz tudo).

**2.5) O doc de evento tem itens pesados?**
**Sim**
> O objeto `EventModel` e o uso no `EventCardPresenter` sugerem a presença de arrays (como `participants`), URLs de fotos e descrição, que são trafegados no payload do mapa.

---

## 3) Markers: geração, atualização e “rebuilds”

**3.1) Como você cria markers?**
**(C) clusters + markers custom**
> Utiliza `MapRenderController` com `MarkersClusterManager`. Os markers de eventos são gerados com bitmaps customizados (Emojis/Avatares) via `MarkerBitmapGenerator`.

**3.2) Quantas vezes os markers são recriados por sessão?**
**(B) 3–10**
> O `scheduleRender` é chamado no `onCameraIdle`. O `MapRenderController` evita rebuilds se a assinatura dos IDs dos eventos não mudar (`_lastMarkersSignature`), mas atualiza clusters em tempo real.

**3.3) Ao mudar zoom, você:**
**(A) recalcula tudo (o clustering)**
> O `MetricsClusterManager` recalcula clusters quando o zoom muda. Os bitmaps dos markers individuais, entretanto, são cacheados no `MapMarkerAssets`.

**3.4) Você tem cache de bitmaps por userId/eventId?**
**(A) Sim**
> A classe `MapMarkerAssets` mantém caches: `_avatarPinCache`, `_clusterPinCache` e `_clusterPinWithEmojiCache` para evitar regeneração custosa de bitmaps.

**3.5) Seus markers dependem de dados que não vieram na query?**
**(B) Sim, busco depois (N+1)**
> O método `_syncBaseMarkersIntoClusterManager` chama `warmupAvatarsForEvents`, que dispara `AvatarService.getAvatarUrl`. Se a URL não estiver no cache, ocorre leitura na coleção `Users` para cada criador de evento único visível (limitado a 40 por vez).

---

## 4) Avatares e imagens no mapa (custo indireto)

**4.1) A imagem do avatar no marker vem de:**
**(B) precisa buscar users/{uid}**
> O `AvatarService` busca explicitamente o documento do usuário para obter a `photoUrl`, gerando **Reads Adicionais** (N+1) se não estiver em cache.

**4.2) Ao carregar markers, você faz reads extras para:**
- **Organizer profile**: **Sim** (via `AvatarService`).
- **Participantes**: Provavelmente não no marker, mas os dados vêm no payload do evento.

**4.3) Avatares/Thumbs usam:**
**(A) Cache Manager (implícito)** e **(C) Mistura**
> O `MarkerBitmapGenerator` precisa baixar os bytes da imagem para desenhar no Canvas (que vira BitmapDescriptor). Isso geralmente envolve download manual, separado do `CachedNetworkImage` da UI Flutter.

**4.4) Tamanho médio do avatar/thumb:**
**(C) 50–150 KB**
> Se as imagens de perfil originais não tiverem thumbnails otimizados gerados por Cloud Functions, o download baixa a imagem completa para depois redimensionar no Canvas.

---

## 5) Event Card / Bottom Sheet

**5.1) Ao tocar no marker, o card abre com:**
**(A) dados já em memória**
> `EventCardPresenter` injeta o objeto `EventModel` já carregado (preloaded).

**5.2) Enquanto o card está aberto, você mantém algum listener?**
**(A) Não**
> O `EventCardPresenter` inicializa o controlador com `enableRealtime: false`. Portanto, não abre streams de Firestore enquanto o card simples é visualizado.

**5.3) O card dispara reads indiretos?**
- **Organizer Name**: **Sim** (busca em background se faltar).
- **Participantes**: Tenta hidratar do cache/Hive (`_hydrateParticipantsFromCache`).

**5.4) O usuário “passeia abrindo vários cards” por sessão:**
**(B) 4–10** (Estimativa padrão de UX de mapa).

**5.5) Você tem cache de eventById na sessão do mapa?**
**(A) Sim**
> O `MapViewModel` mantém a lista de `_events` carregados, servindo de cache em memória para os cards.

---

## 6) Background / retorno

**6.1) Quando o app volta do background, você:**
**(A) não faz nada (mantém estado)**
> Não há gatilho explícito no `DiscoverScreen` para refetch imediato ao retornar do background (resume). O estado permanece até a próxima interação que invalide o cache/tempo.

**6.2) Você tem “cache por tile/bounds” (Hive) para não refazer queries?**
**(B) Não (implementação parcial/memória)**
> O código do `_queryFirestore` no `MapDiscoveryService` mostra apenas fallback para cache em **Memória** (`_getFromMemoryCacheIfFresh`). A lógica de persistência (Hive) não está ativa no trecho de leitura principal analisado.

**6.3) Você busca “somente delta”?**
**(B) Não**
> As queries buscam sempre a lista completa baseada nos filtros geoespaciais.

---

## 7) Leituras invisíveis

**7.1) Queries duplicadas por init()?**
**(A) Sim (risco existente)**
> Embora haja flags como `_platformMapCreated`, a chamada `_triggerInitialEventSearch` e `mapViewModel.initialize()` podem competir em condições de race condition, embora o `_requestSeq` mitigue o processamento duplicado.

**7.2) Cancelamento de requests?**
**(A) Sim (Lógica Last-Wins)**
> O `MapDiscoveryService` usa um contador monotônico `_requestSeq`. Se um request antigo retornar após um novo ter começado, o resultado é descartado, evitando sobrescrita de estado (embora o custo do Read no Firestore já tenha ocorrido).

---

## 8) Medição

**8.1) Você mede reads por sessão/tela?**
**(A) Sim**
> `AnalyticsService.instance.logEvent('map_bounds_query', ...)` é disparado a cada busca no Firestore.

**8.2) Você mede docs retornados?**
**Sim**
> O parâmetro `docs_returned` é logado no evento de analytics.
