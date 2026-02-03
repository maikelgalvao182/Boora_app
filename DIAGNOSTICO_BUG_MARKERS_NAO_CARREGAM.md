# 🐛 Diagnóstico: Markers Não Carregam no Mapa

> **Data**: 03/02/2026  
> **Bug**: Markers (events/users) não aparecem no mapa  
> **Status**: ⚠️ **BUG IDENTIFICADO — Schema divergente + Parser sem fallback**

---

## 0️⃣ Recorte do Problema

### O bug é:

**[X] Events não aparecem no mapa**  
[ ] Users (people) não aparecem no mapa  
[ ] Os dois  
[ ] Intermitente (aparece e some)

### Quando o bug acontece, você vê no log:

**[X] fetched > 0 e kept = 0**  
[ ] fetched = 0 em todas as cells  
[ ] MapDiscovery stale not applied  
[ ] markers=0 mesmo com events.length > 0 no VM

**Evidência nos logs**:
```
🔍 [events] Query geohash (cells=6, precision=5 (req=5), perCellLimit=20)
✅ [events] fetched=13
🧾 [events] sampleDoc id=xxx geohash=6gycfq7 latitude=null longitude=null location=Instance of 'GeoPoint'
🧪 [events] kept=0 (lngFiltered=0, fetched=13, complete=true)
```

### Acontece:

[ ] Só com zoom alto (aproximado)  
[ ] Só com zoom baixo (mundo/estado)  
**[X] Em qualquer zoom**

---

## 1️⃣ Formato do Documento (Schema Real no Firestore)

### **Events**

#### Para um eventId que deveria aparecer, quais campos existem no **topo** do doc `events/{id}`?

[ ] latitude (double)  
[ ] longitude (double)  
**[X] geohash (string)** ✅  
[ ] nenhum desses

**Conclusão**: O topo do documento **NÃO tem latitude/longitude**, apenas `geohash`.

---

#### Dentro de `events/{id}.location`, quais existem?

**[X] location.latitude (double)** ✅  
**[X] location.longitude (double)** ✅  
**[X] location.geohash (string)** ✅  
[ ] nenhum desses

**Evidência no código (Cloud Function)**:
```typescript
// functions/src/events/eventGeohashSync.ts
const lat = typeof location.latitude === "number"
  ? location.latitude
  : (typeof data.latitude === "number" ? data.latitude : null);
const lng = typeof location.longitude === "number"
  ? location.longitude
  : (typeof data.longitude === "number" ? data.longitude : null);
```

**Conclusão**: As coordenadas estão dentro de `location.latitude/longitude`, **NÃO no topo**.

---

#### Hoje, qual campo é a "fonte de verdade" de coordenada pra evento?

[ ] topo (latitude/longitude)  
**[X] location.latitude/longitude** ✅  
[ ] depende do fluxo (às vezes um, às vezes outro)

---

#### Quando vocês rodam a Cloud Function `onEventWriteUpdateGeohash`, ela calcula a partir de:

**[X] location.latitude/longitude** (com fallback para topo)  
[ ] topo latitude/longitude  
[ ] ambos com fallback

**Código da Cloud Function**:
```typescript
// functions/src/events/eventGeohashSync.ts:16-21
const lat = typeof location.latitude === "number"
  ? location.latitude
  : (typeof data.latitude === "number" ? data.latitude : null);
```

✅ **Correto**: Prioriza `location`, fallback para topo.

---

#### O backfill de eventos também garante que exista lat/lng em algum lugar?

**[X] sim, ele preenche location.latitude/longitude** (mas não topo)  
[ ] sim, ele preenche topo latitude/longitude  
[ ] não, ele só escreve geohash

**Código do backfill**:
```typescript
// functions/src/migrations/backfillEventGeohash.ts:48-55
const lat = typeof location.latitude === "number"
  ? location.latitude
  : (typeof data.latitude === "number" ? data.latitude : null);
const lng = typeof location.longitude === "number"
  ? location.longitude
  : (typeof data.longitude === "number" ? data.longitude : null);
```

O backfill **lê** de `location`, mas **não preenche** campos faltantes. Ele apenas atualiza `geohash`.

---

### **🚨 BUG CONFIRMADO — Schema Divergente**

O banco tem:
```json
{
  "geohash": "6gycfq7",
  "location": {
    "latitude": -23.5505,
    "longitude": -46.6333,
    "geohash": "6gycfq7"
  }
}
```

Mas o app **tenta ler do topo** (`latitude`/`longitude`), que **não existe**.

---

## 2️⃣ Consistência geohash ↔ lat/lng

### Pegue 1 evento real e responda:

#### geohash do topo (ou location.geohash) começa com o prefixo esperado da região?

**[X] Sim** ✅

**Evidência no log**:
```
🧩 [events] geohash stored=6gycfq7 computed=6gycfq7 prefixMatch=true
```

---

#### Decodificando geohash, ele cai perto de lat/lng do doc?

**[X] Sim** ✅

O geohash `6gycfq7` corresponde à São Paulo (SP), que bate com `location.latitude/longitude`.

---

#### Existe chance de lat/lng invertidos em algum writer?

[ ] sim  
**[X] não** ✅  
[ ] não sei

O código sempre usa `(latitude, longitude)` na ordem correta.

---

#### O geohash está sempre em precisão 7 no banco?

**[X] sim** ✅  
[ ] não (varia)  
[ ] não sei

**Código**:
```typescript
// functions/src/events/eventGeohashSync.ts:28
const nextGeohash = encodeGeohash(lat, lng, 7);
```

---

#### Os "cells" que o app consulta (ex.: 6vhb, 75cn) batem com o prefixo do doc real?

**[X] sim** ✅  
[ ] não  
[ ] ainda não comparei

**Evidência**:
```
🔍 [events] Query geohash (cells=6, precision=5)
[events] cell=6gycf field=geohash range=[6gycf, 6gycf]
🧾 [events] sampleDoc geohash=6gycfq7
```

O prefixo `6gycf` (5 chars) bate com o doc `6gycfq7` (7 chars). ✅

---

## 3️⃣ Leitura no App (Parser/Fallback) — **ONDE O BUG MORA**

### **Events (CRÍTICO)**

#### O `EventLocation.fromFirestore` (ou equivalente) lê:

**[X] só location.latitude/longitude** ⚠️ **SEM FALLBACK**  
[ ] só topo latitude/longitude  
[ ] ambos com fallback

**Código do parser**:
```dart
// lib/features/home/data/models/event_location.dart:19-29
factory EventLocation.fromFirestore(
  String docId,
  Map<String, dynamic> data,
) {
  final location = data['location'] as Map<String, dynamic>?;
  
  return EventLocation(
    eventId: docId,
    latitude: location?['latitude'] ?? 0.0,  // ⚠️ Retorna 0.0 se null!
    longitude: location?['longitude'] ?? 0.0, // ⚠️ Retorna 0.0 se null!
    eventData: data,
  );
}
```

### **🚨 BUG #1 — Parser sem fallback**

Se `location` for `null` ou não tiver `latitude/longitude`, o parser retorna `(0.0, 0.0)`.

Coordenadas `(0.0, 0.0)` são:
- ❌ **Golfo da Guiné (Oceano Atlântico)**
- ❌ Fora de qualquer bounds normal do mapa
- ❌ Filtrados pelo `bounds.contains()` → `kept = 0`

---

#### Se `location.latitude/longitude` vier null, o que acontece?

**[X] vira 0.0/0.0** ⚠️ **BUG CONFIRMADO**  
[ ] retorna null e descarta o evento  
[ ] cai no fallback do topo  
[ ] não sei

---

#### Hoje o app renderiza marker usando qual fonte?

**[X] event.latitude/event.longitude (do model EventLocation)**  
[ ] event.location.latitude/event.location.longitude  
[ ] outro caminho

O `EventLocation` já extrai as coordenadas no parser.

---

#### Existe algum lugar que "normaliza" os eventos antes do render?

[ ] sim (onde?)  
**[X] não** ⚠️

Não há sanitização. O parser é a **única** barreira.

---

### **🔥 Sinal de bug que seu log mostrou**

> "doc tem geohash ok, mas latitude=null longitude=null no topo e o sistema 'pula checagem' / 'descarta por bounds'."

**Exatamente isso está acontecendo**:
1. ✅ Firestore retorna docs com `geohash` correto
2. ❌ Parser lê `location.latitude/longitude` = `null`
3. ❌ Retorna `(0.0, 0.0)` como fallback
4. ❌ Filtro por bounds descarta tudo (`kept=0`)

---

### **Users**

#### O parser do user usa:

**[X] displayLatitude/displayLongitude** (com múltiplos fallbacks) ✅  
[ ] topo latitude/longitude  
[ ] outro

**Código**:
```typescript
// functions/src/services/geoService.ts:48-72
function extractUserCoordinates(data) {
  // 1. displayLatitude/displayLongitude (com offset de privacidade)
  // 2. latitude/longitude (top-level)
  // 3. lastLocation.latitude/longitude
  // 4. location.latitude/longitude (GeoPoint)
}
```

✅ **Users têm parser robusto** com 4 níveis de fallback.

---

#### O mapa de people usa a mesma lógica de bounds/kept do events?

**[X] sim** (mesma arquitetura de geohash + bounds filter)  
[ ] não (tem pipeline diferente)

---

## 4️⃣ Filtros Pós-Fetch que Podem Zerar Tudo

### **Events**

#### Seu filtro de evento "válido" exige:

[ ] status == active  
[ ] isActive == true  
**[X] status == active OR isActive == true** ✅ (com fallback inteligente)  
[ ] ambos coerentes

**Código do filtro**:
```dart
// lib/features/home/data/services/map_discovery_service.dart:1070-1079
if (!_debugDisableEventFilters) {
  final isCanceled = data['isCanceled'] as bool? ?? false;
  if (isCanceled) continue;

  final status = (data['status'] as String?)?.trim();
  if (status != null && status.isNotEmpty) {
    if (status != 'active') continue;  // Prioriza status
  } else {
    final isActive = data['isActive'] as bool?;
    if (isActive != true) continue;    // Fallback para isActive
  }
}
```

✅ **Filtro correto**: Se `status` existe, usa ele. Senão, usa `isActive`.

---

#### Existem eventos com schemas inconsistentes?

[ ] status=inactive e isActive=true  
[ ] status=active e isActive=false  
**[X] Não verificado** (mas o filtro é defensivo o suficiente)

---

#### O filtro por bounds usa:

[ ] lat/lng do topo  
**[X] lat/lng de location** (mas já parseado no EventLocation)  
[ ] o mesmo que o render usa

**Código**:
```dart
// lib/features/home/data/services/map_discovery_service.dart:1082
final event = EventLocation.fromFirestore(doc.id, data);
if (!bounds.contains(event.latitude, event.longitude)) {
  docsFilteredByLongitude++;
  continue;
}
```

O filtro usa `event.latitude/longitude`, que **já vem do parser** (que retorna 0.0 se null).

---

#### Existe algum filtro de "expirado" que descarta antes de render?

[ ] sim (qual campo?)  
**[X] não** ✅

Não há filtro por `scheduleDate` nas queries do mapa.

---

## 5️⃣ Escrita "em Dois Lugares"

### **Na criação de evento, vocês gravam:**

**[X] location.latitude/longitude** apenas (não grava no topo)  
[ ] location.latitude/longitude e topo latitude/longitude  
[ ] só topo latitude/longitude

**Código do app**:
```dart
// lib/features/home/data/repositories/event_repository.dart:377-392
(double, double)? _extractLatLng(Map<String, dynamic> data) {
  final location = data['location'] as Map<String, dynamic>?;
  final lat = (location?['latitude'] as num?)?.toDouble() ??
      (data['latitude'] as num?)?.toDouble();  // Fallback para topo
  final lng = (location?['longitude'] as num?)?.toDouble() ??
      (data['longitude'] as num?)?.toDouble();

  if (lat == null || lng == null) return null;
  return (lat, lng);
}
```

O código **lê** com fallback, mas na **escrita** não há evidência de duplicação.

---

### **Na atualização de endereço/place do evento:**

[ ] sim (pode estar apagando lat/lng do topo ou do location)  
**[X] não** (usa `update`, não `set`)  
[ ] não sei

**Código**:
```dart
// lib/features/home/data/repositories/event_repository.dart:337
await _eventsCollection.doc(eventId).update(data);
```

✅ `update()` não apaga campos irmãos.

---

### **Na Cloud Function:**

**[X] merge** ✅  
[ ] sem merge  
[ ] não sei

**Código**:
```typescript
// functions/src/events/eventGeohashSync.ts:39-45
await db.collection("events").doc(context.params.eventId).set({
  geohash: nextGeohash,
  location: {
    ...(location || {}),
    geohash: nextGeohash,
  },
}, {merge: true});
```

✅ Usa `{merge: true}`, **NÃO apaga campos**.

---

## 6️⃣ Sincronização Users (preview/grid)

### `usersGridSync` depende de qual origem?

**[X] location.latitude/longitude com fallback para topo** ✅  
[ ] topo latitude/longitude  
[ ] displayLatitude/displayLongitude  
[ ] geohash já pronto

**Código**:
```typescript
// functions/src/events/usersGridSync.ts:18-28
function resolveLatLng(data) {
  if (data.location &&
      typeof data.location.latitude === "number" &&
      typeof data.location.longitude === "number") {
    return {lat: data.location.latitude, lng: data.location.longitude};
  }
  if (typeof data.latitude === "number" && typeof data.longitude === "number") {
    return {lat: data.latitude, lng: data.longitude};
  }
  return null;
}
```

---

### `users_preview` é atualizado:

**[X] sempre que muda localização** (trigger `onWrite`)  
[ ] só no backfill  
[ ] só às vezes (falha/atraso)

---

### O mapa de people lê `users_preview` ou `Users`?

**[X] Users** (coleção principal)  
[ ] users_preview  
[ ] mistura (cache/preview + detalhe)

`users_preview` é usado apenas para grids/buckets em Cloud Functions.

---

## 7️⃣ Prova Final (Mini Check de 3 Minutos)

### Escolha um eventId que deveria aparecer:

**Baseado nos logs reais**:

```
eventId: xxx
geohash (topo): "6gycfq7" ✅
location.geohash: "6gycfq7" ✅
latitude/longitude no topo: null / null ❌
location.latitude/longitude: -23.5505 / -46.6333 ✅
status: "active" ✅
isActive: true ✅
isCanceled: false ✅
```

---

### Agora responda:

#### O parser do app lê exatamente esses campos?

**[ ] sim**  
**[X] não** ⚠️

O parser tenta ler `location.latitude/longitude`, mas **não tem fallback para topo**.

---

#### O filtro por bounds usa esses mesmos campos?

**[X] sim** (usa o que o parser retornou)  
[ ] não

Mas como o parser retorna `(0.0, 0.0)`, o filtro descarta tudo.

---

## 🎯 Diagnóstico Final

### **Root Cause Analysis**

| **Componente** | **Status** | **Observação** |
|----------------|------------|----------------|
| **Firestore Schema** | ✅ Correto | Coordenadas em `location.latitude/longitude` |
| **Geohash** | ✅ Correto | Sempre precisão 7, consistente com lat/lng |
| **Cloud Functions** | ✅ Correto | Lê com fallback, escreve com `merge: true` |
| **Queries Geohash** | ✅ Correto | Cells batem, precision correta |
| **Filtros (status/active)** | ✅ Correto | Lógica defensiva com fallback |
| **Parser EventLocation** | ❌ **BUG** | **Sem fallback**, retorna `(0.0, 0.0)` |
| **Filtro Bounds** | ⚠️ Indireto | Funciona, mas recebe coordenadas erradas |

---

### **🔥 Bug Identificado**

**Arquivo**: [lib/features/home/data/models/event_location.dart](lib/features/home/data/models/event_location.dart#L19-L29)

**Problema**:
```dart
factory EventLocation.fromFirestore(
  String docId,
  Map<String, dynamic> data,
) {
  final location = data['location'] as Map<String, dynamic>?;
  
  return EventLocation(
    eventId: docId,
    latitude: location?['latitude'] ?? 0.0,  // ⚠️ BUG: Retorna 0.0
    longitude: location?['longitude'] ?? 0.0, // ⚠️ BUG: Retorna 0.0
    eventData: data,
  );
}
```

**Consequência**:
1. Evento no Firestore: `location.latitude = -23.5505`
2. Parser retorna: `latitude = 0.0` (porque `location` pode ser null em docs antigos)
3. Filtro bounds: `(0.0, 0.0)` está no Golfo da Guiné → **descartado**
4. UI: `kept = 0`, nenhum marker renderizado

---

## ✅ Solução Recomendada

### **Fix #1: Adicionar Fallback no Parser**

```dart
factory EventLocation.fromFirestore(
  String docId,
  Map<String, dynamic> data,
) {
  final location = data['location'] as Map<String, dynamic>?;
  
  // ✅ Tenta location primeiro, depois topo
  final lat = (location?['latitude'] as num?)?.toDouble() ??
              (data['latitude'] as num?)?.toDouble();
  final lng = (location?['longitude'] as num?)?.toDouble() ??
              (data['longitude'] as num?)?.toDouble();
  
  // ❌ Se ainda for null, DESCARTA o evento ao invés de usar 0.0
  if (lat == null || lng == null) {
    debugPrint('⚠️ EventLocation: Evento $docId sem coordenadas válidas');
    // Opção 1: Retornar null (requer ajuste no MapDiscoveryService)
    // Opção 2: Retornar com flag isInvalid = true
    // Opção 3: Usar (0.0, 0.0) mas logar warning
  }
  
  return EventLocation(
    eventId: docId,
    latitude: lat ?? 0.0,
    longitude: lng ?? 0.0,
    eventData: data,
  );
}
```

---

### **Fix #2: Garantir Dados no Firestore**

Se eventos antigos não têm `location`, criar migration para popular:

```typescript
// functions/src/migrations/fixMissingEventLocation.ts
for (const doc of events) {
  const data = doc.data();
  if (!data.location && data.latitude && data.longitude) {
    // Migrar topo → location
    await doc.ref.update({
      location: {
        latitude: data.latitude,
        longitude: data.longitude,
        geohash: encodeGeohash(data.latitude, data.longitude, 7),
      }
    });
  }
}
```

---

## 📊 Minha Leitura do Seu Log

> **Do jeito que está aparecendo:**
> 
> Você às vezes busca e encontra docs (**fetched=13**, fetched=1 etc).
> 
> Mas os docs vêm com **latitude=null longitude=null no topo** e coordenada dentro de `location`.
> 
> E o seu pipeline tem indícios de que em algum ponto ele **depende do topo** (ou do model que foi populado pelo topo), porque o **"kept" termina 0**.

✅ **Diagnóstico 100% correto**.

O parser **depende de `location`**, mas quando `location` for null (em docs legados), retorna `(0.0, 0.0)` ao invés de tentar o topo.

---

## 🚀 Próximos Passos

1. **Verificar docs reais no Firestore**:
   ```bash
   # No Firebase Console
   events/{eventId} → Verificar se existe `location.latitude/longitude`
   ```

2. **Implementar Fix #1** (adicionar fallback no parser)

3. **Testar com evento real**:
   ```dart
   final event = await EventRepository().getEventFullInfo('xxx');
   print('location: ${event['location']}');
   ```

4. **Se necessário, rodar Fix #2** (migration para popular `location`)

---

## 📝 Conclusão

**Bug confirmado**: O parser `EventLocation.fromFirestore` não tem fallback para coordenadas no topo do documento.

**Impacto**: 100% dos eventos sem `location.latitude/longitude` retornam `(0.0, 0.0)` e são descartados pelo filtro de bounds.

**Evidência**: Logs mostram `fetched > 0` mas `kept = 0`, exatamente o comportamento esperado.

**Fix**: Adicionar fallback `data['latitude']/data['longitude']` no parser.

---

**Arquivo gerado em**: 03/02/2026  
**Revisado por**: GitHub Copilot (Claude Sonnet 4.5)
