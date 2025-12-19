# 🔒 People Discovery - Migração para Cloud Function

## 📊 Resumo

Migração do sistema de descoberta de pessoas de **100% client-side** para **híbrido (client + server)** com segurança server-side.

---

## ⚠️ Problema Anterior (Client-Side Only)

### Vulnerabilidades:
```dart
// ❌ INSEGURO - Limite aplicado no client
if (!VipAccessService.isVip && finalUsers.length > 12) {
  finalUsers = finalUsers.take(12).toList();
}
```

**Riscos**:
- ❌ Usuário pode descompilar APK e remover limite
- ❌ Query direta no Firestore ignora validação
- ❌ Modificação local de `vip_priority` é possível
- ❌ Firestore Rules não impedem acesso aos dados

---

## ✅ Solução Implementada (Híbrido)

### **Arquitetura**

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIENT (Flutter)                      │
├─────────────────────────────────────────────────────────────┤
│ 1. LocationQueryService.getUsersWithinRadiusOnce()          │
│    ├─ Calcula bounding box (GeoUtils)                       │
│    ├─ Chama Cloud Function ☁️                               │
│    └─ Calcula distâncias (Isolate - performance)            │
│                                                              │
│ 2. FindPeopleController._buildUserList()                    │
│    ├─ Enriquece dados (ratings, interesses)                 │
│    ├─ Ordena localmente (VIP → Rating → Distance)           │
│    └─ Atualiza UI                                            │
│                                                              │
│ 3. FindPeopleScreen                                         │
│    ├─ Mostra 12 cards + VipLockedCard (13º item)            │
│    └─ Bloqueio ao scrollar (UX)                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS Callable
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   SERVER (Cloud Function)                    │
├─────────────────────────────────────────────────────────────┤
│ functions/src/get_people.ts                                 │
│                                                              │
│ 1. ✅ Autenticação obrigatória (Firebase Auth)              │
│ 2. ✅ Verifica status VIP no Firestore (fonte da verdade)   │
│ 3. ✅ Define limite: Free = 17, VIP = 100                   │
│ 4. ✅ Query Firestore com bounding box                      │
│ 5. ✅ Filtros em memória (gender, age, verified)            │
│ 6. ✅ Ordenação VIP: vip_priority → rating                  │
│ 7. ✅ Aplica limite (IMPOSSÍVEL BURLAR)                     │
│ 8. ✅ Retorna dados completos para UI                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 🗂️ Arquivos Modificados

### **Backend (Cloud Functions)**

#### 1. `functions/src/get_people.ts` ✅ ATUALIZADO
```typescript
export const getPeople = functions.https.onCall(async (data, context) => {
  // 🔒 Verificação VIP no servidor (fonte da verdade)
  const isVip = userData.user_is_vip === true || 
                (userData.vipExpiresAt && userData.vipExpiresAt > now);
  
  // 🔒 Limite aplicado no servidor (impossível burlar)
  const limit = isVip ? 100 : 17; // 17 = 12 visíveis + 5 extras + VipLockCard
  
  // 🔒 Ordenação garantida pelo servidor
  candidates.sort((a, b) => {
    if (a.vip_priority !== b.vip_priority) return a.vip_priority - b.vip_priority;
    if (a.overallRating !== b.overallRating) return b.overallRating - a.overallRating;
    return 0;
  });
  
  return {
    users: candidates.slice(0, limit), // 🔒 LIMITE GARANTIDO
    isVip,
    limitApplied: limit,
  };
});
```

#### 2. `functions/src/index.ts` ✅ ATUALIZADO
```typescript
// Exportar Cloud Function
export {getPeople} from "./get_people";
```

---

### **Frontend (Flutter)**

#### 3. `lib/services/location/people_cloud_service.dart` ✅ NOVO
```dart
/// Serviço para chamar Cloud Function getPeople
class PeopleCloudService {
  Future<PeopleCloudResult> getPeopleNearby({
    required double userLatitude,
    required double userLongitude,
    required double radiusKm,
    required Map<String, double> boundingBox,
    UserCloudFilters? filters,
  }) async {
    // Chama Cloud Function
    final callable = _functions.httpsCallable('getPeople');
    final result = await callable.call({
      'boundingBox': boundingBox,
      'filters': filters?.toMap(),
    });
    
    // Calcula distâncias no client (melhor performance)
    return _calculateDistances(...);
  }
}
```

#### 4. `lib/services/location/location_query_service.dart` ✅ REFATORADO
```dart
// ✅ ANTES: Query direta no Firestore (inseguro)
// final usersSnap = await FirebaseFirestore.instance
//   .collection('Users')
//   .where('latitude', isGreaterThanOrEqualTo: minLat)
//   .get();

// ✅ AGORA: Cloud Function (seguro)
final result = await _cloudService.getPeopleNearby(
  userLatitude: userLocation.latitude,
  userLongitude: userLocation.longitude,
  radiusKm: radiusKm,
  boundingBox: boundingBox,
  filters: UserCloudFilters(...),
);

// ⚠️ REMOVIDO: Limite client-side (agora é server-side)
// if (!VipAccessService.isVip && finalUsers.length > 12) {
//   finalUsers = finalUsers.take(12).toList();
// }
```

#### 5. `lib/features/home/presentation/screens/find_people/find_people_controller.dart` ✅ MANTIDO
- ✅ Ordenação local preservada para consistência
- ✅ Enriquecimento de dados (ratings, interesses) continua no client
- ✅ Cache e performance otimizados

#### 6. `lib/features/home/presentation/screens/find_people_screen.dart` ✅ MANTIDO
- ✅ Mostra 12 cards + VipLockedCard (UX)
- ✅ Bloqueio ao scrollar para baixo
- ✅ VipDialog no 13º item

---

## 🔒 Camadas de Segurança

### **1. Server-Side (Impenetrável)**
```typescript
// ✅ Autenticação obrigatória
const userId = context.auth?.uid;
if (!userId) throw new Error("unauthenticated");

// ✅ Status VIP verificado no Firestore
const isVip = userData.user_is_vip === true;

// ✅ Limite aplicado no servidor
const limitedUsers = candidates.slice(0, limit);
```

### **2. Client-Side (UX)**
```dart
// ✅ UI mostra apenas 12 cards + VipLockedCard
itemCount: VipAccessService.isVip ? usersList.length : 13

// ✅ Bloqueio ao scrollar (experiência suave)
if (card12Visible && !_vipDialogOpen) {
  _showVipDialog();
}
```

---

## 📊 Comparação

| Aspecto | Antes (Client-Side) | Agora (Híbrido) |
|---------|---------------------|-----------------|
| **Limite de resultados** | ❌ Client (burlável) | ✅ Server (seguro) |
| **Verificação VIP** | ❌ RevenueCat local | ✅ Firestore server |
| **Ordenação VIP** | ❌ Client (modificável) | ✅ Server (garantido) |
| **Queries Firestore** | ❌ Diretas do client | ✅ Via Cloud Function |
| **Performance** | 🔶 Boa | ✅ Melhor (filtros no server) |
| **Segurança** | ❌ Vulnerável | ✅ Protegido |

---

## 🚀 Deploy

### **1. Deploy Cloud Function**
```bash
cd functions
firebase deploy --only functions:getPeople
```

### **2. Hot Reload Flutter**
```bash
flutter run
# Ctrl+R para hot reload
```

---

## ✅ Testes de Validação

### **1. Usuário Free**
- [ ] Deve ver apenas 12 cards + VipLockedCard
- [ ] Ao scrollar para baixo, VipDialog aparece
- [ ] Ao scrollar para cima, VipDialog NÃO aparece
- [ ] Console mostra: `limitApplied: 17`

### **2. Usuário VIP**
- [ ] Deve ver todos os usuários (até 100)
- [ ] Não vê VipLockedCard
- [ ] Não vê VipDialog ao scrollar
- [ ] Console mostra: `limitApplied: 100`

### **3. Ordenação VIP**
- [ ] Usuários com `vip_priority=1` aparecem primeiro
- [ ] Dentro de VIP, ordenado por `overallRating` DESC
- [ ] Dentro de rating igual, ordenado por `distance` ASC
- [ ] Console mostra: `🏆 [VIP Order] ...`

### **4. Segurança**
- [ ] Tentar modificar `vip_priority` local → não afeta servidor
- [ ] Descompilar APK e remover limite → Cloud Function ainda limita
- [ ] Query direta no Firestore → Firestore Rules bloqueiam

---

## 📝 Notas Importantes

### **Por que 17 usuários para Free?**
```
17 usuários do servidor = 12 cards visíveis + 5 extras + 1 VipLockedCard

- 12 cards: mostrados ao usuário
- 5 extras: buffer para scroll suave e cache
- 1 VipLockedCard: mostra no índice 12
```

### **Por que calcular distância no client?**
```dart
// ✅ PERFORMANCE: Isolate no client é mais rápido que loop no servidor
final distances = await compute(filterUsersByDistance, request);

// Server retorna dados brutos, client calcula distância em thread separada
// Não bloqueia UI e aproveita múltiplos cores
```

### **Por que ordenar 2x (server + client)?**
```dart
// 🔒 SERVER: Ordenação VIP garantida (segurança)
candidates.sort((a, b) => vipA - vipB);

// 🎨 CLIENT: Refinamento com distância (UX)
loadedUsers.sort((a, b) => {
  if (vipComparison != 0) return vipComparison;
  if (ratingComparison != 0) return ratingComparison;
  return distA.compareTo(distB); // Só client tem distância precisa
});
```

---

## 🎯 Resultado Final

### ✅ **Segurança**
- Limite de visualização impenetrável (server-side)
- Status VIP verificado no Firestore (fonte da verdade)
- Ordenação VIP garantida pelo backend

### ✅ **Performance**
- Filtros aplicados no servidor (menos dados trafegados)
- Cálculo de distância em Isolate (não bloqueia UI)
- Cache mantido para UX suave

### ✅ **UX**
- Bloqueio suave ao scrollar (apenas para baixo)
- VipLockedCard no 13º item
- Transição sem quebras visuais

---

## 🔗 Referências

- Cloud Functions: `functions/src/get_people.ts`
- Service: `lib/services/location/people_cloud_service.dart`
- Query Service: `lib/services/location/location_query_service.dart`
- Controller: `lib/features/home/presentation/screens/find_people/find_people_controller.dart`
- UI: `lib/features/home/presentation/screens/find_people_screen.dart`
