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

### 🧠 Regras de Negócio (Consolidadas)

| Regra | Descrição |
|------|-----------|
| **Quem pode postar** | Apenas usuários com `EventApplications.status` ∈ {`approved`, `autoApproved`} |
| **Seleção obrigatória** | Foto sempre vinculada a um evento (`eventId` obrigatório) |
| **Eventos elegíveis** | Apenas eventos passados (já ocorreram) |
| **Validação** | Backend valida participação **antes e depois** do upload |
| **Limite por evento** | Máx 3 fotos por usuário por evento |
| **Limite no feed do evento** | UI exibe apenas as 20 fotos mais recentes (não é hard limit no backend) |
| **Cooldown** | 2 minutos entre uploads do mesmo usuário |
| **Moderação** | Conteúdo começa em `under_review` e só fica público após validação (status `active`) |

---

## 🗂️ Estrutura de Dados Proposta

### Nova Coleção: `EventPhotos`

```typescript
interface EventPhoto {
  id: string;                 // doc.id (igual ao nome do arquivo no Storage)
  eventId: string;
  userId: string;

  imageUrl: string;
  thumbnailUrl?: string;

  caption?: string;           // máx 500 chars
  createdAt: Timestamp;

  // Denormalizados (dados estáveis)
  eventTitle: string;
  eventEmoji: string;
  eventDate: Timestamp;
  eventCityId?: string;       // ex: "sao_paulo"
  eventCityName?: string;     // ex: "São Paulo"

  userName: string;
  userPhotoUrl: string;

  // Estado e moderação
  status: 'under_review' | 'active' | 'hidden_by_reports' | 'hidden_by_moderation';
  reportCount: number;

  // Engajamento (cache)
  likesCount: number;
  commentsCount: number;
}
```

### ❤️ Engajamento (Subcoleções)

#### Likes

1 like por usuário garantido pelo ID:

`EventPhotos/{photoId}/likes/{userId}`

```typescript
interface EventPhotoLike {
  userId: string;
  createdAt: Timestamp;
}
```

#### Comentários

`EventPhotos/{photoId}/comments/{commentId}`

```typescript
interface EventPhotoComment {
  id: string;
  photoId: string;
  userId: string;
  userName: string;
  userPhotoUrl: string;
  text: string;
  createdAt: Timestamp;
  status: 'active' | 'hidden';
}
```

### Índices Necessários

```javascript
// Feed global
EventPhotos: status ASC, createdAt DESC

// Feed por evento
EventPhotos: eventId ASC, status ASC, createdAt DESC

// Feed por cidade
EventPhotos: eventCityId ASC, status ASC, createdAt DESC

// Feed por usuário
EventPhotos: userId ASC, createdAt DESC

// Moderação
EventPhotos: status ASC, reportCount DESC
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

### Tipos de Feed

| Feed | Query |
|------|------|
| **Cidade (default)** | `where('eventCityId', isEqualTo: user.cityId)` |
| **Global** | sem filtro de cidade |
| **Evento** | `where('eventId', isEqualTo: X)` |
| **Perfil** | `where('userId', isEqualTo: X)` |

Todos os feeds sempre filtram `status == 'active'` e usam paginação (`limit` + `startAfter`).

### Implementação do Feed (exemplo)

```dart
// EventPhotoFeedScreen com toggle de escopo
class EventPhotoFeedScreen extends HookConsumerWidget {
  Query<Map<String, dynamic>> _buildQuery(
    String? userCityId,
    FeedScope scope,
  ) {
    final baseQuery = FirebaseFirestore.instance
        .collection('EventPhotos')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(20);
    
    switch (scope) {
      case FeedScope.city:
        if (userCityId != null) {
          return baseQuery.where('eventCityId', isEqualTo: userCityId);
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

### Nota sobre cidade

Para suportar feed contextual (cidade), o documento armazena a cidade denormalizada em dois formatos:

- `eventCityId` (estável/normalizado, ex: `sao_paulo`)
- `eventCityName` (exibição, ex: `São Paulo`)

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

### 🔐 Upload Seguro (Tokenizado)

Objetivo: evitar criação de documentos inválidos/forjados e garantir que o arquivo no Storage e o doc no Firestore estejam vinculados 1:1.

#### 1️⃣ Callable: `validateEventPhotoUpload`

```typescript
// Valida ANTES do upload se usuário pode postar neste evento e retorna um photoId + token.
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
  
  // 5. Gerar IDs/Token de upload
  const photoId = db.collection('EventPhotos').doc().id;
  const uploadToken = generateUploadToken({
    userId,
    eventId,
    photoId,
  });

  return {
    allowed: true,
    photoId,
    uploadToken,
    eventTitle: eventData.activityText,
    eventEmoji: eventData.emoji,
  };
});
```

#### 2️⃣ Client (resumo)

1. Faz upload do arquivo para:

`event_photos/{eventId}/{photoId}.jpg`

2. Cria `EventPhotos/{photoId}` com:

- `status: 'under_review'`
- `uploadToken`

#### 3️⃣ Trigger: `onEventPhotoCreated`

```typescript
export const onEventPhotoCreated = functions.firestore
  .document('EventPhotos/{photoId}')
  .onCreate(async (snapshot, context) => {
    const photoData = snapshot.data();

    // 0. Validar token do upload (vínculo client -> callable)
    // Se inválido → apagar documento + cleanup do Storage.
    const tokenValid = await validateUploadToken(photoData.uploadToken, {
      photoId: context.params.photoId,
      userId: photoData.userId,
      eventId: photoData.eventId,
    });
    if (!tokenValid) {
      await snapshot.ref.delete();
      return;
    }
    
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
    const { cityId: eventCityId, cityName: eventCityName } = extractCityFromEvent(eventData);
    
    await snapshot.ref.update({
      eventTitle: eventData?.activityText || '',
      eventEmoji: eventData?.emoji || '📸',
      eventDate: eventData?.schedule?.startDate,
      eventCityId,
      eventCityName,
      userName: userDoc.data()?.fullName || '',
      userPhotoUrl: userDoc.data()?.photoUrl || '',

      // 4. Publicar
      status: 'active',
    });
    
    // 4. Notificar outros participantes (opcional)
    await notifyEventParticipants(photoData.eventId, photoData.userId);
  });

// Função helper para extrair cidade
function extractCityFromEvent(eventData: any): { cityId: string | null; cityName: string | null } {
  // Prioridade: campo específico > address parsing
  if (eventData?.location?.city) {
  const name = String(eventData.location.city);
  return { cityId: normalizeCityId(name), cityName: name };
  }
  
  // Fallback: extrair de formattedAddress
  const address = eventData?.location?.formattedAddress;
  if (address) {
    // Simplificação - na prática pode usar regex ou geocoding reverso
    const parts = address.split(',');
    if (parts.length >= 2) {
    const name = parts[parts.length - 2].trim();
    return { cityId: normalizeCityId(name), cityName: name };
    }
  }
  
  return { cityId: null, cityName: null };
}
```

### 🔒 Firestore Rules (Revisadas)

```javascript
match /EventPhotos/{photoId} {
  allow read: if request.auth != null
    && resource.data.status == 'active';

  allow create: if request.auth != null
    && request.auth.uid == request.resource.data.userId
    && request.resource.data.status == 'under_review';

  // Segurança: updates só via Cloud Functions
  allow update: if false;

  allow delete: if request.auth != null
    && request.auth.uid == resource.data.userId;

  match /likes/{userId} {
    allow read: if request.auth != null;
    allow create, delete: if request.auth.uid == userId;
  }

  match /comments/{commentId} {
    allow read: if request.auth != null;
    allow create: if request.auth.uid == request.resource.data.userId;
    allow update, delete: if request.auth.uid == resource.data.userId;
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

### Fase 1: MVP (Essencial)

| Task | Prioridade | Estimativa |
|------|------------|------------|
| Criar modelo `EventPhotoModel` | Alta | 2h |
| Criar `EventPhotoRepository` | Alta | 4h |
| Upload + validação tokenizada (callable + trigger) | Alta | 6h |
| Firestore rules | Alta | 2h |
| Feed por evento / cidade (status==active + paginação) | Alta | 6h |
| `EventSelectorBottomSheet` (eventos elegíveis: passados + approved/autoApproved) | Alta | 6h |
| `UploadEventPhotoScreen` (caption opcional) | Alta | 8h |
| `EventPhotoCard` widget | Alta | 4h |
| Integração no bottom nav / FAB | Alta | 2h |

**Total Fase 1**: ~30h

### Fase 2: Engajamento (1 semana)

| Task | Prioridade | Estimativa |
|------|------------|------------|
| Sistema de likes | Média | 6h |
| Sistema de comentários | Média | 8h |
| Notificações de engajamento | Média | 4h |
| Contador no perfil do usuário | Média | 2h |

**Total Fase 2**: ~20h

### Fase 3: Qualidade & Moderação (1 semana)

| Task | Prioridade | Estimativa |
|------|------------|------------|
| Report de fotos impróprias | Média | 4h |
| Galeria por evento | Média | 4h |
| Moderação automática (Cloud Vision) | Baixa | 8h |

**Nota**: feed por cidade/toggle entram como parte do MVP nesta versão (já que `eventCityId` faz parte do modelo e índices).

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
