# 📸 Feed de Fotos de Eventos - Plano de Implementação

> **Data**: 20/01/2026  
> **Status**: Proposta de Feature  
> **Objetivo**: Permitir que participantes postem fotos dos eventos que participaram  
> **Revisão**: v1.1 - Incorporado feedback de arquitetura

---

## 📊 Análise do Sistema de Ranking Atual

### Sistema de Reviews (review_dialog.dart)

O sistema atual de reviews segue um fluxo bem estruturado:

1. **Owner Flow** (Organizador):
   - Confirmação de presença dos participantes → Ratings → Badges → Comentário
   - Persiste `confirmedParticipantIds` para liberar reviews

2. **Participant Flow** (Participante):
   - Só pode avaliar o owner se `allowedToReviewOwner = true`
   - Ratings → Badges → Comentário

3. **Controle de Acesso**:
   - Baseado em `PendingReviewModel` que é criado após o evento
   - Owner só pode avaliar quem confirmou presença
   - Participantes só podem avaliar se foram confirmados pelo owner

### Coleções Relacionadas Existentes

| Coleção | Propósito |
|---------|-----------|
| `EventApplications` | Registra quem aplicou/foi aprovado em eventos |
| `Reviews` | Avaliações entre participantes |
| `PendingReviews` | Reviews pendentes de serem feitas |
| `ReviewStats` | Cache de estatísticas de reviews por usuário |

---

## 🎯 Proposta: Event Photo Feed

### Conceito

Um feed onde participantes podem compartilhar fotos dos eventos que participaram, criando um registro visual e social das experiências.

### Regras de Negócio

| Regra | Descrição |
|-------|-----------|
| **Quem pode postar** | Apenas usuários com `EventApplications.status` = `approved` ou `autoApproved` |
| **Seleção obrigatória** | Usuário DEVE selecionar o evento ao qual a foto pertence |
| **Eventos elegíveis** | Apenas eventos **passados** (já ocorreram) |
| **Validação** | Backend verifica se usuário realmente participou do evento |
| **Limite por evento** | Máx **3 fotos** por usuário por evento |
| **Limite global** | Máx **20 fotos** no feed de um evento |
| **Cooldown** | Mínimo **2 minutos** entre uploads do mesmo usuário |

---

## 🗂️ Estrutura de Dados Proposta

### Nova Coleção: `EventPhotos`

```typescript
interface EventPhoto {
  id: string;                    // Auto-generated (usado como nome no Storage)
  eventId: string;               // Referência ao evento
  userId: string;                // Quem postou
  imageUrl: string;              // URL no Firebase Storage
  thumbnailUrl?: string;         // Thumbnail otimizado (opcional)
  caption?: string;              // Legenda (opcional, max 500 chars)
  createdAt: Timestamp;          // Data de criação
  
  // Denormalizados para performance (evita joins) - ESTÁVEIS
  eventTitle: string;            // Título do evento
  eventEmoji: string;            // Emoji do evento
  eventDate: Timestamp;          // Data do evento
  eventCity?: string;            // Cidade do evento (para feed contextual)
  userName: string;              // Nome de quem postou
  userPhotoUrl: string;          // Foto de perfil de quem postou
  
  // Moderação (estados claros e auditáveis)
  status: 'active' | 'under_review' | 'hidden_by_reports' | 'hidden_by_moderation';
  reportCount: number;           // Contagem de denúncias
  moderatedAt?: Timestamp;       // Quando foi moderado (se aplicável)
  moderatedBy?: string;          // Quem moderou (admin userId)
  
  // Engajamento - VOLÁTEIS (apenas contadores, dados reais em subcoleções)
  likesCount: number;            // Cache - fonte: EventPhotoLikes
  commentsCount: number;         // Cache - fonte: EventPhotoComments
}
```

### Subcoleções de Engajamento (Fase 2)

```typescript
// EventPhotoLikes/{photoId}_{oduserId} - Documento único por like
interface EventPhotoLike {
  odphotoId: string;
  userId: string;
  createdAt: Timestamp;
}

// EventPhotoComments/{commentId}
interface EventPhotoComment {
  id: string;
  photoId: string;
  userId: string;
  userName: string;              // Denormalizado
  userPhotoUrl: string;          // Denormalizado
  text: string;
  createdAt: Timestamp;
  status: 'active' | 'hidden';
}
```

### Índices Necessários

```javascript
// Para feed global (mais recentes)
EventPhotos: createdAt DESC

// Para feed de um evento específico
EventPhotos: eventId ASC, createdAt DESC

// Para fotos de um usuário
EventPhotos: userId ASC, createdAt DESC

// Para moderação
EventPhotos: status ASC, reportCount DESC

// Para feed por cidade (contextual)
EventPhotos: eventCity ASC, createdAt DESC
```

---

## 🌍 Feed Contextual vs Global

### Estratégia de Exibição

O feed de fotos pode ter diferentes escopos dependendo do contexto:

| Tipo | Descrição | Quando usar |
|------|-----------|-------------|
| **Feed da Cidade** | Fotos de eventos na cidade do usuário | Tela principal (padrão) |
| **Feed Global** | Todas as fotos de todas as cidades | Toggle "Ver todas" |
| **Feed do Evento** | Fotos específicas de um evento | Ao abrir detalhes do evento |
| **Feed do Usuário** | Fotos postadas por um usuário | Ao visitar perfil |

### Implementação do Feed Contextual

```dart
// EventPhotoFeedScreen com toggle de escopo
class EventPhotoFeedScreen extends HookConsumerWidget {
  Query<Map<String, dynamic>> _buildQuery(
    String? userCity, 
    FeedScope scope,
  ) {
    final baseQuery = FirebaseFirestore.instance
        .collection('EventPhotos')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(20);
    
    switch (scope) {
      case FeedScope.city:
        if (userCity != null) {
          return baseQuery.where('eventCity', isEqualTo: userCity);
        }
        return baseQuery; // fallback para global
      case FeedScope.global:
        return baseQuery;
      case FeedScope.event:
        return baseQuery.where('eventId', isEqualTo: selectedEventId);
      case FeedScope.user:
        return baseQuery.where('userId', isEqualTo: selectedUserId);
    }
  }
}
```

### Campo Adicional Necessário

Para suportar feed por cidade, o `EventPhoto` precisa armazenar a cidade do evento:

```typescript
interface EventPhoto {
  // ... campos existentes ...
  eventCity?: string;            // Denormalizado do evento (ex: "São Paulo")
  eventCountry?: string;         // Opcional, para escalar internacionalmente
}
```

> **NOTA**: A cidade é denormalizada no momento da criação da foto, baseada na localização do evento. Isso evita joins e permite queries eficientes por localização.

### Storage Path

```
event_photos/
  └── {eventId}/
      └── {photoId}.jpg          // photoId = doc.id do Firestore
```

**Vantagens desta estrutura:**
- ✅ Simplifica cleanup (delete doc → delete file com mesmo ID)
- ✅ Traceabilidade direta Firestore ↔ Storage
- ✅ Menos lógica no client (userId já está no documento)

---

## 🏗️ Arquitetura Proposta

### Estrutura de Arquivos

```
lib/features/event_photos/
├── data/
│   ├── models/
│   │   └── event_photo_model.dart
│   ├── repositories/
│   │   └── event_photo_repository.dart
│   └── services/
│       └── event_photo_upload_service.dart
├── domain/
│   └── validators/
│       └── event_photo_validator.dart
├── presentation/
│   ├── viewmodels/
│   │   ├── event_photo_feed_viewmodel.dart
│   │   └── upload_photo_viewmodel.dart
│   ├── screens/
│   │   ├── event_photo_feed_screen.dart
│   │   └── upload_event_photo_screen.dart
│   ├── widgets/
│   │   ├── event_photo_card.dart
│   │   ├── event_selector_bottom_sheet.dart
│   │   └── photo_feed_shimmer.dart
│   └── dialogs/
│       └── report_photo_dialog.dart

functions/src/
└── eventPhotos/
    ├── onPhotoCreated.ts        // Validação e denormalização
    ├── onPhotoDeleted.ts        // Cleanup Storage
    └── moderatePhoto.ts         // Moderação automática/manual
```

---

## 🔒 Cloud Functions & Security

### 1. `validateEventPhotoUpload` (Callable)

```typescript
// Valida ANTES do upload se usuário pode postar neste evento
export const validateEventPhotoUpload = functions.https.onCall(async (data, context) => {
  const { eventId } = data;
  const userId = context.auth?.uid;
  
  if (!userId) throw new HttpsError('unauthenticated', 'Login required');
  
  // 1. Verificar se evento existe e já ocorreu
  const eventDoc = await db.collection('events').doc(eventId).get();
  if (!eventDoc.exists) throw new HttpsError('not-found', 'Event not found');
  
  const eventData = eventDoc.data();
  const eventDate = eventData.schedule?.startDate?.toDate();
  if (eventDate && eventDate > new Date()) {
    throw new HttpsError('failed-precondition', 'Event has not occurred yet');
  }
  
  // 2. Verificar se usuário participou
  const applicationSnapshot = await db.collection('EventApplications')
    .where('eventId', '==', eventId)
    .where('userId', '==', userId)
    .where('status', 'in', ['approved', 'autoApproved'])
    .limit(1)
    .get();
    
  if (applicationSnapshot.empty) {
    throw new HttpsError('permission-denied', 'User did not participate in this event');
  }
  
  // 3. Verificar limite de fotos por usuário neste evento (máx 3)
  const userPhotosCount = await db.collection('EventPhotos')
    .where('eventId', '==', eventId)
    .where('userId', '==', userId)
    .count()
    .get();
    
  if (userPhotosCount.data().count >= 3) {
    throw new HttpsError('resource-exhausted', 'Maximum 3 photos per event reached');
  }
  
  // 4. Verificar cooldown (2 minutos entre uploads)
  const recentPhoto = await db.collection('EventPhotos')
    .where('userId', '==', userId)
    .orderBy('createdAt', 'desc')
    .limit(1)
    .get();
    
  if (!recentPhoto.empty) {
    const lastUpload = recentPhoto.docs[0].data().createdAt.toDate();
    const cooldownMs = 2 * 60 * 1000; // 2 minutos
    if (Date.now() - lastUpload.getTime() < cooldownMs) {
      throw new HttpsError('resource-exhausted', 'Please wait before uploading another photo');
    }
  }
  
  return { allowed: true, eventTitle: eventData.activityText, eventEmoji: eventData.emoji };
});
```

### 2. `onEventPhotoCreated` (Trigger)

```typescript
export const onEventPhotoCreated = functions.firestore
  .document('EventPhotos/{photoId}')
  .onCreate(async (snapshot, context) => {
    const photoData = snapshot.data();
    
    // 1. Re-validar participação (segurança)
    const isParticipant = await validateParticipation(photoData.eventId, photoData.userId);
    if (!isParticipant) {
      await snapshot.ref.delete();
      return;
    }
    
    // 2. Denormalizar dados do evento e usuário
    const [eventDoc, userDoc] = await Promise.all([
      db.collection('events').doc(photoData.eventId).get(),
      db.collection('Users').doc(photoData.userId).get(),
    ]);
    
    const eventData = eventDoc.data();
    
    // 3. Extrair cidade do evento (para feed contextual)
    // Pode vir de location.address ou de um campo específico
    const eventCity = extractCityFromEvent(eventData);
    
    await snapshot.ref.update({
      eventTitle: eventData?.activityText || '',
      eventEmoji: eventData?.emoji || '📸',
      eventDate: eventData?.schedule?.startDate,
      eventCity: eventCity,                        // Para feed contextual
      userName: userDoc.data()?.fullName || '',
      userPhotoUrl: userDoc.data()?.photoUrl || '',
    });
    
    // 4. Notificar outros participantes (opcional)
    await notifyEventParticipants(photoData.eventId, photoData.userId);
  });

// Função helper para extrair cidade
function extractCityFromEvent(eventData: any): string | null {
  // Prioridade: campo específico > address parsing
  if (eventData?.location?.city) {
    return eventData.location.city;
  }
  
  // Fallback: extrair de formattedAddress
  const address = eventData?.location?.formattedAddress;
  if (address) {
    // Simplificação - na prática pode usar regex ou geocoding reverso
    const parts = address.split(',');
    if (parts.length >= 2) {
      return parts[parts.length - 2].trim();
    }
  }
  
  return null;
}
```

### 3. Firestore Rules

```javascript
match /EventPhotos/{photoId} {
  // Leitura: qualquer autenticado pode ver fotos ativas
  // (fotos escondidas por moderação não aparecem na query do app)
  allow read: if request.auth != null;
  
  // Criação: usuário autenticado, é o dono do documento
  allow create: if request.auth != null 
    && request.auth.uid == request.resource.data.userId
    && request.resource.data.status == 'active';
  
  // Update: apenas o dono (para caption/delete) ou Cloud Function (para status)
  // NOTA: Mudança de status só via Cloud Functions (admin/moderação)
  allow update: if request.auth != null 
    && request.auth.uid == resource.data.userId
    && request.resource.data.status == resource.data.status; // não pode mudar status
  
  // Delete: apenas o dono
  allow delete: if request.auth != null 
    && request.auth.uid == resource.data.userId;
  
  // SUBCOLEÇÕES
  
  // Likes: cada usuário pode dar um like (documento com ID = userId)
  match /EventPhotoLikes/{likeUserId} {
    allow read: if request.auth != null;
    allow create, delete: if request.auth != null 
      && request.auth.uid == likeUserId;
    allow update: if false; // likes são imutáveis
  }
  
  // Comentários
  match /EventPhotoComments/{commentId} {
    allow read: if request.auth != null;
    allow create: if request.auth != null 
      && request.auth.uid == request.resource.data.userId;
    allow update: if request.auth != null 
      && request.auth.uid == resource.data.userId;
    allow delete: if request.auth != null 
      && (request.auth.uid == resource.data.userId 
          || request.auth.uid == get(/databases/$(database)/documents/EventPhotos/$(photoId)).data.userId);
  }
}
```

---

## 📱 Fluxo de UI

### 1. Acessando o Feed

```
HomeScreen
  └── BottomNavBar
      └── "Fotos" Tab (novo) ou integrado ao Feed existente
          └── EventPhotoFeedScreen
```

### 2. Postando uma Foto

```
FloatingActionButton (+) 
  └── SelectPhotoFromGallery/Camera
      └── EventSelectorBottomSheet
          ├── Lista eventos passados que participou
          ├── Busca por título
          └── Preview: Emoji + Título + Data
              └── AddCaptionScreen (opcional)
                  └── ConfirmAndUpload
```

### 3. Event Selector Bottom Sheet

```dart
class EventSelectorBottomSheet extends StatelessWidget {
  // Mostra apenas eventos:
  // - Que o usuário participou (status approved/autoApproved)
  // - Que já ocorreram (data < hoje)
  // - Ordenados por data (mais recentes primeiro)
  
  Future<List<Event>> _getEligibleEvents(String userId) async {
    final applications = await _getApprovedApplications(userId);
    final pastEventIds = applications
      .where((app) => isPastEvent(app.eventId))
      .map((app) => app.eventId)
      .toList();
    
    return _getEventsByIds(pastEventIds);
  }
}
```

---

## 🚀 Fases de Implementação

### Fase 1: MVP (1-2 semanas)

| Task | Prioridade | Estimativa |
|------|------------|------------|
| Criar modelo `EventPhotoModel` | Alta | 2h |
| Criar `EventPhotoRepository` | Alta | 4h |
| Cloud Function de validação | Alta | 4h |
| Firestore rules | Alta | 2h |
| `EventSelectorBottomSheet` | Alta | 6h |
| `UploadEventPhotoScreen` | Alta | 8h |
| `EventPhotoFeedScreen` (lista simples) | Alta | 6h |
| `EventPhotoCard` widget | Alta | 4h |
| Integração no bottom nav / FAB | Alta | 2h |

**Total Fase 1**: ~38h

### Fase 2: Engajamento (1 semana)

| Task | Prioridade | Estimativa |
|------|------------|------------|
| Sistema de likes | Média | 6h |
| Sistema de comentários | Média | 8h |
| Notificações de engajamento | Média | 4h |
| Contador no perfil do usuário | Média | 2h |

**Total Fase 2**: ~20h

### Fase 3: Feed Contextual & Melhorias (1 semana)

| Task | Prioridade | Estimativa |
|------|------------|------------|
| Feed por cidade (contextual) | Alta | 4h |
| Toggle cidade/global | Alta | 2h |
| Report de fotos impróprias | Média | 4h |
| Galeria por evento | Média | 4h |
| Moderação automática (Cloud Vision) | Baixa | 8h |

**Total Fase 3**: ~22h

---

## ⚠️ Considerações de Viabilidade

### ✅ Pontos Positivos

1. **Reutiliza infraestrutura existente**:
   - Firebase Storage já configurado
   - Sistema de upload de imagens funcional
   - `ImageCompressService` para otimização
   - `ImageUploadService` como base

2. **Segurança bem definida**:
   - Validação via `EventApplications` é confiável
   - Padrão já usado no sistema de reviews

3. **Baixo custo incremental**:
   - Escala bem com Cloud Functions
   - Denormalização evita queries caras

### ⚠️ Pontos de Atenção

1. **Custo de Storage**:
   - Imagens ocupam espaço (~200-500KB cada comprimida)
   - Considerar limite de fotos por evento/usuário
   - Implementar cleanup de fotos antigas

2. **Moderação**:
   - Conteúdo gerado por usuário = risco
   - Implementar report system desde o início
   - Considerar Cloud Vision API para moderação automática

3. **Performance do Feed**:
   - Usar paginação (`.limit()` + cursor)
   - Lazy loading de imagens
   - Thumbnails para preview

---

## 🔗 Integração com Sistema de Reviews

### Sinergia Potencial

O feed de fotos pode complementar o sistema de reviews:

```typescript
// Ao postar foto, incrementar "contribuição" do usuário
await db.collection('Users').doc(userId).update({
  eventPhotosCount: FieldValue.increment(1),
  lastPhotoAt: FieldValue.serverTimestamp(),
});

// Considerar fotos no cálculo de ranking (opcional)
// Usuários que compartilham fotos demonstram mais engajamento
```

### Exibição no Perfil

```dart
ProfileScreen
  └── Stats Row
      ├── ⭐ 4.8 (reviews)
      ├── 📸 12 (fotos postadas)  // NOVO
      └── 🎉 8 (eventos)
```

---

## 📝 Próximos Passos

1. **Validar proposta** com stakeholders
2. **Prototipar UI** no Figma
3. **Criar branch** `feature/event-photo-feed`
4. **Implementar** Fase 1 MVP
5. **Testar** com grupo beta
6. **Iterar** baseado em feedback

---

## 📚 Referências

- Sistema de reviews existente: `lib/features/reviews/`
- Upload de imagens: `lib/features/profile/data/services/image_upload_service.dart`
- Validação de participação: `lib/features/home/data/repositories/event_application_repository.dart`
- Ranking system: `RANKING_SYSTEM_COMPLETE.md`

---

**Autor**: GitHub Copilot  
**Revisão**: v1.1 - Incorporado feedback de arquitetura (subcoleções, limites, feed contextual)  
**Última atualização**: Junho 2025
