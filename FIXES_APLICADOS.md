# 🔧 Fixes Aplicados — Bug Markers Não Carregam

> **Data**: 03/02/2026  
> **Bug**: Markers (events/users) não aparecem no mapa  
> **Status**: ✅ **FIX IMPLEMENTADO**

---

## 📋 Resumo do Bug

**Problema**: Parser `EventLocation.fromFirestore` retornava `(0.0, 0.0)` quando `location` era null, causando descarte de todos os eventos pelo filtro de bounds.

**Root Cause**: Falta de fallback para schemas legados onde coordenadas estão no topo do documento (`data.latitude/longitude`) ao invés de `location.latitude/longitude`.

**Impacto**: `fetched > 0` mas `kept = 0` — eventos buscados, mas nenhum renderizado.

---

## ✅ Fix Implementado

### 1️⃣ **Parser Robusto com Múltiplos Schemas**

**Arquivo**: [lib/features/home/data/models/event_location.dart](lib/features/home/data/models/event_location.dart)

**Mudanças**:

#### ✨ Novo Método: `tryFromFirestore()`

Suporta **4 formatos de schema**:

1. **`location` como Map** (schema atual)
   ```json
   {
     "location": {
       "latitude": -23.5505,
       "longitude": -46.6333
     }
   }
   ```

2. **`location` como GeoPoint** (Firestore nativo)
   ```json
   {
     "location": GeoPoint(-23.5505, -46.6333)
   }
   ```

3. **Topo do documento** (schema legado)
   ```json
   {
     "latitude": -23.5505,
     "longitude": -46.6333
   }
   ```

4. **Keys alternativas** (`lat/lng` ao invés de `latitude/longitude`)

#### 🛡️ Validação de Coordenadas

- ❌ Rejeita `NaN`
- ❌ Rejeita fora de range (`lat: -90~90`, `lng: -180~180`)
- ❌ Rejeita `(0.0, 0.0)` (Golfo da Guiné — provável bug)

#### 🔄 Retorno Seguro

```dart
// ✅ ANTES (bug):
factory EventLocation.fromFirestore(...) {
  return EventLocation(
    latitude: location?['latitude'] ?? 0.0,  // ⚠️ Retornava 0.0
    longitude: location?['longitude'] ?? 0.0, // ⚠️ Retornava 0.0
  );
}

// ✅ DEPOIS (fix):
static EventLocation? tryFromFirestore(...) {
  final coords = _extractLatLng(data);
  if (coords.lat == null || coords.lng == null) {
    return null; // ✅ Retorna null ao invés de inventar 0.0
  }
  if (!_isValidLatLng(coords.lat, coords.lng)) {
    return null; // ✅ Valida coordenadas
  }
  return EventLocation(...);
}
```

---

### 2️⃣ **Atualização do MapDiscoveryService**

**Arquivo**: [lib/features/home/data/services/map_discovery_service.dart](lib/features/home/data/services/map_discovery_service.dart)

**Mudanças**:

```dart
// ❌ ANTES:
final event = EventLocation.fromFirestore(doc.id, data);
if (!bounds.contains(event.latitude, event.longitude)) {
  continue; // Sempre descartava (0.0, 0.0)
}

// ✅ DEPOIS:
final event = EventLocation.tryFromFirestore(doc.id, data);
if (event == null) continue; // Pula eventos sem coordenadas válidas
if (!bounds.contains(event.latitude, event.longitude)) {
  continue;
}
```

**Impacto**:
- ✅ Eventos sem coordenadas são **descartados antes** do filtro de bounds
- ✅ Eventos com coordenadas válidas passam a renderizar
- ✅ Logs mais claros (null é mais óbvio que 0.0)

---

## 🧪 Como Testar

### 1. Verificar eventos no Firestore

```bash
# No Firebase Console
events/{eventId} → Verificar schema
```

**Schemas esperados**:

✅ **Novo** (location como Map):
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

✅ **Legado** (topo):
```json
{
  "geohash": "6gycfq7",
  "latitude": -23.5505,
  "longitude": -46.6333
}
```

✅ **GeoPoint** (alternativo):
```json
{
  "geohash": "6gycfq7",
  "location": GeoPoint(-23.5505, -46.6333)
}
```

---

### 2. Testar no app

#### Terminal:
```bash
flutter run -d 45b08856f41c61b7ae80f6855cf40dc3b5d1a6c6
```

#### Logs esperados:

**✅ ANTES DO FIX**:
```
🔍 [events] Query geohash (cells=6, precision=5)
✅ [events] fetched=13
🧾 [events] sampleDoc geohash=6gycfq7 latitude=null longitude=null
🧪 [events] kept=0  ❌ BUG
```

**✅ DEPOIS DO FIX**:
```
🔍 [events] Query geohash (cells=6, precision=5)
✅ [events] fetched=13
🧾 [events] sampleDoc geohash=6gycfq7 latitude=-23.5505 longitude=-46.6333
🧪 [events] kept=10  ✅ FIXADO
```

---

### 3. Teste de regressão

**Cenários cobertos pelo fix**:

| Schema | Antes | Depois |
|--------|-------|--------|
| `location` Map | ❌ 0.0 se null | ✅ Tenta topo |
| `location` GeoPoint | ❌ 0.0 | ✅ Extrai corretamente |
| Topo `latitude/longitude` | ❌ 0.0 | ✅ Usa como fallback |
| Sem coordenadas | ❌ Renderiza (0,0) | ✅ Retorna null |
| Coordenadas inválidas | ❌ Renderiza errado | ✅ Retorna null |

---

## 📊 Métricas Esperadas

### Antes do Fix:
- **Fetched**: 13 eventos
- **Kept**: 0 eventos (100% descartados)
- **Markers no mapa**: 0

### Depois do Fix:
- **Fetched**: 13 eventos
- **Kept**: ~10-13 eventos (dependendo de quantos têm coordenadas válidas)
- **Markers no mapa**: ~10-13

---

## 🚨 Casos de Atenção

### Se `kept` continuar 0:

1. **Verificar logs**:
   ```
   ⚠️ EventLocation: {eventId} sem lat/lng (schema=null)
   ⚠️ EventLocation: {eventId} lat/lng inválidos: 0.0,0.0
   ```

2. **Possíveis causas**:
   - Todos os eventos no Firestore **realmente** não têm coordenadas
   - Coordenadas estão em formato não suportado
   - Eventos estão fora do bounds do mapa

3. **Solução**:
   - Rodar migration para popular `location` (ver Fix #2 no diagnóstico)
   - Habilitar logs comentados no parser para debug

---

## 🔄 Backward Compatibility

### `EventLocation.fromFirestore()` ainda existe

Marcado como **@deprecated**, mas ainda funciona:

```dart
// ✅ Código antigo continua funcionando
final event = EventLocation.fromFirestore(doc.id, data);
// Internamente chama tryFromFirestore() e fallback para (0.0, 0.0) se null
```

**Migração gradual**:
- ✅ MapDiscoveryService já usa `tryFromFirestore()`
- ⚠️ Outros lugares podem continuar usando `fromFirestore()` (mas será descartado depois)

---

## 📝 Próximos Passos (Opcional)

### 1. Migration para normalizar schemas antigos

Se houver muitos eventos sem `location`, criar migration:

```typescript
// functions/src/migrations/normalizeEventLocation.ts
for (const doc of events) {
  const data = doc.data();
  
  // Migrar topo → location
  if (!data.location && data.latitude && data.longitude) {
    await doc.ref.update({
      'location.latitude': data.latitude,
      'location.longitude': data.longitude,
      'location.geohash': encodeGeohash(data.latitude, data.longitude, 7),
    });
  }
}
```

### 2. Habilitar logs para debug

Descomentar no `event_location.dart`:

```dart
if (lat == null || lng == null) {
  debugPrint('⚠️ EventLocation: $docId sem lat/lng (schema=${data['location']?.runtimeType})');
  return null;
}
```

---

## ✅ Checklist de Validação

- [x] Parser suporta múltiplos schemas (Map, GeoPoint, topo)
- [x] Valida coordenadas (range, NaN, 0.0)
- [x] Retorna null ao invés de inventar 0.0
- [x] MapDiscoveryService usa tryFromFirestore()
- [x] Fallback query atualizado
- [x] Sem erros de análise estática
- [ ] Testado no device real
- [ ] Logs confirmam kept > 0
- [ ] Markers aparecem no mapa

---

**Arquivo gerado em**: 03/02/2026  
**Implementado por**: GitHub Copilot (Claude Sonnet 4.5)  
**Baseado em**: [DIAGNOSTICO_BUG_MARKERS_NAO_CARREGAM.md](DIAGNOSTICO_BUG_MARKERS_NAO_CARREGAM.md)
