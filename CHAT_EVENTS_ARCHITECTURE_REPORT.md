# 📊 Relatório: Arquitetura de Chat para Eventos Multiusuários

## 🔍 Análise da Arquitetura Atual

### 1. **Sistema de Conversas Existente** (1-to-1)

#### Estrutura Firestore:
```
Connections/{userId}/Conversations/{otherUserId}
  ├─ user_id: string (ID do outro usuário)
  ├─ fullname: string
  ├─ user_profile_photo: string
  ├─ last_message: string
  ├─ message_type: string
  ├─ message_read: boolean
  └─ timestamp: timestamp

Messages/{userId}/{otherUserId}/{messageId}
  ├─ message: string
  ├─ sender_id: string
  ├─ receiver_id: string
  ├─ message_type: string
  ├─ timestamp: timestamp
  ├─ read: boolean
  └─ ... (outros campos)
```

**Características:**
- ✅ Sistema peer-to-peer (1-to-1)
- ✅ Cada usuário tem sua própria subcoleção de conversas
- ✅ Messages armazena mensagens bilaterais
- ❌ **NÃO suporta grupos/multiusuários nativamente**

---

## 🎯 Sistema de Eventos com Applications

### Estrutura Atual:

```
events/{eventId}
  ├─ activityText: string
  ├─ emoji: string
  ├─ createdBy: string (userId do criador)
  ├─ participants.privacyType: "open" | "private"
  └─ ...

EventApplications/{applicationId}
  ├─ eventId: string (referência ao evento)
  ├─ userId: string (participante aplicado)
  ├─ status: "pending" | "approved" | "rejected" | "autoApproved"
  ├─ appliedAt: timestamp
  └─ decisionAt: timestamp?
```

**Cloud Function Existente:**
- ✅ `onEventCreated` → Cria automaticamente application `autoApproved` para o criador

---

## 🚨 PROBLEMA IDENTIFICADO

### ❌ Incompatibilidade Arquitetural:

1. **Connections/Messages** = Estrutura **peer-to-peer** (1-to-1)
2. **Eventos** = Estrutura **multiusuário** (1-to-N)

**Usar o mesmo ID entre `EventApplications` e `Connections/Messages` NÃO FAZ SENTIDO:**
- `Connections/{userId}/Conversations/{otherUserId}` espera **1 outro usuário**
- Eventos têm **N participantes aprovados**

---

## ✅ SOLUÇÃO RECOMENDADA: Chat de Grupo Dedicado

### Arquitetura Proposta:

```
EventChats/{eventId}
  ├─ eventId: string (referência ao evento)
  ├─ createdBy: string (criador do evento)
  ├─ createdAt: timestamp
  ├─ lastMessage: string
  ├─ lastMessageAt: timestamp
  ├─ lastMessageSenderId: string
  ├─ participantIds: array<string> (IDs dos aprovados)
  └─ participantCount: number

EventChats/{eventId}/Messages/{messageId}
  ├─ senderId: string
  ├─ senderName: string
  ├─ senderPhotoUrl: string
  ├─ message: string
  ├─ messageType: "text" | "image" | "location"
  ├─ timestamp: timestamp
  └─ readBy: array<string> (userIds que leram)

EventChats/{eventId}/Participants/{userId}
  ├─ userId: string
  ├─ fullName: string
  ├─ photoUrl: string
  ├─ joinedAt: timestamp
  ├─ lastReadAt: timestamp
  └─ unreadCount: number
```

---

## 🔧 Implementação por Etapas

### **FASE 1: Cloud Function - Criar Chat ao Criar Evento**

**Trigger:** `events/{eventId}.onCreate`

```typescript
export const onEventCreated = functions.firestore
  .document("events/{eventId}")
  .onCreate(async (snap, context) => {
    const eventId = context.params.eventId;
    const eventData = snap.data();
    const creatorId = eventData.createdBy;

    const batch = admin.firestore().batch();

    // 1. Criar application do criador (JÁ EXISTE ✅)
    const applicationRef = admin.firestore()
      .collection("EventApplications").doc();
    
    batch.set(applicationRef, {
      eventId: eventId,
      userId: creatorId,
      status: "autoApproved",
      appliedAt: admin.firestore.FieldValue.serverTimestamp(),
      decisionAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Criar EventChat (NOVO 🆕)
    const chatRef = admin.firestore()
      .collection("EventChats").doc(eventId); // ID do chat = ID do evento
    
    batch.set(chatRef, {
      eventId: eventId,
      createdBy: creatorId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessage: "",
      lastMessageAt: null,
      lastMessageSenderId: null,
      participantIds: [creatorId], // Criador é o primeiro participante
      participantCount: 1,
    });

    // 3. Adicionar criador como participante (NOVO 🆕)
    const participantRef = chatRef.collection("Participants").doc(creatorId);
    
    // Buscar dados do criador
    const creatorDoc = await admin.firestore()
      .collection("Users").doc(creatorId).get();
    
    const creatorData = creatorDoc.data() || {};
    
    batch.set(participantRef, {
      userId: creatorId,
      fullName: creatorData.fullName || "",
      photoUrl: creatorData.photoUrl || "",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastReadAt: admin.firestore.FieldValue.serverTimestamp(),
      unreadCount: 0,
    });

    await batch.commit();
  });
```

---

### **FASE 2: Cloud Function - Adicionar Participante ao Chat**

**Trigger:** `EventApplications/{applicationId}.onUpdate`

```typescript
export const onApplicationApproved = functions.firestore
  .document("EventApplications/{applicationId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Detectar mudança de status para approved ou autoApproved
    const wasApproved = 
      (before.status !== "approved" && after.status === "approved") ||
      (before.status !== "autoApproved" && after.status === "autoApproved");

    if (!wasApproved) return;

    const eventId = after.eventId;
    const userId = after.userId;

    const batch = admin.firestore().batch();

    // 1. Atualizar EventChat com novo participante
    const chatRef = admin.firestore()
      .collection("EventChats").doc(eventId);
    
    batch.update(chatRef, {
      participantIds: admin.firestore.FieldValue.arrayUnion(userId),
      participantCount: admin.firestore.FieldValue.increment(1),
    });

    // 2. Adicionar participante à subcoleção
    const participantRef = chatRef.collection("Participants").doc(userId);
    
    // Buscar dados do usuário
    const userDoc = await admin.firestore()
      .collection("Users").doc(userId).get();
    
    const userData = userDoc.data() || {};
    
    batch.set(participantRef, {
      userId: userId,
      fullName: userData.fullName || "",
      photoUrl: userData.photoUrl || "",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastReadAt: admin.firestore.FieldValue.serverTimestamp(),
      unreadCount: 0,
    });

    await batch.commit();
  });
```

---

### **FASE 3: Flutter - Repository para EventChat**

**Arquivo:** `lib/features/home/data/repositories/event_chat_repository.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class EventChatRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  EventChatRepository([FirebaseFirestore? firestore, FirebaseAuth? auth])
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Busca dados do chat do evento
  Future<Map<String, dynamic>?> getEventChat(String eventId) async {
    try {
      final doc = await _firestore
          .collection('EventChats')
          .doc(eventId)
          .get();
      
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('❌ Erro ao buscar chat do evento: $e');
      return null;
    }
  }

  /// Stream de mensagens do chat do evento
  Stream<QuerySnapshot<Map<String, dynamic>>> getEventMessages(String eventId) {
    return _firestore
        .collection('EventChats')
        .doc(eventId)
        .collection('Messages')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Envia mensagem no chat do evento
  Future<void> sendMessage({
    required String eventId,
    required String message,
    String messageType = 'text',
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Usuário não autenticado');

    // Buscar dados do usuário
    final userDoc = await _firestore.collection('Users').doc(userId).get();
    final userData = userDoc.data() ?? {};

    final batch = _firestore.batch();

    // 1. Adicionar mensagem
    final messageRef = _firestore
        .collection('EventChats')
        .doc(eventId)
        .collection('Messages')
        .doc();

    batch.set(messageRef, {
      'senderId': userId,
      'senderName': userData['fullName'] ?? '',
      'senderPhotoUrl': userData['photoUrl'] ?? '',
      'message': message,
      'messageType': messageType,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': [userId], // Sender já leu (enviou)
    });

    // 2. Atualizar lastMessage no chat
    final chatRef = _firestore.collection('EventChats').doc(eventId);
    
    batch.update(chatRef, {
      'lastMessage': message,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': userId,
    });

    // 3. Atualizar lastReadAt do sender
    final senderParticipantRef = chatRef
        .collection('Participants')
        .doc(userId);
    
    batch.update(senderParticipantRef, {
      'lastReadAt': FieldValue.serverTimestamp(),
      'unreadCount': 0,
    });

    await batch.commit();
  }

  /// Marca mensagens como lidas
  Future<void> markAsRead(String eventId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _firestore
        .collection('EventChats')
        .doc(eventId)
        .collection('Participants')
        .doc(userId)
        .update({
      'lastReadAt': FieldValue.serverTimestamp(),
      'unreadCount': 0,
    });
  }

  /// Busca participantes do chat
  Future<List<Map<String, dynamic>>> getParticipants(String eventId) async {
    try {
      final snapshot = await _firestore
          .collection('EventChats')
          .doc(eventId)
          .collection('Participants')
          .orderBy('joinedAt')
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar participantes: $e');
      return [];
    }
  }
}
```

---

### **FASE 4: Firestore Security Rules**

**Adicionar ao `firestore.rules`:**

```javascript
//
// 💬 Coleção de chats de eventos (multiusuário)
//
match /EventChats/{eventId} {
  // Qualquer participante aprovado pode ler o chat
  allow read: if isSignedIn() && 
    request.auth.uid in resource.data.participantIds;
  
  // Apenas Cloud Functions podem criar/atualizar o documento principal
  allow write: if false;

  // Mensagens dentro do chat
  match /Messages/{messageId} {
    // Qualquer participante pode ler mensagens
    allow read: if isSignedIn() && 
      request.auth.uid in get(/databases/$(database)/documents/EventChats/$(eventId)).data.participantIds;
    
    // Qualquer participante pode enviar mensagens
    allow create: if isSignedIn() && 
      request.auth.uid in get(/databases/$(database)/documents/EventChats/$(eventId)).data.participantIds &&
      request.resource.data.senderId == request.auth.uid;
    
    // Não pode editar/deletar mensagens (opcional: permitir delete do próprio sender)
    allow update, delete: if false;
  }

  // Participantes do chat
  match /Participants/{userId} {
    // Cada participante pode ler todos os outros
    allow read: if isSignedIn() && 
      request.auth.uid in get(/databases/$(database)/documents/EventChats/$(eventId)).data.participantIds;
    
    // Cada participante pode atualizar apenas seu próprio documento (lastReadAt, unreadCount)
    allow update: if isSignedIn() && 
      request.auth.uid == userId &&
      request.auth.uid in get(/databases/$(database)/documents/EventChats/$(eventId)).data.participantIds;
    
    // Apenas Cloud Functions podem criar/deletar participantes
    allow create, delete: if false;
  }
}
```

---

## 🎯 Fluxo Completo

### **1. Criação do Evento:**
```
User cria evento
  ↓
Cloud Function: onEventCreated
  ↓
Cria: EventApplications (status: autoApproved) ✅
Cria: EventChats/{eventId} ✅
Cria: EventChats/{eventId}/Participants/{creatorId} ✅
```

### **2. Aplicação de Outros Usuários:**
```
User aplica ao evento
  ↓
EventApplicationRepository.createApplication()
  ↓
Status determinado (open → autoApproved, private → pending)
  ↓
Se autoApproved: Cloud Function onApplicationApproved
  ↓
Adiciona userId ao EventChats/{eventId}.participantIds
Cria EventChats/{eventId}/Participants/{userId}
```

### **3. Acesso ao Chat:**
```
User clica em "Entrar no chat" (isApproved = true)
  ↓
EventCard.onActionPressed()
  ↓
Navega para EventChatScreen (eventId: eventId)
  ↓
EventChatRepository.getEventMessages(eventId)
  ↓
Stream de mensagens renderizado
```

---

## 📊 Comparação: ID Único vs Estrutura Dedicada

| Aspecto | Reusar Connections/Messages | EventChats Dedicado |
|---------|----------------------------|---------------------|
| **Arquitetura** | ❌ Incompatível (1-to-1 vs 1-to-N) | ✅ Projetado para grupos |
| **Escalabilidade** | ❌ Limitado a 2 participantes | ✅ Suporta N participantes |
| **Queries** | ❌ Complexo filtrar por evento | ✅ eventId como raiz |
| **Security Rules** | ❌ Difícil validar multiusuário | ✅ Validação clara |
| **Manutenção** | ❌ Código misturado | ✅ Separação de responsabilidades |
| **Unread Count** | ❌ Global (todas conversas) | ✅ Por evento |
| **Future Features** | ❌ Difícil adicionar (reactions, threads) | ✅ Extensível |

---

## 🚀 Recomendação Final

### ✅ **IMPLEMENTAR EVENTCHATS SEPARADO**

**Justificativas:**
1. **Separação de responsabilidades**: Conversas 1-to-1 ≠ Chats de grupo
2. **Escalabilidade**: Eventos podem ter centenas de participantes
3. **Performance**: Queries otimizadas por `eventId`
4. **Manutenção**: Código isolado e testável
5. **Segurança**: Rules específicas para contexto de eventos

### ❌ **NÃO REUSAR CONNECTIONS/MESSAGES**

**Problemas:**
- Incompatibilidade estrutural (peer-to-peer vs grupo)
- Dificuldade em manter `participantIds` sincronizado
- Security rules extremamente complexas
- Confusão entre "conversas privadas" e "chats de eventos"

---

## 📝 Checklist de Implementação

### Backend (Cloud Functions):
- [ ] Atualizar `onEventCreated` para criar EventChat
- [ ] Criar `onApplicationApproved` para adicionar participantes
- [ ] Criar `onApplicationRejected` para remover participantes (opcional)

### Frontend (Flutter):
- [ ] Criar `EventChatRepository`
- [ ] Criar `EventChatScreen` (UI de chat)
- [ ] Criar `EventChatController` (ChangeNotifier)
- [ ] Integrar navegação no `EventCard` (botão "Entrar no chat")
- [ ] Adicionar badge de unread count nos eventos

### Firestore:
- [ ] Adicionar Security Rules para `EventChats`
- [ ] Criar índices compostos (se necessário)
- [ ] Testar rules no Rules Playground

### Testes:
- [ ] Testar criação de evento + chat
- [ ] Testar aplicação aprovada → adição ao chat
- [ ] Testar envio/recebimento de mensagens
- [ ] Testar unread count por participante
- [ ] Testar permissões (usuário não aprovado não vê chat)

---

## 📚 Referências de Arquitetura

### Coleções Relacionadas:
```
events/{eventId}                          ← Dados do evento
EventApplications/{applicationId}         ← Quem aplicou
EventChats/{eventId}                      ← Chat do evento (1-to-1 com evento)
EventChats/{eventId}/Messages/{messageId} ← Mensagens do grupo
EventChats/{eventId}/Participants/{userId} ← Metadata de participantes
```

### Sincronização Automática:
- **Cloud Functions garantem consistência** entre `EventApplications.status=approved` e `EventChats.participantIds`
- **Security Rules garantem acesso** apenas para `participantIds`
- **Frontend apenas consome** dados sincronizados pelo backend

---

## 🔔 ADENDO: Mensagem Automática vs Botão Manual

### Pergunta: "Ao invés de botão, disparar mensagem automática?"

#### ✅ **RESPOSTA: SIM, MENSAGEM AUTOMÁTICA É MELHOR**

### Comparação de Abordagens:

| Aspecto | Botão "Entrar no chat" | Mensagem Automática |
|---------|------------------------|---------------------|
| **UX** | ❌ Requer ação manual | ✅ Notificação instantânea |
| **Descoberta** | ❌ User pode não clicar | ✅ User sempre sabe do chat |
| **Engajamento** | ⚠️ Baixo (precisa lembrar) | ✅ Alto (push notification) |
| **Visibilidade** | ❌ Chat "escondido" até clicar | ✅ Aparece na lista de conversas |
| **Consistência** | ⚠️ Diferente de outros chats | ✅ Igual a conversas normais |

---

### 🎯 Solução Recomendada: HÍBRIDA

**Combinar os dois:**
1. ✅ Mensagem automática de boas-vindas (todos recebem)
2. ✅ Botão "Ver chat do evento" (acesso direto)

---

### 📨 Implementação: Mensagem Automática

#### **Cloud Function Atualizada: onApplicationApproved**

```typescript
export const onApplicationApproved = functions.firestore
  .document("EventApplications/{applicationId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    const wasApproved = 
      (before.status !== "approved" && after.status === "approved") ||
      (before.status !== "autoApproved" && after.status === "autoApproved");

    if (!wasApproved) return;

    const eventId = after.eventId;
    const userId = after.userId;

    // Buscar dados do evento e usuário em paralelo
    const [eventDoc, userDoc] = await Promise.all([
      admin.firestore().collection("events").doc(eventId).get(),
      admin.firestore().collection("Users").doc(userId).get(),
    ]);

    const eventData = eventDoc.data() || {};
    const userData = userDoc.data() || {};
    const userName = userData.fullName || "Alguém";
    const activityText = eventData.activityText || "evento";

    const batch = admin.firestore().batch();

    // 1. Atualizar EventChat com novo participante
    const chatRef = admin.firestore()
      .collection("EventChats").doc(eventId);
    
    batch.update(chatRef, {
      participantIds: admin.firestore.FieldValue.arrayUnion(userId),
      participantCount: admin.firestore.FieldValue.increment(1),
    });

    // 2. Adicionar participante à subcoleção
    const participantRef = chatRef.collection("Participants").doc(userId);
    
    batch.set(participantRef, {
      userId: userId,
      fullName: userName,
      photoUrl: userData.photoUrl || "",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastReadAt: null, // Ainda não leu nada (novo)
      unreadCount: 0, // Será incrementado pela mensagem de boas-vindas
    });

    // 3. 🆕 CRIAR MENSAGEM AUTOMÁTICA DE BOAS-VINDAS
    const welcomeMessageRef = chatRef.collection("Messages").doc();
    
    batch.set(welcomeMessageRef, {
      senderId: "system", // ID especial para mensagens do sistema
      senderName: "Sistema",
      senderPhotoUrl: "",
      message: `${userName} entrou no grupo! 🎉`,
      messageType: "system", // Tipo especial
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      readBy: [], // Ninguém leu ainda (incluindo quem entrou)
    });

    // 4. 🆕 ATUALIZAR lastMessage NO CHAT
    batch.update(chatRef, {
      lastMessage: `${userName} entrou no grupo! 🎉`,
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessageSenderId: "system",
    });

    await batch.commit();

    // 5. 🆕 ENVIAR PUSH NOTIFICATION PARA TODOS OS PARTICIPANTES
    // (Exceto quem acabou de entrar)
    const chatSnapshot = await chatRef.get();
    const participantIds = (chatSnapshot.data()?.participantIds || [])
      .filter((id: string) => id !== userId); // Excluir quem entrou

    if (participantIds.length > 0) {
      // Buscar tokens FCM dos participantes
      const tokensPromises = participantIds.map((id: string) =>
        admin.firestore().collection("Users").doc(id).get()
      );
      
      const userDocs = await Promise.all(tokensPromises);
      const tokens = userDocs
        .map(doc => doc.data()?.fcmToken)
        .filter(token => token); // Remover nulls

      if (tokens.length > 0) {
        await admin.messaging().sendMulticast({
          tokens: tokens,
          notification: {
            title: activityText,
            body: `${userName} entrou no grupo! 🎉`,
          },
          data: {
            type: "event_chat",
            eventId: eventId,
            chatId: eventId,
          },
        });
      }
    }
  });
```

---

### 🎨 UI: Botão "Ver chat" ao invés de "Entrar"

**Atualização no EventCard:**

```dart
/// Texto do botão baseado no estado
String get buttonText {
  if (isCreator) return 'Ver participantes';
  if (isApplying) return 'Aplicando...';
  if (isApproved) return 'Ver chat do grupo'; // 🆕 Mudança
  if (isPending) return 'Aguardando aprovação';
  if (isRejected) return 'Aplicação rejeitada';
  return privacyType == 'open' ? 'Participar' : 'Solicitar participação';
}
```

---

### 📊 Experiência do Usuário

#### Fluxo Completo:

```
1. User aplica ao evento
   ↓
2. Status muda para "approved" ou "autoApproved"
   ↓
3. Cloud Function:
   - Adiciona ao EventChats/{eventId}.participantIds ✅
   - Cria Participants/{userId} ✅
   - Cria mensagem: "{Nome} entrou no grupo! 🎉" ✅
   - Atualiza lastMessage no chat ✅
   - Envia push notification para outros participantes ✅
   ↓
4. User recebe notificação (se estava offline)
   ↓
5. User abre app:
   - Vê badge de unread no EventCard
   - Vê chat na lista de conversas (ConversationsTab)
   - Clica em "Ver chat do grupo" → Abre chat
```

---

### ❓ "Todos os demais users do grupo vão receber?"

#### ✅ **SIM, E ISSO É BOM!**

**Por quê?**
1. **Transparência**: Todos sabem quem está no grupo
2. **Contexto**: Facilita saber quando novos membros entraram
3. **Engajamento**: Incentiva dar boas-vindas

**Alternativas (se quiser silencioso):**

#### Opção A: Mensagem Silenciosa (sem notificação)
```typescript
// Não enviar push notification
// Apenas criar mensagem no Firestore
// Users veem quando abrirem o chat naturalmente
```

#### Opção B: Apenas para o Novo Usuário
```typescript
// Criar mensagem privada só para ele:
const welcomeMessageRef = chatRef.collection("Messages").doc();

batch.set(welcomeMessageRef, {
  senderId: "system",
  message: `Bem-vindo ao grupo! Você está participando do evento "${activityText}"`,
  messageType: "system",
  timestamp: admin.firestore.FieldValue.serverTimestamp(),
  readBy: [],
  visibleTo: [userId], // 🆕 Campo especial: só ele vê
});
```

**Security Rule para visibleTo:**
```javascript
match /EventChats/{eventId}/Messages/{messageId} {
  allow read: if isSignedIn() && 
    request.auth.uid in get(/databases/$(database)/documents/EventChats/$(eventId)).data.participantIds &&
    (
      !("visibleTo" in resource.data) || // Mensagem pública
      request.auth.uid in resource.data.visibleTo // Mensagem privada para ele
    );
}
```

---

### 🏆 Recomendação Final

#### ✅ **USAR MENSAGEM AUTOMÁTICA PÚBLICA**

**Implementar:**
1. ✅ Mensagem "{Nome} entrou no grupo! 🎉" visível para todos
2. ✅ Push notification para participantes existentes
3. ✅ Chat aparece automaticamente na lista de conversas do novo user
4. ✅ Botão muda de "Entrar no chat" → "Ver chat do grupo"

**Benefícios:**
- Reduz fricção (user não precisa lembrar de clicar)
- Aumenta engajamento (notificação ativa)
- Consistência UX (igual a outros chats)
- Transparência (todos sabem quem está no grupo)

**Tipos de Mensagens do Sistema:**
```typescript
// Possíveis mensagens automáticas:
- "{Nome} entrou no grupo! 🎉"          ← Novo participante
- "{Nome} criou o evento"                ← Evento criado
- "O evento começa em 1 hora! ⏰"        ← Lembrete
- "O evento foi atualizado"              ← Edição do evento
- "O evento foi cancelado"               ← Cancelamento
```

---

### 📋 Checklist Atualizado

#### Backend:
- [ ] Atualizar `onApplicationApproved` para criar mensagem automática
- [ ] Adicionar envio de push notification multicast
- [ ] Criar sistema de mensagens `type: "system"`
- [ ] (Opcional) Implementar `visibleTo` para mensagens privadas

#### Frontend:
- [ ] Mudar botão de "Entrar no chat" → "Ver chat do grupo"
- [ ] Adicionar badge de unread no EventCard
- [ ] Renderizar mensagens do sistema com estilo diferente
- [ ] Tratar notificação `type: "event_chat"` no FCM handler

#### Firestore:
- [ ] Atualizar Security Rules para suportar `senderId: "system"`
- [ ] (Opcional) Adicionar suporte a `visibleTo` nas rules

---

**Data do Relatório:** 3 de dezembro de 2025  
**Última Atualização:** 3 de dezembro de 2025  
**Status:** ✅ Proposta Completa + Adendo Mensagem Automática - Pronto para Implementação
