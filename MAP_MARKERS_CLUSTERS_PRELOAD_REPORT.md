# Relatório — pré-carregamento de markers e clusters (Discover / Google Maps)

## Requisitos deste relatório

- Revisar o fluxo **após o Splash**: onde o app “aquece” mapa / markers / clusters.
- Conferir **se existe duplicidade de preload** (mesma coisa disparada em mais de um lugar).
- Responder: o preload carrega **tudo** ou **apenas viewport**.
- Sugerir ajustes de baixo risco para reduzir churn e bugs de "0 markers".

> Base de evidência: `SplashScreen` → `AppInitializerService.initializeCritical()` + `warmupAfterFirstFrame()`; `DiscoverScreen`; `GoogleMapView`; `MapViewModel`; `GoogleEventMarkerService`.

---

## 1) Visão geral do pipeline (quem faz o quê)

### 1.1 `SplashScreen` → `AppInitializerService.initializeCritical()`
- Objetivo declarado: **reduzir tempo de splash** mantendo só inicialização essencial.
- Ações relevantes pro mapa:
  - Ajusta `ImageCache` global (200 imagens / 50MB).
  - “Seed” de localização inicial do usuário via Firestore (`mapViewModel.seedInitialLocation(LatLng(lat,lng))`) para evitar o primeiro frame em localização fallback.
  - Dispara `mapViewModel.initialize()` **se ainda não estiver `mapReady` e não estiver `isLoading`**.

**Conclusão:** no Splash existe um **preload de mapa** (location + primeiros eventos) mas sem tocar em `GoogleMapController` nem em clusters.

### 1.2 Home (pós-primeiro-frame) → `AppInitializerService.warmupAfterFirstFrame()`
- Também chama `mapViewModel.initialize()` (se ainda não estiver pronto/carregando).
- Depois tenta obter um snapshot mínimo (location + events) via `_waitForInitialMapSnapshot()`.
- Faz warmup de avatares do viewport inicial **por aproximação** (raio em km ao redor da localização), porque aqui não há acesso aos bounds reais do mapa.

**Conclusão:** existe um **segundo caminho** de “warmup” do mapa, mas ele é (a) idempotente pelo VM e (b) mais focado em aquecer cache/avatares sem depender do mapa renderizado.

### 1.3 Discover → `DiscoverScreen`
- No primeiro frame:
  - Dispara `mapViewModel.initialize()` best-effort (lazy init; idempotente).
  - Agenda `_scheduleClusterPreloadWhenReady()`.
- `_scheduleClusterPreloadWhenReady()` só executa quando:
  - `PlatformView` do mapa foi criado (`_platformMapCreated == true`)
  - `mapViewModel.mapReady == true`
- `GoogleMapView` sinalizou que o primeiro render de markers foi aplicado (`firstRenderApplied == true`)
- Quando pronto, após 350ms: chama duas ações (best-effort):
  - `prefetchExpandedBounds(bufferFactor: 2.5)` (cobertura / dados)
  - `preloadZoomOutClusters(targetZoom: 3.0)` (compute / clusters)

**Conclusão:** o warmup do Discover fica sincronizado com o **primeiro render aplicado**, evitando aquecer clusters cedo demais (quando ainda estamos no "progressive first render").

**Atualização (implementado):**
- O `GoogleMapView` expõe o callback `onFirstRenderApplied` (dispara 1x) e o método `prefetchExpandedBounds()`.
- O `DiscoverScreen` aguarda `platformCreated + mapReady + firstRenderApplied` e dispara:
  - `prefetchExpandedBounds(bufferFactor: 2.5)`
  - `preloadZoomOutClusters(targetZoom: 3.0)`

Isso aquece:
- **cobertura (dados)**: reduz espera ao pan
- **compute (clusters/bitmaps)**: aquece clusters sem mexer na câmera

### 1.4 Render do mapa → `GoogleMapView`
- Tem um pipeline único de render via `scheduleRender()` → `_rebuildClusteredMarkers()` com debounce e token `_renderSeq`.
- A parte crucial:
  - Obtém bounds via `getVisibleRegion()` quando necessário.
  - Expande bounds com buffer (`_viewportBoundsBufferFactor = 2.0`).
  - Decide se filtra por viewport:
    - `shouldFilterByViewport = zoomSnapshot > _clusterZoomThreshold (11.0)`
    - **Em zoom baixo (cluster ativo), NÃO filtra por viewport.**
  - Faz "progressive first render" limitando a 60 eventos no primeiro paint.
  - Preload de avatares com timeout curto antes de construir markers.

**Conclusão:** o mapa tenta evitar tanto o custo de render quanto o bug de “0 markers” em zoom out, tomando decisões diferentes por zoom.

**Atualização (implementado):**
- Existe um segundo bounds expandido ("zona de gordura") mantido pelo `GoogleMapView` para **decidir se precisa refetch**.
  - Se o viewport atual estiver contido nessa zona, o `onCameraIdle` **pula rede** e faz apenas `scheduleRender()`.
  - Ao sair da zona, o fluxo volta a fazer `loadEventsInBounds` e atualiza a zona.

---

## 2) Onde o preload está duplicado (e se isso é um problema)

### 2.1 `mapViewModel.initialize()` é chamado em três lugares
- `AppInitializerService.initializeCritical()` (Splash)
- `AppInitializerService.warmupAfterFirstFrame()` (Home)
- `DiscoverScreen.initState()` (primeiro frame da tela)

**Por que isso não explode?**
- `MapViewModel.initialize()` tem um guard (`_didInitialize`) e retorna se já rodou.

**Risco real (aqui é o que importa):**
- Mesmo sendo idempotente, **a competição temporal** pode ocorrer:
  - Splash dispara `initialize()`.
  - Home warmup dispara de novo (logo em seguida).
  - Discover dispara de novo.
- Isso aumenta a chance de múltiplos listeners/rebuilds do lado do mapa, e mascara “onde começou”.

**Recomendação:** manter 1 “dono” claro do `initialize()`.
- Melhor prática: deixar o Splash fazer apenas o seed de localização + coisas globais; e deixar a tela do Discover (ou Home warmup) ser a responsável por iniciar o mapa.
- Alternativa de baixo risco: centralizar o “start” no `AppInitializerService` e remover o disparo no `DiscoverScreen`.

### 2.2 Warmup de clusters acontece só no Discover
- A função `preloadZoomOutClusters()` está em `GoogleMapViewState`, então só pode ser chamada depois do `PlatformView` existir.
- `DiscoverScreen` é quem faz isso.

**Conclusão:** não parece haver duplicidade de “cluster warmup” fora do Discover.

**Nota (pós-mudança):** mesmo com duplicidade de `initialize()`, o prefetch correto (viewport real) deve acontecer **depois** do mapa estar criado. Hoje isso é atendido no `GoogleMapViewState` (quando já existe `GoogleMapController`).

---

## 3) O preload carrega o mapa inteiro ou só o viewport?

### 3.1 Carregamento de eventos: bounds-based, não “mundo todo”
- A arquitetura atual declara que a fonte de verdade deve ser viewport/bounds (comentário do VM).
- Porém, **o preload no Splash/VM** chama `loadNearbyEvents()`, que cria um bounds fixo de ~10km (`radiusDegrees = 0.09`) e delega para `loadEventsInBounds(bounds)`.

**Ou seja:** no preload inicial, o app tenta carregar **um recorte local (10 km)**, não o planeta.

### 3.2 Renderização de markers: viewport quando zoom alto; sem filtro quando zoom baixo
Em `GoogleMapView._rebuildClusteredMarkers()`:
- `shouldFilterByViewport = zoomSnapshot > 11.0`
  - zoom alto (sem cluster): filtra eventos para os que estão dentro de bounds expandido.
- zoom baixo (cluster): **não filtra por viewport**.
  - Isso é intencional: evita bug de "0 markers" com bounds instável/grande.
  - Consequência: se `viewModel.events` tiver muitos itens, o cluster vai considerar todos.

**O que isso significa na prática:**
- O app não “prefetch” tudo do mundo no backend, mas pode “clusterizar o que já tem” em memória ao dar warmup em zoom baixo.

### 3.3 `preloadZoomOutClusters()` não move câmera (atualmente)
Apesar do nome, `preloadZoomOutClusters()`:
- não chama `animateCamera`.
- faz apenas:
  - set `_currentZoom = targetZoom` → `scheduleRender()`
  - volta `_currentZoom` → `scheduleRender()`

**Conclusão:** o preload de cluster é “compute/UI-only”: ele usa o dataset já carregado e tenta aquecer bitmaps/clusters sem mudar bounds nem refazer fetch.

**Atualização (implementado):** agora também existe **warmup de cobertura** (não só compute): o mapa faz `loadEventsInBounds` com bounds expandido por viewport real, criando uma área pré-carregada para pans curtos.

---

## 3.4 Cache por tiles (quadkey) — implementado

Antes:
- `MapDiscoveryService` guardava cache para **apenas 1 quadkey** (última região), com TTL.

Agora:
- `MapDiscoveryService` mantém cache **LRU por quadkey** (multi-tiles), com:
  - TTL (`cacheTTL`)
  - limite de memória (máx de tiles em cache)

Impacto:
- pans pequenos (vai e volta) tendem a virar **cache hits**, reduzindo refetch.

---

## 4) Potenciais pontos confusos / bugs prováveis

### 4.1 `MapViewModel` tem `googleMarkers` mas o `GoogleMapView` ignora
- `MapViewModel` gera `_googleMarkers` via `_googleMarkerService.buildEventMarkers()` (não clusterizado).
- `GoogleMapView` sempre constrói `_markers` via `_markerService.buildClusteredMarkers()`.

**Impacto:** `_googleMarkers` parece ser usado só para:
- aquecer cache de bitmaps no init
- logs de diagnóstico

**Risco:** manter duas rotas de geração de marker aumenta confusão e pode levar alguém a “usar markers do VM” no futuro, reintroduzindo bugs de callback.

### 4.2 “progressive first render” + `preloadZoomOutClusters`
- Primeiro paint em `GoogleMapView` pode capar a 60 eventos.
- `DiscoverScreen` agenda o warmup quando `mapReady` + `platform created` + `firstRenderApplied`.

**Risco:** se `mapReady` ficar true antes do `GoogleMapView` ter feito o render completo, o warmup pode aquecer clusters com dataset parcial.
- Isso não quebra, mas pode reduzir o benefício do warmup.

**Mitigação (implementado):** o `GoogleMapView` sinaliza explicitamente quando o 1º `setState` de markers foi aplicado, e o warmup só roda depois disso.

### 4.3 Filtro por viewport desativado em zoom baixo
- É uma defesa contra “0 markers”, mas pode gerar custo alto se o dataset em memória crescer.

**Ideal:** garantir que `viewModel.events` seja sempre limitado ao “query bounds” atual, para que o cluster em zoom baixo não precise considerar um conjunto gigante.

---

## 5) Recomendações práticas (baixo risco)

1) **Definir um único dono para `mapViewModel.initialize()`**.
   - Opção A: apenas `AppInitializerService` (Splash ou warmup), remover em `DiscoverScreen`.
   - Opção B (minha preferida): Splash faz seed de localização + coisas globais; `DiscoverScreen` inicia mapa porque é a primeira tela que realmente precisa dele.

2) **Documentar explicitamente** que `MapViewModel.googleMarkers` existe só para aquecer cache e não deve ser fonte do UI.
   - Isso evita regressão.

3) **Garantir limitação do dataset em memória** ao bounds atual.
   - Assim, em zoom baixo (sem filtro), o custo de cluster continua aceitável.

4) **Melhorar a sincronização do warmup de clusters**:
   - Em vez de depender só de `mapReady`, depender de (a) `mapReady` e (b) primeiro render aplicado (ex.: um flag exposto pelo `GoogleMapViewState` ou evento local).

5) **(Aplicado) Warmup correto pós-splash = baseado em viewport real**:
  - Melhor lugar: `GoogleMapViewState` logo após `getVisibleRegion()` funcionar.
  - Implementação: prefetch de bounds expandido ("zona de gordura") + cache multi-tile no `MapDiscoveryService`.

6) **(Aplicado) Warmup em duas etapas (low-risk) no Discover**:
   - Gatilho: `platformCreated + mapReady + firstRenderApplied`.
   - Ações:
     1) `prefetchExpandedBounds(bufferFactor: 2.5)` (cobertura / dados)
     2) `preloadZoomOutClusters(targetZoom: 3.0)` (compute / clusters)

---

## 6) Respostas diretas às perguntas

- **“Após o splash, como funciona o pré-carregamento?”**
  - Splash chama `initializeCritical()` que pode disparar `mapViewModel.initialize()` (pins + localização + eventos). Depois, no Home warmup, pode rodar novamente, e na tela de Discover também roda. Clusters são aquecidos no Discover via `preloadZoomOutClusters()`.

- **“Tem duplicidade?”**
  - Sim: `mapViewModel.initialize()` é disparado em **3 lugares**. É idempotente, mas ainda aumenta a chance de churn/confusão.

- **“Pré-carrega tudo ou só viewport?”**
  - O fetch inicial é um bounds local (~10km). O render filtra por viewport só em zoom alto; em zoom baixo (cluster), não filtra por viewport e clusteriza o dataset em memória.

---

## Arquivos citados
- `lib/core/services/app_initializer_service.dart`
- `lib/features/home/presentation/screens/splash_screen.dart`
- `lib/features/home/presentation/screens/discover_screen.dart`
- `lib/features/home/presentation/widgets/google_map_view.dart`
- `lib/features/home/presentation/viewmodels/map_viewmodel.dart`
- `lib/features/home/presentation/services/google_event_marker_service.dart`

## Mudanças implementadas nesta branch
- `lib/features/home/presentation/widgets/google_map_view.dart`
  - `_viewportBoundsBufferFactor` 1.3 → 2.0
  - Prefetch por viewport real + "zona de gordura" (skip de rede dentro da área)
  - Callback `onFirstRenderApplied` + método `prefetchExpandedBounds()`
- `lib/features/home/data/services/map_discovery_service.dart`
  - Cache LRU multi-tile por quadkey
- `lib/features/home/presentation/screens/discover_screen.dart`
  - Warmup sincronizado com `platformCreated + mapReady + firstRenderApplied`
  - Dispara: `prefetchExpandedBounds(2.5x)` + `preloadZoomOutClusters(3.0)`
