# Sistema de Reviews - Plano Atualizado Partiu

## 🎯 Mudanças Importantes

### ✅ Decisões Arquiteturais

1. **Sem HTTP API** - Comunicação direta com Firestore
2. **Critérios Unificados** - Mesmos critérios para owner e participantes
3. **3 Steps no Review** - Ratings → Badges → Comentário
4. **Fluxo Bidirecional** - Todos avaliam todos

---

## 📋 Estrutura de Dados (Firestore)

### 1. Collection: `PendingReviews`

```dart
{
  'pending_review_id': 'auto_generated_id',
  'event_id': 'event123',
  'application_id': 'app456',
  'reviewer_id': 'user_abc',         // Quem vai avaliar
  'reviewee_id': 'user_xyz',         // Quem será avaliado
  'reviewer_role': 'owner',          // 'owner' | 'participant'
  'event_title': 'Rolê no parque',
  'event_emoji': '🏞️',
  'event_location': 'Parque Ibirapuera',
  'event_date': Timestamp,
  'created_at': Timestamp,
  'expires_at': Timestamp,           // 7 dias após evento
  'dismissed': false,
  'reviewee_name': 'João Silva',
  'reviewee_photo_url': 'https://...'
}
```

### 2. Collection: `Reviews`

```dart
{
  'review_id': 'auto_generated_id',
  'event_id': 'event123',
  'reviewer_id': 'user_abc',         // Quem avaliou
  'reviewee_id': 'user_xyz',         // Quem foi avaliado
  'reviewer_role': 'owner',          // 'owner' | 'participant'
  
  // RATINGS (1-5 estrelas) - MESMOS PARA TODOS
  'criteria_ratings': {
    'conversation': 5,               // Papo & Conexão
    'energy': 4,                     // Energia & Presença
    'coexistence': 5,                // Convivência
    'participation': 4               // Participação
  },
  'overall_rating': 4.5,             // Média automática
  
  // BADGES (opcional)
  'badges': [
    'mega_simpatico',                // 😄 Mega simpático(a)
    'muito_engracado'                // 😂 Muito engraçado(a)
  ],
  
  // COMENTÁRIO (opcional)
  'comment': 'Pessoa incrível! Adorei o rolê',
  
  // METADATA
  'created_at': Timestamp,
  'updated_at': Timestamp,
  
  // Dados do reviewer (para exibição)
  'reviewer_name': 'Ana Costa',
  'reviewer_photo_url': 'https://...'
}
```

### 3. Collection: `ReviewStats` (Cache)

```dart
{
  'user_id': 'user_xyz',
  'total_reviews': 15,
  'overall_rating': 4.5,
  
  // Média por critério
  'ratings_breakdown': {
    'conversation': 4.8,
    'energy': 4.2,
    'coexistence': 4.6,
    'participation': 4.4
  },
  
  // Contagem de badges recebidos
  'badges_count': {
    'mega_simpatico': 10,
    'muito_engracado': 5,
    'muito_inteligente': 8,
    'estilo_impecavel': 3,
    'super_educado': 12,
    'anima_todo_mundo': 7,
    'super_gato': 4
  },
  
  // Reviews recentes
  'recent_reviews_count': {
    'last_30_days': 3,
    'last_90_days': 8
  },
  
  'last_updated': Timestamp
}
```

---

## 🎨 Critérios de Avaliação (Unificados)

### Mesmos critérios para Owner e Participantes:

```dart
final reviewCriteria = [
  {
    'key': 'conversation',
    'icon': '💬',
    'title': 'Papo & Conexão',
    'description': 'Conseguiu manter uma boa conversa e criar conexão?'
  },
  {
    'key': 'energy',
    'icon': '⚡',
    'title': 'Energia & Presença',
    'description': 'Estava presente e engajado durante o evento?'
  },
  {
    'key': 'coexistence',
    'icon': '🤝',
    'title': 'Convivência',
    'description': 'Foi agradável e respeitoso com todos?'
  },
  {
    'key': 'participation',
    'icon': '🎯',
    'title': 'Participação',
    'description': 'Participou ativamente das atividades?'
  }
];
```

---

## 🏆 Sistema de Badges

### Lista completa de badges disponíveis:

```dart
final availableBadges = [
  {
    'key': 'mega_simpatico',
    'emoji': '😄',
    'title': 'Mega simpático(a)',
    'color': Color(0xFFFFEB3B), // Amarelo
  },
  {
    'key': 'muito_engracado',
    'emoji': '😂',
    'title': 'Muito engraçado(a)',
    'color': Color(0xFFFF9800), // Laranja
  },
  {
    'key': 'muito_inteligente',
    'emoji': '🧠',
    'title': 'Muito inteligente',
    'color': Color(0xFF9C27B0), // Roxo
  },
  {
    'key': 'estilo_impecavel',
    'emoji': '😍',
    'title': 'Estilo impecável',
    'color': Color(0xFFE91E63), // Pink
  },
  {
    'key': 'super_educado',
    'emoji': '🤝',
    'title': 'Super educado(a)',
    'color': Color(0xFF2196F3), // Azul
  },
  {
    'key': 'anima_todo_mundo',
    'emoji': '🎉',
    'title': 'Anima todo mundo',
    'color': Color(0xFF4CAF50), // Verde
  },
  {
    'key': 'super_gato',
    'emoji': '🐱',
    'title': 'Super gato(a)',
    'color': Color(0xFFFF5722), // Vermelho
  }
];
```

---

## 🎭 Fluxo dos 3 Steps

### Step 0: Ratings (Critérios)
- Exibe 4 critérios com sistema de estrelas (1-5)
- Usuário pode avaliar todos ou apenas alguns
- Botão "Continuar" valida se pelo menos 1 critério foi avaliado

### Step 1: Badges (NOVO)
- Título: "Quer deixar um elogio? Escolha um badge!"
- Grid com 7 badges disponíveis
- Usuário pode selecionar múltiplos badges (opcional)
- Botão "Continuar" (não é obrigatório selecionar)

### Step 2: Comentário
- Campo de texto livre (opcional)
- Placeholder: "Compartilhe sua experiência... (opcional)"
- Botões: "Pular" e "Enviar Avaliação"

---

## 🔄 Fluxo Bidirecional Completo

### Cenário: Evento "Rolê no parque" com 3 participantes

```
Owner: Ana
Participantes: Bruno, Carlos, Diana

Quando evento passa 24h:
├─ Ana (owner) avalia:
│  ├─ Bruno (participant)
│  ├─ Carlos (participant)
│  └─ Diana (participant)
│
├─ Bruno (participant) avalia:
│  └─ Ana (owner)
│
├─ Carlos (participant) avalia:
│  └─ Ana (owner)
│
└─ Diana (participant) avalia:
   └─ Ana (owner)

Total: 6 PendingReviews criados
```

---

## 📦 Estrutura de Arquivos Flutter

```
lib/
├─ features/
│  └─ reviews/
│     ├─ data/
│     │  ├─ models/
│     │  │  ├─ review_model.dart
│     │  │  ├─ pending_review_model.dart
│     │  │  ├─ review_stats_model.dart
│     │  │  └─ review_badge.dart
│     │  └─ repositories/
│     │     └─ review_repository.dart
│     │
│     ├─ domain/
│     │  └─ constants/
│     │     ├─ review_criteria.dart
│     │     └─ review_badges.dart
│     │
│     └─ presentation/
│        ├─ screens/
│        │  ├─ pending_reviews_screen.dart
│        │  └─ user_reviews_screen.dart
│        │
│        ├─ dialogs/
│        │  ├─ review_dialog.dart
│        │  └─ review_dialog_controller.dart
│        │
│        └─ components/
│           ├─ rating_criteria_step.dart
│           ├─ badge_selection_step.dart    ← NOVO
│           ├─ comment_step.dart
│           ├─ review_header.dart
│           ├─ reviewee_avatar_info.dart
│           ├─ error_message_box.dart
│           └─ review_actions.dart
```

---

## 🚀 Cloud Function (Backend)

### `functions/src/events/checkEventsForReview.ts`

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

/**
 * Roda a cada hora verificando eventos que passaram há 24h
 */
export const checkEventsForReview = functions.pubsub
  .schedule('every 1 hours')
  .timeZone('America/Sao_Paulo')
  .onRun(async () => {
    console.log('🔍 Checking events for review creation...');
    
    const now = admin.firestore.Timestamp.now();
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    
    // Busca eventos que terminaram há 24h e ainda não criaram reviews
    const eventsSnapshot = await admin.firestore()
      .collection('Events')
      .where('schedule.date', '<=', twentyFourHoursAgo)
      .where('reviewsCreated', '==', false)
      .limit(50)
      .get();
    
    console.log(`📊 Found ${eventsSnapshot.size} events to process`);
    
    for (const eventDoc of eventsSnapshot.docs) {
      try {
        await createPendingReviewsForEvent(eventDoc);
        
        // Marca evento como processado
        await eventDoc.ref.update({ 
          reviewsCreated: true,
          reviewsCreatedAt: now
        });
        
        console.log(`✅ Reviews created for event ${eventDoc.id}`);
      } catch (error) {
        console.error(`❌ Error processing event ${eventDoc.id}:`, error);
      }
    }
    
    return null;
  });

/**
 * Cria PendingReviews para um evento
 */
async function createPendingReviewsForEvent(
  eventDoc: admin.firestore.DocumentSnapshot
) {
  const eventData = eventDoc.data();
  if (!eventData) return;
  
  const eventId = eventDoc.id;
  const ownerId = eventData.createdBy;
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 dias
  
  // Busca participantes aprovados
  const applicationsSnapshot = await admin.firestore()
    .collection('EventApplications')
    .where('eventId', '==', eventId)
    .where('status', 'in', ['approved', 'autoApproved'])
    .get();
  
  // Filtra apenas quem confirmou presença
  const confirmedParticipants = applicationsSnapshot.docs.filter(doc => {
    const presence = doc.data().presence;
    return presence === 'Eu vou' || presence === 'Vou';
  });
  
  console.log(`👥 Found ${confirmedParticipants.length} confirmed participants`);
  
  // Busca dados do owner
  const ownerDoc = await admin.firestore()
    .collection('Users')
    .doc(ownerId)
    .get();
  const ownerData = ownerDoc.data();
  
  const batch = admin.firestore().batch();
  
  // Para cada participante confirmado
  for (const participantApp of confirmedParticipants) {
    const participantId = participantApp.data().userId;
    
    // Busca dados do participante
    const participantDoc = await admin.firestore()
      .collection('Users')
      .doc(participantId)
      .get();
    const participantData = participantDoc.data();
    
    // 1. Owner avalia Participante
    const ownerReviewRef = admin.firestore()
      .collection('PendingReviews')
      .doc();
    
    batch.set(ownerReviewRef, {
      pending_review_id: ownerReviewRef.id,
      event_id: eventId,
      application_id: participantApp.id,
      reviewer_id: ownerId,
      reviewee_id: participantId,
      reviewer_role: 'owner',
      event_title: eventData.activityText || eventData.title,
      event_emoji: eventData.emoji || '🎉',
      event_location: eventData.locationName || eventData.location?.locationName,
      event_date: eventData.schedule?.date || eventData.scheduleDate,
      created_at: admin.firestore.Timestamp.now(),
      expires_at: admin.firestore.Timestamp.fromDate(expiresAt),
      dismissed: false,
      reviewee_name: participantData?.fullname || 'Usuário',
      reviewee_photo_url: participantData?.user_photo_link || null
    });
    
    // 2. Participante avalia Owner
    const participantReviewRef = admin.firestore()
      .collection('PendingReviews')
      .doc();
    
    batch.set(participantReviewRef, {
      pending_review_id: participantReviewRef.id,
      event_id: eventId,
      application_id: participantApp.id,
      reviewer_id: participantId,
      reviewee_id: ownerId,
      reviewer_role: 'participant',
      event_title: eventData.activityText || eventData.title,
      event_emoji: eventData.emoji || '🎉',
      event_location: eventData.locationName || eventData.location?.locationName,
      event_date: eventData.schedule?.date || eventData.scheduleDate,
      created_at: admin.firestore.Timestamp.now(),
      expires_at: admin.firestore.Timestamp.fromDate(expiresAt),
      dismissed: false,
      reviewee_name: ownerData?.fullname || 'Usuário',
      reviewee_photo_url: ownerData?.user_photo_link || null
    });
  }
  
  // Commit batch
  await batch.commit();
  
  // Envia notificações (opcional)
  await sendReviewNotifications(ownerId, confirmedParticipants, eventData);
}

/**
 * Envia notificações para owner e participantes
 */
async function sendReviewNotifications(
  ownerId: string,
  participants: admin.firestore.QueryDocumentSnapshot[],
  eventData: any
) {
  const batch = admin.firestore().batch();
  
  // Notificação para owner
  const ownerNotifRef = admin.firestore().collection('Notifications').doc();
  batch.set(ownerNotifRef, {
    userId: ownerId,
    type: 'review_request',
    title: '⭐ Hora de avaliar!',
    message: `Avalie os participantes do evento "${eventData.activityText}"`,
    data: {
      eventId: eventData.id,
      actionType: 'open_pending_reviews'
    },
    createdAt: admin.firestore.Timestamp.now(),
    read: false
  });
  
  // Notificações para participantes
  for (const participantApp of participants) {
    const participantId = participantApp.data().userId;
    const participantNotifRef = admin.firestore().collection('Notifications').doc();
    
    batch.set(participantNotifRef, {
      userId: participantId,
      type: 'review_request',
      title: '⭐ Avalie o evento!',
      message: `Como foi o evento "${eventData.activityText}"? Deixe sua avaliação!`,
      data: {
        eventId: eventData.id,
        actionType: 'open_pending_reviews'
      },
      createdAt: admin.firestore.Timestamp.now(),
      read: false
    });
  }
  
  await batch.commit();
}
```

---

## 📱 Repository Flutter (Firestore direto)

### `lib/features/reviews/data/repositories/review_repository.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/features/reviews/data/models/review_model.dart';
import 'package:partiu/features/reviews/data/models/pending_review_model.dart';
import 'package:partiu/features/reviews/data/models/review_stats_model.dart';

class ReviewRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // ==================== PENDING REVIEWS ====================
  
  /// Busca reviews pendentes do usuário atual
  Future<List<PendingReviewModel>> getPendingReviews(String userId) async {
    final now = Timestamp.now();
    
    final snapshot = await _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: userId)
        .where('dismissed', isEqualTo: false)
        .where('expires_at', isGreaterThan: now)
        .orderBy('expires_at')
        .orderBy('created_at', descending: true)
        .limit(20)
        .get();
    
    // Filtra reviews já submetidos
    final pendingReviews = <PendingReviewModel>[];
    
    for (final doc in snapshot.docs) {
      final pending = PendingReviewModel.fromFirestore(doc);
      
      // Verifica se já existe review
      final existingReview = await _firestore
          .collection('Reviews')
          .where('reviewer_id', isEqualTo: userId)
          .where('reviewee_id', isEqualTo: pending.revieweeId)
          .where('event_id', isEqualTo: pending.eventId)
          .limit(1)
          .get();
      
      if (existingReview.docs.isEmpty) {
        pendingReviews.add(pending);
      }
    }
    
    return pendingReviews;
  }
  
  /// Marca pending review como dismissed
  Future<void> dismissPendingReview(String pendingReviewId) async {
    await _firestore
        .collection('PendingReviews')
        .doc(pendingReviewId)
        .update({
      'dismissed': true,
      'dismissed_at': FieldValue.serverTimestamp(),
    });
  }
  
  // ==================== REVIEWS ====================
  
  /// Cria uma nova review
  Future<void> createReview(ReviewModel review) async {
    // Verifica duplicata
    final existing = await _firestore
        .collection('Reviews')
        .where('reviewer_id', isEqualTo: review.reviewerId)
        .where('reviewee_id', isEqualTo: review.revieweeId)
        .where('event_id', isEqualTo: review.eventId)
        .limit(1)
        .get();
    
    if (existing.docs.isNotEmpty) {
      throw Exception('Review já existe para este evento');
    }
    
    // Cria review
    final docRef = await _firestore
        .collection('Reviews')
        .add(review.toFirestore());
    
    // Atualiza stats do reviewee
    await _updateReviewStats(review.revieweeId);
    
    // Remove pending review
    await _removePendingReview(
      review.reviewerId,
      review.revieweeId,
      review.eventId,
    );
  }
  
  /// Busca reviews de um usuário
  Future<List<ReviewModel>> getUserReviews(
    String userId, {
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _firestore
        .collection('Reviews')
        .where('reviewee_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(limit);
    
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    final snapshot = await query.get();
    
    return snapshot.docs
        .map((doc) => ReviewModel.fromFirestore(doc))
        .toList();
  }
  
  /// Busca estatísticas de reviews
  Future<ReviewStatsModel?> getReviewStats(String userId) async {
    final doc = await _firestore
        .collection('ReviewStats')
        .doc(userId)
        .get();
    
    if (!doc.exists) {
      // Calcula pela primeira vez
      await _updateReviewStats(userId);
      final recalculatedDoc = await _firestore
          .collection('ReviewStats')
          .doc(userId)
          .get();
      
      if (recalculatedDoc.exists) {
        return ReviewStatsModel.fromFirestore(recalculatedDoc);
      }
      return null;
    }
    
    return ReviewStatsModel.fromFirestore(doc);
  }
  
  // ==================== PRIVATE HELPERS ====================
  
  Future<void> _updateReviewStats(String userId) async {
    final reviewsSnapshot = await _firestore
        .collection('Reviews')
        .where('reviewee_id', isEqualTo: userId)
        .get();
    
    if (reviewsSnapshot.docs.isEmpty) {
      // Sem reviews ainda
      return;
    }
    
    final reviews = reviewsSnapshot.docs
        .map((doc) => ReviewModel.fromFirestore(doc))
        .toList();
    
    // Calcula estatísticas
    final stats = ReviewStatsModel.calculate(userId, reviews);
    
    // Salva no Firestore
    await _firestore
        .collection('ReviewStats')
        .doc(userId)
        .set(stats.toFirestore(), SetOptions(merge: true));
  }
  
  Future<void> _removePendingReview(
    String reviewerId,
    String revieweeId,
    String eventId,
  ) async {
    final snapshot = await _firestore
        .collection('PendingReviews')
        .where('reviewer_id', isEqualTo: reviewerId)
        .where('reviewee_id', isEqualTo: revieweeId)
        .where('event_id', isEqualTo: eventId)
        .limit(1)
        .get();
    
    if (snapshot.docs.isNotEmpty) {
      await snapshot.docs.first.reference.delete();
    }
  }
}
```

---

## 🎯 Próximos Passos

1. ✅ Criar modelos (Review, PendingReview, ReviewStats, ReviewBadge)
2. ✅ Criar ReviewRepository com métodos Firestore
3. ✅ Adaptar ReviewDialogController para 3 steps
4. ✅ Criar BadgeSelectionStep component
5. ✅ Adaptar ReviewDialog
6. ✅ Criar Cloud Function checkEventsForReview
7. ✅ Criar tela de pending reviews
8. ✅ Integrar com perfil do usuário

---

## 📊 Estimativa Atualizada

- **Modelos Flutter**: 2-3 horas
- **ReviewRepository**: 3-4 horas
- **BadgeSelectionStep**: 2-3 horas
- **Adaptar Dialog/Controller**: 3-4 horas
- **Cloud Function**: 4-5 horas
- **Testes e ajustes**: 4-5 horas
- **TOTAL**: ~20-24 horas

Pronto para começar! 🚀
