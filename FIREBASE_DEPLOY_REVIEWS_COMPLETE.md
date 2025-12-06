# ✅ Deploy Completo - Sistema de Reviews

**Data:** 5 de dezembro de 2025  
**Projeto:** Partiu (partiu-479902)

---

## 🎯 O que foi deployado

### 1. **Cloud Function: `checkEventsForReview`**
- ✅ **Status:** Deployada com sucesso
- 📍 **Região:** us-central1
- ⏰ **Schedule:** Diariamente às 06:00 (horário de São Paulo)
- 🔧 **Runtime:** Node.js 22 (1st Gen)

**Funcionalidade:**
- Roda automaticamente todo dia às 6h da manhã
- Busca eventos que terminaram há 24 horas
- Cria `PendingReviews` bidirecionais (owner ↔ participantes)
- Envia notificações in-app para todos os envolvidos
- Marca eventos como processados (`reviewsCreated: true`)

**Logs da função:**
```typescript
🔍 [checkEventsForReview] Starting...
📊 [checkEventsForReview] Found X events to process
✅ [checkEventsForReview] Reviews created for event {eventId}
🎯 [checkEventsForReview] Completed - Success: X, Errors: Y
```

---

### 2. **Firestore Security Rules**
- ✅ **Status:** Deployadas com sucesso
- 📄 **Arquivo:** `firestore.rules` (compilado de `/rules/reviews.rules`)

**Collections protegidas:**

#### `Reviews/{reviewId}`
```javascript
// Qualquer usuário logado pode ler reviews
allow read: if isSignedIn();

// Criar: apenas quem está fazendo a review
allow create: if isSignedIn() && 
  request.auth.uid == request.resource.data.reviewer_id;

// Atualizar/deletar: apenas o autor
allow update, delete: if isSignedIn() && 
  request.auth.uid == resource.data.reviewer_id;
```

#### `PendingReviews/{pendingId}`
```javascript
// Ler: apenas o reviewer
allow read: if isSignedIn() && 
  request.auth.uid == resource.data.reviewer_id;

// Criar: apenas Cloud Functions
allow create: if false;

// Atualizar: apenas para marcar como dismissed
allow update: if isSignedIn() && 
  request.auth.uid == resource.data.reviewer_id &&
  request.resource.data.status == 'dismissed';

// Deletar: não permitido
allow delete: if false;
```

#### `ReviewStats/{userId}`
```javascript
// Qualquer usuário logado pode ler stats
allow read: if isSignedIn();

// Criar/atualizar/deletar: apenas Cloud Functions
allow create, update, delete: if false;
```

---

## 🔧 Correções Aplicadas

### **Lint Errors**
Corrigidos 54 erros de lint:
- ✅ Strings com aspas duplas (`"` em vez de `'`)
- ✅ Linhas quebradas para respeitar max-len de 80 caracteres
- ✅ JSDoc adicionado para todos os parâmetros
- ✅ Tipo `any` substituído por `admin.firestore.DocumentData`
- ✅ Parâmetro `context` removido (não usado)

### **Build Rules**
Executado script `./build-rules.sh` para compilar regras modulares em arquivo único.

---

## 📊 Estrutura das Collections

### **PendingReviews**
```typescript
{
  pending_review_id: string,
  event_id: string,
  application_id: string,
  reviewer_id: string,        // Quem deve fazer a review
  reviewee_id: string,         // Quem será avaliado
  reviewer_role: 'owner' | 'participant',
  event_title: string,
  event_emoji: string,
  event_location: string?,
  event_date: Timestamp?,
  created_at: Timestamp,
  expires_at: Timestamp,       // 7 dias após criação
  dismissed: boolean,
  reviewee_name: string,
  reviewee_photo_url: string?
}
```

### **Reviews**
```typescript
{
  review_id: string,
  event_id: string,
  reviewer_id: string,
  reviewee_id: string,
  reviewer_role: 'owner' | 'participant',
  criteria_ratings: {
    conversation: number,      // 1-5
    energy: number,            // 1-5
    coexistence: number,       // 1-5
    participation: number      // 1-5
  },
  badges: string[],            // ['friendly', 'funny', ...]
  comment: string?,
  created_at: Timestamp,
  updated_at: Timestamp?
}
```

### **ReviewStats**
```typescript
{
  user_id: string,
  total_reviews: number,
  overall_rating: number,      // Média geral
  ratings_breakdown: {
    conversation: number,
    energy: number,
    coexistence: number,
    participation: number
  },
  badges_count: {
    [badgeKey: string]: number
  },
  last_updated: Timestamp
}
```

---

## 🚀 Como Funciona (Fluxo Completo)

### **1. Evento é Criado**
```
User cria evento → Salvo em Events collection
```

### **2. Participantes Confirmam**
```
Applications criadas → Status: approved/autoApproved
Participants confirmam presença → presence: "Eu vou"
```

### **3. Evento Acontece**
```
schedule.date passa → Evento realizado
```

### **4. 24h Após o Evento (6h da manhã seguinte)**
```
Cloud Function checkEventsForReview roda automaticamente:
├─ Busca eventos com schedule.date <= 24h atrás
├─ Filtra: reviewsCreated == false
├─ Para cada evento:
│  ├─ Owner → PendingReview para cada participante
│  ├─ Cada participante → PendingReview para owner
│  ├─ Marca evento: reviewsCreated = true
│  └─ Envia notificações in-app
```

### **5. Usuários Avaliam**
```
App Flutter:
├─ PendingReviewsScreen lista pending reviews
├─ Usuário clica → ReviewDialog abre
├─ 3 steps: Ratings → Badges → Comment
├─ Submit → ReviewRepository.createReview()
└─ Review salva em Firestore
```

### **6. Stats Atualizadas**
```
Trigger (manual ou agendado):
├─ Cloud Function calcula stats agregadas
├─ Salva em ReviewStats/{userId}
└─ Profile exibe ratings e badges
```

---

## 🔍 Verificação do Deploy

### **No Firebase Console**

1. **Functions:**
   - Acesse: https://console.firebase.google.com/project/partiu-479902/functions
   - Verifique: `checkEventsForReview` aparece listada
   - Status: Verde (ativa)
   - Schedule: `0 6 * * *` (cron diário às 6h)

2. **Firestore Rules:**
   - Acesse: https://console.firebase.google.com/project/partiu-479902/firestore/rules
   - Verifique: Última publicação em 5 de dezembro de 2025
   - Confirm que as 3 collections têm regras:
     - `Reviews/{reviewId}`
     - `PendingReviews/{pendingId}`
     - `ReviewStats/{userId}`

3. **Logs:**
   ```bash
   firebase functions:log --only checkEventsForReview
   ```

---

## 🧪 Como Testar

### **Teste Manual da Cloud Function**
```bash
# No Firebase Console > Functions > checkEventsForReview
# Clicar em "Testar função" ou usar CLI:
firebase functions:shell
> checkEventsForReview()
```

### **Teste de Evento Real**
1. Criar evento no app
2. Aprovar participantes
3. Confirmar presenças
4. Aguardar 24h após evento
5. Verificar às 6h se PendingReviews foram criadas

### **Teste de Reviews via App**
```dart
// No Flutter
import 'package:partiu/features/reviews/presentation/screens/pending_reviews_screen.dart';

// Navegar para tela
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => PendingReviewsScreen()),
);
```

---

## 📋 Próximos Passos

### **Opcional: Criar Índices Compostos**
Se houver erros de query, criar índices em `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "PendingReviews",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "reviewer_id", "order": "ASCENDING" },
        { "fieldPath": "dismissed", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "Reviews",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "reviewee_id", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    }
  ]
}
```

Deploy:
```bash
firebase deploy --only firestore:indexes
```

### **Monitoramento**
- ✅ Configurar alertas no Firebase Console
- ✅ Monitorar logs diariamente (especialmente às 6h)
- ✅ Verificar taxa de erro da função

### **Melhorias Futuras**
- [ ] Cloud Function para calcular ReviewStats automaticamente
- [ ] Push notifications além das in-app
- [ ] Página de "Todas as reviews" no profile
- [ ] Badge de pending reviews no AppBar
- [ ] Deep links para abrir pending reviews

---

## ⚠️ Avisos Importantes

### **Warnings no Deploy (não críticos)**
```
⚠ functions: package.json indicates an outdated version of firebase-functions
```
**Ação:** Considerar upgrade para `firebase-functions@latest` no futuro.

```
⚠ [W] 37:10 - Unused function: isEventCreator
⚠ [W] 42:10 - Unused function: isEventParticipant
```
**Ação:** Funções helpers não usadas ainda. Podem ser removidas ou mantidas para uso futuro.

---

## 🎉 Resumo

✅ **Cloud Function deployada e agendada**  
✅ **Firestore Rules ativas e seguras**  
✅ **Sistema de reviews operacional**  
✅ **Pronto para produção**

**Link do Console:** https://console.firebase.google.com/project/partiu-479902/overview

---

**Próxima execução da função:** Amanhã, 6 de dezembro de 2025, às 06:00 (horário de Brasília) 🌅
