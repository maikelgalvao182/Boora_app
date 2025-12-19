# 🚨 Correção Crítica: Validação de Coordenadas no Sistema de Offset

## 📋 Problema Identificado

### Sintomas
Valores de `displayLatitude` e `displayLongitude` estavam sendo gerados com valores absurdos:

```
❌ VALORES INCORRETOS:
displayLatitude  = -1557860
displayLongitude = -47196748

✅ VALORES ESPERADOS (para Uberlândia):
displayLatitude  ≈ -18.924xxx
displayLongitude ≈ -48.253xxx
```

### Causa Raiz

Os valores gerados estão típicos de **coordenadas projetadas Web Mercator (EPSG:3857)** em metros, não latitude/longitude em graus.

**Regras violadas:**
- Latitude válida: `-90` a `+90` graus
- Longitude válida: `-180` a `+180` graus

**Diagnóstico:**
Em algum ponto do fluxo, coordenadas em graus estavam sendo confundidas ou misturadas com coordenadas projetadas (metros).

---

## 🔍 Análise da Arquitetura Atual

### ✅ Algoritmo de Offset (CORRETO)

O algoritmo em si está matematicamente correto:

**Dart:** `/lib/core/utils/location_offset_helper.dart`
**TypeScript:** `/functions/src/utils/locationOffset.ts`

```dart
// Calcula offset entre 300m e 1500m
final offsetMeters = 300 + (random × 1200);
final offsetKm = offsetMeters / 1000;

// Converte para graus
final latOffset = (offsetKm / 6371) × (180 / π);
final lngOffset = (offsetKm / 6371) × (180 / π) / cos(realLat × π/180);

// Aplica offset em direção aleatória
final displayLat = realLat + (latOffset × cos(angle));
final displayLng = realLng + (lngOffset × sin(angle));
```

### ✅ Fonte de Coordenadas (CORRETA)

O app obtém coordenadas via `Geolocator.getCurrentPosition()`:

```dart
// LocationService retorna Position do Geolocator
final position = await Geolocator.getCurrentPosition(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
  ),
);

// Position.latitude e Position.longitude SÃO em graus
```

### ⚠️ Problema Identificado

**Não há conversão Web Mercator no fluxo de salvamento de localização do usuário.**

A conversão Web Mercator existe apenas em:
- `marker_cluster_service.dart` - para clustering de **eventos** no mapa
- Nunca deveria afetar coordenadas do **usuário**

---

## 🛠️ Correções Implementadas

### 1. Validação Pré-Cálculo (Dart)

**Arquivo:** `lib/features/location/presentation/viewmodels/update_location_view_model.dart`

```dart
// 🚨 VALIDAÇÃO PRÉ-OFFSET: Garantir que valores são lat/lng válidos
if (latitude < -90 || latitude > 90) {
  throw Exception(
    'Latitude inválida: $latitude. '
    'Deve estar entre -90 e +90. '
    'Possível bug: coordenada projetada sendo usada como latitude.'
  );
}

if (longitude < -180 || longitude > 180) {
  throw Exception(
    'Longitude inválida: $longitude. '
    'Deve estar entre -180 e +180. '
    'Possível bug: coordenada projetada sendo usada como longitude.'
  );
}

AppLogger.info('✅ Validação de coordenadas passou:', tag: 'UpdateLocationVM');
AppLogger.info('   Latitude: $latitude (válida)', tag: 'UpdateLocationVM');
AppLogger.info('   Longitude: $longitude (válida)', tag: 'UpdateLocationVM');
```

### 2. Validação no Helper de Offset (Dart)

**Arquivo:** `lib/core/utils/location_offset_helper.dart`

```dart
static Map<String, double> generateDisplayLocation({
  required double realLat,
  required double realLng,
  required String userId,
}) {
  // 🚨 VALIDAÇÃO ENTRADA
  if (realLat < -90 || realLat > 90) {
    throw ArgumentError(
      '🚨 ERRO CRÍTICO: Latitude inválida: $realLat\n'
      'Latitude deve estar entre -90 e +90 graus.\n'
      'Valor recebido parece ser coordenada projetada (Web Mercator), '
      'não latitude em graus.',
    );
  }
  
  if (realLng < -180 || realLng > 180) {
    throw ArgumentError(
      '🚨 ERRO CRÍTICO: Longitude inválida: $realLng\n'
      'Longitude deve estar entre -180 e +180 graus.\n'
      'Valor recebido parece ser coordenada projetada (Web Mercator), '
      'não longitude em graus.',
    );
  }
  
  // ... cálculo do offset ...
  
  // 🚨 VALIDAÇÃO SAÍDA
  if (displayLatitude < -90 || displayLatitude > 90) {
    throw StateError(
      '🚨 BUG NO ALGORITMO: displayLatitude calculada está fora do range: '
      '$displayLatitude\n'
      'Input: realLat=$realLat, realLng=$realLng\n'
      'Isso indica um bug no cálculo do offset.',
    );
  }
  
  if (displayLongitude < -180 || displayLongitude > 180) {
    throw StateError(
      '🚨 BUG NO ALGORITMO: displayLongitude calculada está fora do range: '
      '$displayLongitude\n'
      'Input: realLat=$realLat, realLng=$realLng\n'
      'Isso indica um bug no cálculo do offset.',
    );
  }
  
  return {
    'displayLatitude': displayLatitude,
    'displayLongitude': displayLongitude,
  };
}
```

### 3. Validação no Backend (TypeScript)

**Arquivo:** `functions/src/utils/locationOffset.ts`

```typescript
export function generateDisplayLocation(
  realLat: number,
  realLng: number,
  userId: string
): { displayLatitude: number; displayLongitude: number } {
  // 🚨 VALIDAÇÃO ENTRADA
  if (realLat < -90 || realLat > 90) {
    throw new Error(
      `🚨 ERRO CRÍTICO: Latitude inválida: ${realLat}\n` +
      `Latitude deve estar entre -90 e +90 graus.\n` +
      `Valor recebido parece ser coordenada projetada (Web Mercator), ` +
      `não latitude em graus.`
    );
  }

  if (realLng < -180 || realLng > 180) {
    throw new Error(
      `🚨 ERRO CRÍTICO: Longitude inválida: ${realLng}\n` +
      `Longitude deve estar entre -180 e +180 graus.\n` +
      `Valor recebido parece ser coordenada projetada (Web Mercator), ` +
      `não longitude em graus.`
    );
  }

  if (!userId || userId.trim().length === 0) {
    throw new Error("userId não pode ser vazio");
  }
  
  // ... cálculo do offset ...
  
  // 🚨 VALIDAÇÃO SAÍDA
  if (displayLatitude < -90 || displayLatitude > 90) {
    throw new Error(
      `🚨 BUG NO ALGORITMO: displayLatitude calculada está fora ` +
      `do range: ${displayLatitude}\n` +
      `Input: realLat=${realLat}, realLng=${realLng}\n` +
      `Isso indica um bug no cálculo do offset.`
    );
  }

  if (displayLongitude < -180 || displayLongitude > 180) {
    throw new Error(
      `🚨 BUG NO ALGORITMO: displayLongitude calculada está fora ` +
      `do range: ${displayLongitude}\n` +
      `Input: realLat=${realLat}, realLng=${realLng}\n` +
      `Isso indica um bug no cálculo do offset.`
    );
  }
  
  return { displayLatitude, displayLongitude };
}
```

---

## 🔍 Como Testar

### 1. Teste Manual no App

1. Execute o app: `flutter run`
2. Vá para a tela de atualização de localização
3. Toque em "Obter Localização Atual"
4. **Observe os logs:**

```
✅ LOGS ESPERADOS:
[UpdateLocationVM] ✅ Validação de coordenadas passou:
[UpdateLocationVM]    Latitude: -18.933167 (válida)
[UpdateLocationVM]    Longitude: -48.265507 (válida)
[UpdateLocationVM] 🔒 Generated display offset:
[UpdateLocationVM]    Real: (-18.933167, -48.265507)
[UpdateLocationVM]    Display: (-18.924xxx, -48.253xxx)

❌ LOGS DE ERRO (se houver bug):
[UpdateLocationVM] ❌ Error: Latitude inválida: -1557860.0
```

### 2. Teste de Unidade

Crie um teste em `test/core/utils/location_offset_helper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:partiu/core/utils/location_offset_helper.dart';

void main() {
  group('LocationOffsetHelper Validations', () {
    test('Deve rejeitar latitude fora do range', () {
      expect(
        () => LocationOffsetHelper.generateDisplayLocation(
          realLat: -1557860.0, // ❌ Inválido
          realLng: -48.265507,
          userId: 'test-user-id',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Deve rejeitar longitude fora do range', () {
      expect(
        () => LocationOffsetHelper.generateDisplayLocation(
          realLat: -18.933167,
          realLng: -47196748.0, // ❌ Inválido
          userId: 'test-user-id',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Deve aceitar coordenadas válidas', () {
      final result = LocationOffsetHelper.generateDisplayLocation(
        realLat: -18.933167,
        realLng: -48.265507,
        userId: 'test-user-id',
      );
      
      expect(result['displayLatitude'], isNotNull);
      expect(result['displayLongitude'], isNotNull);
      
      // Verificar ranges
      expect(result['displayLatitude']!, inInclusiveRange(-90, 90));
      expect(result['displayLongitude']!, inInclusiveRange(-180, 180));
      
      // Verificar que offset não é muito grande (máx 1.5km ≈ 0.014°)
      final latDiff = (result['displayLatitude']! - (-18.933167)).abs();
      final lngDiff = (result['displayLongitude']! - (-48.265507)).abs();
      
      expect(latDiff, lessThan(0.02));
      expect(lngDiff, lessThan(0.02));
    });
  });
}
```

### 3. Verificar Firestore

Após salvar localização, verificar no console do Firebase:

```javascript
// Todos os valores devem estar no range correto
{
  latitude: -18.933167,         // ✅ Entre -90 e +90
  longitude: -48.265507,        // ✅ Entre -180 e +180
  displayLatitude: -18.924xxx,  // ✅ Entre -90 e +90
  displayLongitude: -48.253xxx, // ✅ Entre -180 e +180
}
```

---

## 🎯 Próximos Passos

### Imediato
- [x] Adicionar validações pré e pós-cálculo
- [x] Adicionar logs de diagnóstico
- [ ] Testar em ambiente real com GPS
- [ ] Verificar dados já salvos no Firestore

### Arquitetural (Recomendado)

**Problema atual:**
- Client (app) gera `displayLatitude` e `displayLongitude`
- Backend confia cegamente nos valores

**Solução ideal:**
```
📱 App → envia apenas realLat/realLng
🔐 Backend → calcula displayLat/displayLng (Cloud Function)
💾 Firestore → salva ambos
```

**Vantagens:**
- Offset controlado pelo backend (mais seguro)
- Client não pode manipular offset
- Lógica centralizada
- Mais fácil de auditar/debug

---

## 📊 Checklist de Validação

- [x] Validação de entrada no helper Dart
- [x] Validação de saída no helper Dart
- [x] Validação de entrada no backend TypeScript
- [x] Validação de saída no backend TypeScript
- [x] Validação pré-cálculo no ViewModel
- [x] Logs de diagnóstico adicionados
- [ ] Testes unitários criados
- [ ] Testado com GPS real em dispositivo físico
- [ ] Dados antigos no Firestore verificados/limpos

---

## 🐛 Como Investigar se o Bug Persistir

Se após as validações você ainda ver valores absurdos nos logs:

### 1. Verificar logs do Geolocator

Adicione este log no `LocationService`:

```dart
final position = await Geolocator.getCurrentPosition(...);

print('🔍 DEBUG Geolocator:');
print('   Type: ${position.runtimeType}');
print('   Latitude: ${position.latitude} (${position.latitude.runtimeType})');
print('   Longitude: ${position.longitude} (${position.longitude.runtimeType})');
```

### 2. Verificar se há override em Position

Busque por extensões ou overrides:

```bash
grep -r "extension.*Position" lib/
grep -r "class.*Position.*extends" lib/
```

### 3. Verificar packages conflitantes

Em `pubspec.yaml`, verificar se há múltiplas versões de:
- `geolocator`
- `google_maps_flutter`
- `apple_maps_flutter`

---

## 📚 Referências

- [WGS84 Coordinate System](https://en.wikipedia.org/wiki/World_Geodetic_System)
- [Web Mercator Projection (EPSG:3857)](https://en.wikipedia.org/wiki/Web_Mercator_projection)
- [Geolocator Package](https://pub.dev/packages/geolocator)

---

**Data:** 19 de dezembro de 2025  
**Status:** ✅ Validações implementadas, aguardando teste em ambiente real
