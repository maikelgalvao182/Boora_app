# Diagnóstico — Migração lat/lng → geohash (Users + Events)

> **Data:** 3 de fevereiro de 2026

## Resumo rápido

- **Events usam geohash:** sim (campo `geohash` + `location.geohash`).
- **Users usam geohash:** sim (campo `geohash` em `Users` e em `users_preview`).

---

## A) O que mudou exatamente na migração

**Geohash é gerado onde?**
- **Events:** gerado no backend via Cloud Function `onEventWriteUpdateGeohash` (on-write). Há também backfill via HTTP `backfillEventGeohash`.
- **Users:** gerado no client na atualização de localização e também no backend (`usersGridSync` e `backfillUserGeohash`).

**Tipo de migração:**
- **Events:** **híbrida** (backfill + on-write).
- **Users:** **híbrida** (backfill + on-write + client update).

**Latitude/longitude removidos?**
- **Não.** O geohash é calculado a partir de `location.latitude/longitude` ou `latitude/longitude`, e esses campos continuam presentes como fonte de verdade.

**Nome do campo geohash:**
- **Events:** `geohash` e também `location.geohash`.
- **Users:** `geohash` (em `Users` e `users_preview`).

**Tipo do campo:**
- **String** (gerado por encode geohash; validado em código).

**Evidências:**
- Events on-write/backfill: [functions/src/events/eventGeohashSync.ts](functions/src/events/eventGeohashSync.ts), [functions/src/migrations/backfillEventGeohash.ts](functions/src/migrations/backfillEventGeohash.ts)
- Users on-write/backfill: [functions/src/events/usersGridSync.ts](functions/src/events/usersGridSync.ts), [functions/src/migrations/backfillUserGeohash.ts](functions/src/migrations/backfillUserGeohash.ts)
- Client geohash em atualização de usuário: [lib/features/home/presentation/viewmodels/parts/map_viewmodel_location.part.dart](lib/features/home/presentation/viewmodels/parts/map_viewmodel_location.part.dart)

---

## B) Validação do dado (a parte mais importante)

**EventId e UserId reais:** não acessíveis por código (precisam ser fornecidos do console). 

**O que o código espera/usa:**
- **Events:**
  - `geohash` string (precisão **7** no backend)
  - `location.latitude/longitude` ou `latitude/longitude` numéricos
  - `status`, `isActive`, `isCanceled` usados como filtros client-side
- **Users:**
  - `geohash` string (precisão **7** no backend e no client)
  - `latitude/longitude` numéricos

**Checagens exigidas (manual):**
- Latitude no Brasil tende a ser **negativa**.
- Latitude entre **-90..90** e longitude entre **-180..180**.
- `geohash` deve decodificar próximo ao ponto real.

**Evidências:**
- Geohash e filtros em eventos: [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart)
- Geohash no backend users/events: [functions/src/events/usersGridSync.ts](functions/src/events/usersGridSync.ts), [functions/src/events/eventGeohashSync.ts](functions/src/events/eventGeohashSync.ts)

---

## C) Compatibilidade do algoritmo de geohash

**Flutter (client):** `GeohashHelper` com base32 clássica `0123456789bcdefghjkmnpqrstuvwxyz`.

**Backend (functions):** `encodeGeohash` com a **mesma base32**.

**Conclusão:** implementações **compatíveis** (mesmo alfabeto, mesma lógica). Mismatch tende a vir de **lat/lng invertidos**, tipo errado ou campo diferente.

**Evidências:**
- Flutter geohash: [lib/core/utils/geohash_helper.dart](lib/core/utils/geohash_helper.dart)
- Backend geohash: [functions/src/utils/geohash.ts](functions/src/utils/geohash.ts)

---

## D) Query por prefixo: prefixo correto?

**Events (mapa):**
- `orderBy('geohash')` + `startAt([cell])` + `endAt(['$cell\uf8ff'])`.
- Prefixo vem de células geradas por bounds (precisão 4–7).

**Users (backend People/geo):**
- Usa `orderBy('geohash')` + `startAt(cell)` + `endAt(cell + "~")`.

**Conclusão:** prefix search existe para **Events e Users**. Se query por prefixo do próprio doc retorna 0, o problema tende a ser **campo errado** ou **dados inválidos**.

**Evidências:**
- Query por prefixo de eventos: [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart)
- Query por prefixo de users (backend): [functions/src/services/geoService.ts](functions/src/services/geoService.ts)

---

## E) Pós-filtros (pode achar docs e jogar fora)

**Events (client-side):**
- `isCanceled == false`
- `status == active` **ou** `isActive == true`
- filtro adicional por bounds (descarta fora do viewport)

**Conclusão:** se `fetched > 0` e `kept = 0`, o problema provavelmente está em **status/isActive/isCanceled** ou **lat/lng inválidos**.

**Evidências:**
- Filtros de eventos: [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart)

---

## F) UI/Render/Cluster (achou evento mas marker some)

**Situação no código:** existe pipeline `MapDiscoveryService → MapViewModel → render/cluster`. Nenhum filtro “hard” na UI foi identificado aqui, mas isso **precisa de logs locais** quando `events > 0`.

**Conclusão:** sem logs indicando `events > 0` e `markers=0`, não dá para cravar falha de render.

---

## G) Users vs Events: usar geohash para user vale a pena?

**Users:**
- Backend já usa geohash para busca por área (`queryUsersByGeohash`).
- `users_preview` recebe `geohash` e `gridId` para acelerar consultas e agregações.

**Events:**
- Mapa usa geohash diretamente no client para `events`.

**Conclusão:** geohash é **usado em ambos**. Ainda assim, **lat/lng seguem sendo fonte de verdade** para bounds, distância e renderização.

**Evidências:**
- Users geohash backend: [functions/src/services/geoService.ts](functions/src/services/geoService.ts)
- Users geohash sync: [functions/src/events/usersGridSync.ts](functions/src/events/usersGridSync.ts)
- Events geohash query: [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart)

---

## Conclusões objetivas

- **Sim, o app usa geohash para Events e Users.**
- **Migração é híbrida** (backfill + on-write) em ambos.
- **Lat/lng não foram removidos** e continuam sendo fonte de verdade.
- **Algoritmo compatível** entre Flutter e backend.

Se houver falha real, as causas mais prováveis são:
1. `geohash` ausente/errado/tipo inválido em docs reais.
2. `status/isActive/isCanceled` eliminando tudo no client.
3. Ambiente errado (projectId diferente) ou regras bloqueando leitura.

---

# Questionário (enriquecido) — Migração lat/lng → geohash

## 1) Onde lat/lng “moram” hoje?

**Events (fonte oficial):**
- ✅ `location.latitude` e `location.longitude` são usados como fonte principal no app (ver `EventLocation.fromFirestore`).
- Existe suporte no backend para **topo do doc** (`latitude/longitude`) como fallback na geração de geohash (Cloud Functions).

**Users (fonte oficial):**
- ✅ `latitude`/`longitude` no topo do doc são usados nas migrações e no backend.
- ✅ O app também grava `displayLatitude/displayLongitude` e `geohash` via `updateUserLocation`.

**Período em que o app escreve só `location.*` e não escreve o topo?**
- **Possível.** `EventLocation.fromFirestore` lê **apenas `location.*`** e ignora topo; já as funções fazem fallback para topo. Isso indica coexistência de formatos.

**Evidências:**
- Events leitura: [lib/features/home/data/models/event_location.dart](lib/features/home/data/models/event_location.dart)
- Events geohash on-write/backfill: [functions/src/events/eventGeohashSync.ts](functions/src/events/eventGeohashSync.ts), [functions/src/migrations/backfillEventGeohash.ts](functions/src/migrations/backfillEventGeohash.ts)

## 2) O app lê lat/lng de onde?

**No `EventLocation.fromFirestore`:**
- ✅ Lê **somente** `doc['location']['latitude']` e `doc['location']['longitude']`.
- ❌ **Não há fallback** para `doc['latitude'] / doc['longitude']`.

**Se latitude/longitude são null:**
- Hoje vira **0.0/0.0**, e depois é descartado por bounds (ou vira marcador inválido).

**Etapa que descarta eventos sem lat/lng:**
- ✅ No filtro de bounds do `MapDiscoveryService` (se fora do retângulo, é descartado).

**Implicação:**
- Se os eventos só têm lat/lng no topo, **o mapa vai descartar tudo**.

**Evidências:**
- Parser: [lib/features/home/data/models/event_location.dart](lib/features/home/data/models/event_location.dart)
- Filtro bounds: [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart)

## 3) Escrita e migração

**Backfill/migração preenche:**
- **Events:** `geohash` + `location.geohash` (não escreve lat/lng). 
- **Users:** `geohash` no topo e também em `users_preview`.

**Latitude/longitude no topo foram removidos?**
- **Não há evidência de remoção automática** no código; continuam sendo lidos como fallback no backend.

**Criação de evento grava lat/lng onde?**
- **Indefinido no código analisado** (precisa confirmar no fluxo de criação). O reader atual exige `location.*`.

**Evidências:**
- Events backfill: [functions/src/migrations/backfillEventGeohash.ts](functions/src/migrations/backfillEventGeohash.ts)
- Users backfill: [functions/src/migrations/backfillUserGeohash.ts](functions/src/migrations/backfillUserGeohash.ts)

## 4) Consistência de status (pra não saturar célula)

**Regra atual no client:**
- `status == 'active'` **ou**, se `status` está vazio, `isActive == true`.
- `isCanceled == false`.

**Se existem divergências (`status` vs `isActive`):**
- Eventos com `status='inactive'` e `isActive=true` **serão descartados**.
- Eventos com `status='active'` e `isActive=false` **passam** (status tem precedência).

**Evidências:**
- Filtros: [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart)

## 5) Prova final (teste rápido com doc real)

Pegue um doc real do log (ex.: `WWj7T3...` ou `93AIk...`) e confirme:

- Tem `latitude/longitude` **no topo**? (pelo log, **não**)
- Tem `location.latitude/longitude` preenchido? (**sim**, pelo log de `location`)
- Deveria virar marker? (**sim**, se ativo e dentro bounds)

✅ **Se “sim”, a correção imediata é adicionar fallback no parser** (`EventLocation.fromFirestore`) para ler topo quando `location.*` estiver ausente.

---

# Questionário de Diagnóstico — Migração lat/lng → geohash (Users + Events)

## 0) Recorte do problema (pra não misturar causas)

**O bug é:**
- ( ) Events não aparecem no mapa
- ( ) Users (people) não aparecem no mapa
- ( ) Os dois
- ( ) Intermitente (aparece e some)

**Quando o bug acontece, você vê no log:**
- ( ) fetched > 0 e kept = 0
- ( ) fetched = 0 em todas as cells
- ( ) MapDiscovery stale not applied
- ( ) markers=0 mesmo com events.length > 0 no VM

**Acontece:**
- ( ) Só com zoom alto (aproximado)
- ( ) Só com zoom baixo (mundo/estado)
- ( ) Em qualquer zoom

## 1) Formato do documento (schema real no Firestore)

### Events

Para um `eventId` que deveria aparecer, quais campos existem no topo do doc `events/{id}`?
- ( ) latitude (double)
- ( ) longitude (double)
- ( ) geohash (string)
- ( ) nenhum desses

Dentro de `events/{id}.location`, quais existem?
- ( ) location.latitude (double)
- ( ) location.longitude (double)
- ( ) location.geohash (string)
- ( ) nenhum desses

Hoje, qual campo é a “fonte de verdade” de coordenada pra evento?
- ( ) topo (latitude/longitude)
- ( ) location.latitude/longitude
- ( ) depende do fluxo (às vezes um, às vezes outro)

Quando vocês rodam a Cloud Function `onEventWriteUpdateGeohash`, ela calcula a partir de:
- ( ) location.latitude/longitude
- ( ) topo latitude/longitude
- ( ) ambos com fallback

O backfill de eventos também garante que exista lat/lng em algum lugar?
- ( ) sim, ele preenche location.latitude/longitude
- ( ) sim, ele preenche topo latitude/longitude
- ( ) não, ele só escreve geohash

**Sinal de bug comum:** backfill escreve geohash, mas os lat/lng ficaram só em location e o app lê topo (ou o oposto).

### Users

Para um `userId`, o que existe no topo de `Users/{id}`?
- ( ) latitude e longitude
- ( ) displayLatitude e displayLongitude
- ( ) geohash
- ( ) nenhum / inconsistentes

No `users_preview/{id}`, existe:
- ( ) geohash
- ( ) gridId
- ( ) lat/lng
- ( ) não existe/está desatualizado

## 2) Consistência geohash ↔ lat/lng (teste que mata dúvida)

Pegue 1 evento real e responda:

- geohash do topo (ou `location.geohash`) começa com o prefixo esperado da região? (sim/não)
- Decodificando geohash, ele cai perto de lat/lng do doc? (sim/não)
- Existe chance de lat/lng invertidos em algum writer? (sim/não/não sei)
- O geohash está sempre em precisão 7 no banco?
  - ( ) sim
  - ( ) não (varia)
  - ( ) não sei
- Os “cells” que o app consulta (ex.: `6vhb`, `75cn`) batem com o prefixo do doc real?
  - ( ) sim
  - ( ) não
  - ( ) ainda não comparei

**Se “não bate”:** ou o geohash foi gerado com lat/lng errados, ou o app está consultando um campo diferente do que o banco tem.

## 3) Leitura no app (parser/fallback) — onde o bug costuma morar

### Events (crítico)

O `EventLocation.fromFirestore` (ou equivalente) lê:
- ( ) só location.latitude/longitude
- ( ) só topo latitude/longitude
- ( ) ambos com fallback

Se `location.latitude/longitude` vier null, o que acontece?
- ( ) vira 0.0/0.0
- ( ) retorna null e descarta o evento
- ( ) cai no fallback do topo
- ( ) não sei

Hoje o app renderiza marker usando qual fonte?
- ( ) event.latitude/event.longitude (topo do model)
- ( ) event.location.latitude/event.location.longitude
- ( ) outro caminho

Existe algum lugar que “normaliza” os eventos antes do render (ex.: sanitizeEventLocation)?
- ( ) sim (onde?)
- ( ) não

**Sinal de bug:** doc tem geohash ok, mas latitude=null longitude=null no topo e o sistema descarta por bounds.

### Users

O parser do user usa:
- ( ) topo latitude/longitude
- ( ) displayLatitude/displayLongitude
- ( ) outro

O mapa de people usa a mesma lógica de bounds/kept do events?
- ( ) sim
- ( ) não (tem pipeline diferente)

## 4) Filtros pós-fetch que podem zerar tudo (mesmo com dados)

### Events

Seu filtro de evento “válido” exige:
- ( ) status == active
- ( ) isActive == true
- ( ) status == active OR isActive == true
- ( ) ambos coerentes

Existem eventos com:
- status=inactive e isActive=true? (sim/não)
- status=active e isActive=false? (sim/não)
- status preenchido com valores diferentes (enabled, published, etc.)? (sim/não)

O filtro por bounds usa:
- ( ) lat/lng do topo
- ( ) lat/lng de location
- ( ) o mesmo que o render usa

Existe algum filtro de “expirado” que descarta antes de render?
- ( ) sim (qual campo?)
- ( ) não

## 5) Escrita “em dois lugares” (onde a migração quebra silenciosamente)

Na criação de evento, vocês gravam:
- ( ) location.latitude/longitude e topo latitude/longitude
- ( ) só location.latitude/longitude
- ( ) só topo latitude/longitude

Na atualização de endereço/place do evento, vocês sobrescrevem `location` inteiro?
- ( ) sim (pode estar apagando lat/lng do topo ou do location)
- ( ) não

Na Cloud Function, vocês fazem `set(..., {merge:true})` ou `set` sem merge?
- ( ) merge
- ( ) sem merge
- ( ) não sei

**Bug clássico:** writer salva `location` completo e apaga campos irmãos sem querer, ou salva topo e não salva `location`, ou vice-versa.

## 6) Sincronização Users (preview/grid) — o “segundo” bug possível

`usersGridSync` depende de qual origem?
- ( ) topo latitude/longitude
- ( ) displayLatitude/displayLongitude
- ( ) geohash já pronto

`users_preview` é atualizado:
- ( ) sempre que muda localização
- ( ) só no backfill
- ( ) só às vezes (falha/atraso)

O mapa de people lê `users_preview` ou `Users`?
- ( ) Users
- ( ) users_preview
- ( ) mistura (cache/preview + detalhe)

## 7) Prova final (mini check de 3 minutos que encerra discussão)

Escolha um `eventId` que deveria aparecer e responda (copiando do Console):

- geohash (topo) = ?
- location.geohash = ?
- latitude/longitude no topo = ?
- location.latitude/longitude = ?
- status/isActive/isCanceled = ?

Agora responda:

- O parser do app lê exatamente esses campos? (sim/não)
- O filtro por bounds usa esses mesmos campos? (sim/não)

✅ **Se qualquer resposta for “não”, achamos o ponto.**

---

## Minha leitura do seu log (pra orientar a prioridade)

Pelo padrão observado:

- Às vezes a busca encontra docs (`fetched=13`, `fetched=1`).
- Os docs vêm com latitude/longitude **no topo nulos** e coordenada preenchida dentro de `location`.
- O pipeline indica dependência de lat/lng no topo (ou model populado só pelo topo), então o “kept” termina 0.

Isso aponta para:
- ✅ **schema divergente + parser sem fallback**, ou
- ✅ **writer apagando campo (merge errado)**, ou
- ✅ **filtro por bounds usando fonte diferente do render**.
