# Sistema de Reviews - Plano de Implementação Partiu

## 📊 Análise de Reaproveitamento do Advanced-Dating

### ✅ O que PODE ser reaproveitado (80% do código)

#### 1. **UI Components (100% reutilizável)**
Toda a pasta `review_components/` pode ser reaproveitada:
- ✅ `comment_section.dart` - Campo de comentário opcional
- ✅ `error_message_box.dart` - Exibição de erros
- ✅ `rating_criteria_list.dart` - Lista de critérios com estrelas (só precisa adaptar critérios)
- ✅ `review_actions.dart` - Botões submit/dismiss
- ✅ `review_header.dart` - Header do modal
- ✅ `reviewee_avatar_info.dart` - Info da pessoa sendo avaliada

#### 2. **Dialog Controller (90% reutilizável)**
O `review_dialog_controller.dart` só precisa de ajustes mínimos:
- ✅ Lógica de navegação entre steps (ratings → comentário)
- ✅ Validação de campos
- ✅ Gerenciamento de estado (loading, errors)
- 🔄 Apenas ajustar critérios específicos para eventos sociais

#### 3. **Backend Logic (85% reutilizável)**
Do arquivo `review.ts`:

##### ✅ Endpoints HTTP que podem ser adaptados:
```typescript
GET  /reviews/pending          // Lista reviews pendentes
POST /reviews                  // Cria review
POST /reviews/dismiss          // Descarta review
GET  /reviews/user/:userId     // Reviews de um usuário
GET  /reviews/stats/:userId    // Estatísticas agregadas
GET  /reviews/check            // Verifica duplicatas
```

##### ✅ Funções auxiliares:
- `calculateReviewStats()` - Calcula estatísticas agregadas
- `updateReviewStats()` - Atualiza cache de stats
- `removePendingReview()` - Remove review pendente após submit

#### 4. **Estrutura de Dados (95% compatível)**

##### Reviews Collection
```typescript
{
  reviewId: string,
  reviewerId: string,           // Quem está avaliando
  revieweeId: string,           // Quem está sendo avaliado
  eventId: string,              // ID do evento
  overallRating: number,        // Nota geral (1-5)
  criteriaRatings: {            // Notas por critério
    [criterion: string]: number
  },
  comment?: string,             // Comentário opcional
  createdAt: Timestamp,
  updatedAt: Timestamp,
  // Dados adicionais do reviewer
  fullname?: string,
  user_photo_link?: string,
}
```

##### ReviewStats Collection (cache)
```typescript
{
  userId: string,
  totalReviews: number,
  overallRating: number,
  ratingsBreakdown: {           // Média por critério
    [criterion: string]: number
  },
  recentReviewsCount: {
    last30Days: number,
    last90Days: number
  },
  lastUpdated: Timestamp
}
```

---

### 🔄 O que precisa ser ADAPTADO (20% do código)

#### 1. **PendingReviews Collection** 
No Advanced-Dating é focado em casamentos (vendor/bride), no Partiu precisa focar em eventos sociais:

```typescript
// ADVANCED-DATING (vendor/bride context)
interface PendingReview {
  announcement_id: string,      // ID do anúncio
  application_id: string,       // ID da candidatura
  reviewer_id: string,
  reviewee_id: string,
  reviewee_role: 'bride' | 'vendor',  // ❌ Não aplicável
  category_name: string,        // Ex: "Fotógrafo", "DJ"
  event_name: string,
  event_date: Timestamp
}

// PARTIU (social events context)
interface PendingReview {
  event_id: string,             // ID do evento
  application_id: string,       // ID da application (EventApplications)
  reviewer_id: string,          // Owner ou participante
  reviewee_id: string,          // Quem será avaliado
  reviewer_role: 'owner' | 'participant', // ✅ Novo campo
  event_title: string,
  event_emoji: string,
  event_location?: string,
  event_date: Timestamp,
  created_at: Timestamp,
  expires_at: Timestamp,        // 7 dias após evento
  dismissed: boolean
}
```

#### 2. **Critérios de Avaliação**

**Advanced-Dating:**
- Para Vendors: pontualidade, postura, comunicação, entrega do briefing, trabalho em equipe
- Para Brides: instruções claras, pagamento em dia, suporte

**Partiu (eventos sociais):**

##### Para Owner avaliar Participantes:
1. ⏰ **Pontualidade** - Chegou no horário combinado?
2. 🤝 **Respeito** - Comportamento adequado durante o evento?
3. 💬 **Comunicação** - Respondeu mensagens e confirmou presença?
4. 🎉 **Energia positiva** - Contribuiu para clima do evento?
5. 🔄 **Comprometimento** - Cumpriu o que prometeu?

##### Para Participante avaliar Owner:
1. 📋 **Organização** - Evento foi bem planejado?
2. 💬 **Comunicação** - Informações claras sobre local/horário?
3. 🎯 **Expectativa** - Evento foi como descrito?
4. 🤝 **Hospitalidade** - Owner foi receptivo e atencioso?

#### 3. **Lógica de Disparo (NOVO - não existe no Advanced-Dating)**

Precisa criar uma **Cloud Function agendada** que:

```typescript
// functions/src/events/checkEventsForReview.ts
export const checkEventsForReview = functions.pubsub
  .schedule('every 1 hours') // Roda a cada hora
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    // Busca eventos que terminaram há 24h
    const events = await admin.firestore()
      .collection('Events')
      .where('schedule.date', '<=', twentyFourHoursAgo)
      .where('reviewsCreated', '==', false) // Flag para não processar 2x
      .get();

    for (const eventDoc of events.docs) {
      await createPendingReviewsForEvent(eventDoc);
    }
  });
```

#### 4. **Fluxo Bidirecional (NOVO)**

No Advanced-Dating, apenas bride avalia vendor (unidirecional).
No Partiu, owner E participantes se avaliam mutuamente:

```typescript
async function createPendingReviewsForEvent(eventDoc: DocumentSnapshot) {
  const eventData = eventDoc.data();
  const eventId = eventDoc.id;
  const ownerId = eventData.createdBy;

  // Busca participantes que marcaram "Eu vou" ou "Talvez"
  const applications = await admin.firestore()
    .collection('EventApplications')
    .where('eventId', '==', eventId)
    .where('status', 'in', ['approved', 'autoApproved'])
    .get();

  const confirmedParticipants = applications.docs.filter(doc => 
    ['Vou', 'Talvez'].includes(doc.data().presence)
  );

  // 1. Cria pending review para OWNER avaliar cada PARTICIPANTE
  for (const participantDoc of confirmedParticipants) {
    const participantId = participantDoc.data().userId;
    
    await admin.firestore().collection('PendingReviews').add({
      event_id: eventId,
      application_id: participantDoc.id,
      reviewer_id: ownerId,           // Owner avalia
      reviewee_id: participantId,     // Participante
      reviewer_role: 'owner',
      event_title: eventData.activityText,
      event_emoji: eventData.emoji,
      event_date: eventData.schedule.date,
      created_at: admin.firestore.Timestamp.now(),
      expires_at: getExpirationDate(7), // 7 dias
      dismissed: false
    });

    // 2. Cria pending review para PARTICIPANTE avaliar OWNER
    await admin.firestore().collection('PendingReviews').add({
      event_id: eventId,
      application_id: participantDoc.id,
      reviewer_id: participantId,     // Participante avalia
      reviewee_id: ownerId,           // Owner
      reviewer_role: 'participant',
      event_title: eventData.activityText,
      event_emoji: eventData.emoji,
      event_date: eventData.schedule.date,
      created_at: admin.firestore.Timestamp.now(),
      expires_at: getExpirationDate(7),
      dismissed: false
    });
  }

  // Marca evento como processado
  await eventDoc.ref.update({ reviewsCreated: true });
}
```

#### 5. **Notificação ao Owner (NOVO)**

Quando o evento passar 24h, notificar o owner:

```typescript
// Envia notificação in-app
await admin.firestore().collection('Notifications').add({
  userId: ownerId,
  type: 'review_request',
  title: 'Hora de avaliar seu evento!',
  message: `Avalie os participantes do evento "${eventData.activityText}"`,
  data: {
    eventId: eventId,
    actionType: 'open_pending_reviews'
  },
  createdAt: admin.firestore.Timestamp.now(),
  read: false
});

// Opcional: Push notification
await sendPushNotification(ownerId, {
  title: '🎉 Avalie seu evento',
  body: `Como foi o evento ${eventData.activityText}? Avalie os participantes!`
});
```

---

## 🎯 Plano de Implementação (Ordem Sugerida)

### Fase 1: Backend (Functions)
1. ✅ Criar estrutura de coleções (PendingReviews, Reviews, ReviewStats)
2. ✅ Criar endpoints HTTP (adaptar de review.ts)
3. ✅ Criar Cloud Function agendada (checkEventsForReview)
4. ✅ Implementar lógica bidirecional (owner ↔ participants)
5. ✅ Sistema de notificações

### Fase 2: Frontend (Flutter)
1. ✅ Copiar pasta review_components/ do Advanced-Dating
2. ✅ Adaptar review_dialog.dart (novos campos: reviewer_role, event_emoji)
3. ✅ Adaptar review_dialog_controller.dart (novos critérios)
4. ✅ Criar ReviewWorkflowService adaptado
5. ✅ Integrar com tela de eventos (botão "Ver avaliações pendentes")

### Fase 3: UX/UI
1. ✅ Tela de pending reviews (lista de eventos para avaliar)
2. ✅ Badge de notificação para reviews pendentes
3. ✅ Perfil do usuário com estatísticas de reviews
4. ✅ Lista de reviews recebidos (histórico)

---

## 📝 Exemplo de Fluxo Completo

1. **Evento acontece** → scheduleDate = 20/12/2024 18:00
2. **24h depois** (21/12/2024 18:00) → Cloud Function detecta
3. **Sistema cria PendingReviews**:
   - Owner → Participante 1
   - Owner → Participante 2
   - Participante 1 → Owner
   - Participante 2 → Owner
4. **Notificação enviada** ao owner e participantes
5. **Owner abre app** → Vê badge "2 avaliações pendentes"
6. **Owner abre modal** → Seleciona Participante 1
7. **Owner avalia** → Pontualidade: 5⭐, Respeito: 5⭐, etc
8. **Review salvo** → Atualiza ReviewStats do Participante 1
9. **Participante 1 abre app** → Vê "Avalie o evento XYZ"
10. **Participante avalia owner** → Ciclo completo!

---

## 🚀 Vantagens do Reaproveitamento

1. **Economia de tempo**: 80% do código já existe e está testado
2. **Consistência**: Mesma UX de reviews em ambos apps
3. **Manutenibilidade**: Bugs corrigidos em um podem ser aplicados no outro
4. **Escalabilidade**: Sistema de cache (ReviewStats) já otimizado

---

## ⚠️ Pontos de Atenção

1. **Duplicatas**: Verificar se já existe review antes de criar
2. **Expiração**: Reviews pendentes expiram em 7 dias
3. **Privacidade**: Reviews são públicos ou apenas para owner?
4. **Moderação**: Implementar sistema de report para reviews ofensivos?
5. **Gamificação**: Integrar com sistema de ranking existente?

---

## 🔗 Arquivos Importantes

### No Advanced-Dating (referência):
- `functions/src/http/routes/review.ts` - Backend completo
- `lib/dialogs/review_dialog.dart` - Modal de avaliação
- `lib/dialogs/review_dialog_controller.dart` - Controller
- `lib/services/review_workflow_service.dart` - Service layer
- `lib/dialogs/review_components/*` - Componentes UI

### No Partiu (a criar/adaptar):
- `functions/src/events/checkEventsForReview.ts` - NOVO
- `functions/src/http/routes/review.ts` - Adaptar
- `lib/features/reviews/*` - Adaptar do Advanced-Dating
- `lib/models/review_model.dart` - Criar
- `lib/models/pending_review_model.dart` - Criar

---

## 📊 Estimativa de Esforço

- **Backend Functions**: 8-12 horas
- **Endpoints HTTP**: 4-6 horas (já tem base)
- **Frontend Flutter**: 6-8 horas (adaptação)
- **Testes e ajustes**: 4-6 horas
- **TOTAL**: ~24-32 horas

Cerca de 1 semana de desenvolvimento para um dev experiente! 🎉
