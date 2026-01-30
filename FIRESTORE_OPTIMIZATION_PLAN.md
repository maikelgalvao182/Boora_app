# Plano de Otimização Firestore: Coleção Espelho (events_map)

## Problema
O app atualmente consome o documento completo do evento na coleção `events` (ou `events_map` com payload completo) para renderizar o mapa. Isso resulta em alto consumo de banda (bytes transferidos) e latência, já que campos pesados (arrays de participantes, galeria de fotos, descrições longas) são baixados desnecessariamente apenas para exibir markers.

## Solução Implementada
Criação de uma "Cloud Function Espelho" que sincroniza automaticamente documentos da coleção `events` para uma coleção leve `events_map`.

### 1. Arquitetura

- **Fonte:** `events/{eventId}` (Documento Pesado)
- **Destino:** `events_map/{eventId}` (Preview Leve)
- **Gatilho:** `onWrite` (Create, Update, Delete)

### 2. Schema da Coleção `events_map`

O documento lite contém **apenas** o necessário para:
1. Query Geoespacial (lat/lng/filters)
2. Renderização do Marker (Icon/Avatar)
3. Preview inicial do Card (Title/Thumb/Resumo)

```json
{
  "location": { "latitude": -23.5, "longitude": -46.6 },
  "isActive": true,
  
  // Marker
  "emoji": "⚽",
  "activityText": "Futebol no Ibirapuera",
  "category": "sports",
  
  // Card Preview & N+1 Fix
  "scheduleDate": "Timestamp",
  "photoUrl": "https://.../thumb.jpg",
  "creatorAvatarUrl": "https://.../avatar.jpg", // Denormalized
  "creatorFullName": "João Silva", // Denormalized
  "participantsCount": 15,
  
  // Filtros
  "privacyType": "open",
  "minAge": 18,
  "maxAge": 100,
  "gender": "all",
  
  // Meta
  "updatedAt": "Timestamp",
  "createdBy": "user123",
  "isBoosted": false,
  "hasPremium": true
}
```

### 3. Código da Cloud Function (Implementado)

O arquivo `functions/src/events/mapSync.ts` já foi criado com a lógica:
- Escuta mudanças em `events/{eventId}`.
- Se o evento for deletado, remove de `events_map`.
- Se o evento não for "visível" (`isActive=false`, `isCanceled=true`, etc.), remove de `events_map`.
- Se for válido, cria/atualiza o documento leve em `events_map`.

### 4. Como Ativar

1.  **Deploy da Function:**
    ```bash
    firebase deploy --only functions:syncEventToMap
    ```

2.  **Migração de Dados (Backfill):**
    Como o gatilho só roda em eventos *alterados*, você precisa rodar um script para popular o `events_map` com os eventos existentes.
    
    Crie um script temporário ou use o console do Firebase para "tocar" (update dummy) em todos os eventos ativos, ou rode um script Node.js admin:

    ```javascript
    // Exemplo de script de migração (rodar localmente com admin-sdk)
    async function migrateEvents() {
      const snapshot = await db.collection('events').where('isActive', '==', true).get();
      for (const doc of snapshot.docs) {
        // Trigger the function by touching updatedAt
        await doc.ref.update({ _migration: true }); 
        console.log(`Migrating ${doc.id}...`);
      }
    }
    ```

### 5. Ajustes no App Flutter

O `MapDiscoveryService` já consulta a coleção `events_map`. Com essa mudança, o payload recebido pelo app será drasticamente menor.

**Recomendação:**
No futuro, remover o fallback para a coleção `events` no `MapDiscoveryService` para garantir que o app nunca baixe payloads pesados no mapa.

```dart
// (Atual)
if (events.isEmpty && _allowEventsFallback) { ... busca em events ... }

// (Futuro - após migração)
// Remover o bloco acima.
```

## Impacto Estimado
- **Leitura de Bytes:** Redução de ~80% por doc (dependendo do tamanho da descrição/arrays do evento original).
- **Tempo de Mapa:** Carregamento mais rápido devido ao payload menor.
- **Custo:** Economia direta na fatura do Firebase (Bandwidth).
