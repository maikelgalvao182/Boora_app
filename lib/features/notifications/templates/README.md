# 📢 NotificationTemplateEngine - Documentação

## 🎯 O que é?

O **NotificationTemplateEngine** é o sistema centralizado de padronização de mensagens de notificações do Partiu. Todos os textos, títulos e previews de notificações são definidos em um único lugar.

---

## ✅ Benefícios

1. **Padronização Total**: Todas as mensagens seguem o mesmo estilo e tom
2. **Fácil Internacionalização**: No futuro, basta traduzir este arquivo
3. **Menos Bugs**: Triggers apenas passam dados, não montam texto
4. **Consistência**: Push, feed e preview sempre alinhados
5. **Manutenibilidade**: Mudanças de texto em um único lugar

---

## 📁 Estrutura

```
lib/features/notifications/templates/
├── notification_templates.dart    # Engine de templates
└── README.md                      # Esta documentação
```

---

## 🔧 Como Usar

### 1. No Trigger

Em vez de montar o texto manualmente, use o template:

```dart
// ❌ ANTES (montava texto no trigger)
final params = {
  'activityText': activity.name,
  'emoji': activity.emoji,
  'creatorName': creatorInfo['fullName'],
};

await createNotification(
  receiverId: userId,
  type: ActivityNotificationTypes.activityCreated,
  params: params,
  // ...
);
```

```dart
// ✅ AGORA (usa template)
final template = NotificationTemplates.activityCreated(
  creatorName: creatorInfo['fullName'],
  activityName: activity.name,
  emoji: activity.emoji,
  commonInterests: ['Café', 'Viagem'], // opcional
);

await createNotification(
  receiverId: userId,
  type: ActivityNotificationTypes.activityCreated,
  params: {
    'title': template.title,
    'body': template.body,
    'preview': template.preview,
    ...template.extra,
  },
  senderId: activity.createdBy,
  senderName: creatorInfo['fullName'],
  senderPhotoUrl: creatorInfo['photoUrl'],
  relatedId: activity.id,
);
```

---

## 📋 Templates Disponíveis

### 1. `activityCreated`
**Quando**: Nova atividade criada no raio do usuário  
**Título**: `{activityName} {emoji}`  
**Corpo**: `{creatorName} criou esta atividade. Vai participar?`  
**Preview**: `{creatorName} criou uma nova atividade`

```dart
final template = NotificationTemplates.activityCreated(
  creatorName: "Ana",
  activityName: "Correr no parque",
  emoji: "🏃",
  commonInterests: ["Café", "Viagem"], // opcional
);
```

---

### 2. `activityJoinRequest`
**Quando**: Alguém pede para entrar em atividade privada  
**Título**: `{activityName} {emoji}`  
**Corpo**: `{requesterName} pediu para entrar na sua atividade`  
**Preview**: `Novo pedido de entrada`

```dart
final template = NotificationTemplates.activityJoinRequest(
  requesterName: "João",
  activityName: "Pizza e conversa",
  emoji: "🍕",
);
```

---

### 3. `activityJoinApproved`
**Quando**: Dono aprovou entrada na atividade  
**Título**: `{activityName} {emoji}`  
**Corpo**: `Você foi aprovado para participar!`  
**Preview**: `Entrada aprovada 🎉`

```dart
final template = NotificationTemplates.activityJoinApproved(
  activityName: "Café da manhã",
  emoji: "☕",
);
```

---

### 4. `activityJoinRejected`
**Quando**: Dono recusou entrada na atividade  
**Título**: `{activityName} {emoji}`  
**Corpo**: `Seu pedido para entrar foi recusado`  
**Preview**: `Pedido recusado`

```dart
final template = NotificationTemplates.activityJoinRejected(
  activityName: "Jantar exclusivo",
  emoji: "🍽️",
);
```

---

### 5. `activityNewParticipant`
**Quando**: Novo participante entrou (atividade aberta)  
**Título**: `{activityName} {emoji}`  
**Corpo**: `{participantName} entrou na sua atividade!`  
**Preview**: `{participantName} entrou`

```dart
final template = NotificationTemplates.activityNewParticipant(
  participantName: "Maria",
  activityName: "Caminhada",
  emoji: "🚶",
);
```

---

### 6. `activityHeatingUp`
**Quando**: Atividade atingiu threshold de participantes (3, 5 ou 10)  
**Título**: `🔥 Atividade bombando!`  
**Corpo**: `As pessoas estão participando da atividade de {creatorName}! Não fique de fora!`  
**Preview**: `Uma atividade perto de você está bombando 🔥`

```dart
final template = NotificationTemplates.activityHeatingUp(
  activityName: "Show ao vivo",
  emoji: "🎸",
  creatorName: "Pedro",
  participantCount: 5,
);
```

---

### 7. `activityExpiringSoon`
**Quando**: Atividade está quase expirando  
**Título**: `{activityName} {emoji}`  
**Corpo**: `Esta atividade está quase acabando. Última chance!`  
**Preview**: `Atividade quase expirando ⏰`

```dart
final template = NotificationTemplates.activityExpiringSoon(
  activityName: "Happy hour",
  emoji: "🍻",
  hoursRemaining: 2,
);
```

---

### 8. `activityCanceled`
**Quando**: Atividade foi cancelada pelo dono  
**Título**: `{activityName} {emoji}`  
**Corpo**: `Esta atividade foi cancelada`  
**Preview**: `Atividade cancelada 🚫`

```dart
final template = NotificationTemplates.activityCanceled(
  activityName: "Festa surpresa",
  emoji: "🎉",
);
```

---

### 9. `newMessage`
**Quando**: Nova mensagem no chat  
**Título**: `Nova mensagem`  
**Corpo**: `{senderName}: {messagePreview}` ou `{senderName} enviou uma mensagem`  
**Preview**: `Nova mensagem de {senderName}`

```dart
final template = NotificationTemplates.newMessage(
  senderName: "Lucas",
  messagePreview: "Oi, tudo bem?",
);
```

---

### 10. `systemAlert`
**Quando**: Alertas gerais do sistema  
**Título**: `{title}` ou `Partiu` (padrão)  
**Corpo**: `{message}`  
**Preview**: Primeiros 50 caracteres da mensagem

```dart
final template = NotificationTemplates.systemAlert(
  message: "Você recebeu um novo badge!",
  title: "Conquista desbloqueada",
);
```

---

### 11. `custom`
**Quando**: Casos especiais que não se encaixam nos templates  
**Título**: Customizado  
**Corpo**: Customizado  
**Preview**: Customizado ou primeiros 50 caracteres do corpo

```dart
final template = NotificationTemplates.custom(
  title: "Título especial",
  body: "Mensagem especial",
  preview: "Preview curto",
  extra: {'key': 'value'},
);
```

---

## 🎨 Estrutura de NotificationMessage

```dart
class NotificationMessage {
  final String title;       // Título da notificação
  final String body;        // Corpo principal
  final String preview;     // Preview curto para lista
  final Map<String, dynamic> extra;  // Dados extras
}
```

---

## 🔄 Fluxo Completo

```
1. Trigger detecta evento
   ↓
2. Busca dados necessários (usuário, atividade, etc)
   ↓
3. Chama NotificationTemplates.xxx() com parâmetros
   ↓
4. Recebe NotificationMessage estruturado
   ↓
5. Envia para createNotification() com params do template
   ↓
6. Notificação salva no Firestore
   ↓
7. Push enviado via FCM
```

---

## 📝 Checklist para Novo Template

- [ ] Adicionar método estático em `NotificationTemplates`
- [ ] Documentar no `README.md`
- [ ] Definir título, corpo e preview consistentes
- [ ] Adicionar exemplo de uso
- [ ] Atualizar trigger correspondente
- [ ] Testar notificação visual

---

## 🌍 Internacionalização Futura

Quando for necessário traduzir:

1. Substitua strings hardcoded por chaves i18n
2. Mantenha a estrutura de parâmetros dinâmicos
3. Atualize apenas este arquivo

```dart
// Futuro
body: i18n.translate('notification_activity_created', {
  'creatorName': creatorName,
}),
```

---

## 🎯 Boas Práticas

✅ **FAÇA**:
- Use templates para TODAS as notificações
- Passe apenas dados ao template, não texto formatado
- Mantenha consistência de tom e estilo
- Adicione emojis relevantes
- Use preview descritivo e curto

❌ **NÃO FAÇA**:
- Montar texto manualmente no trigger
- Duplicar lógica de formatação
- Misturar idiomas
- Criar texto sem usar template
- Pular campos obrigatórios (title, body, preview)

---

## 📊 Exemplos de Uso Real

### Exemplo 1: Activity Created Trigger

```dart
// activity_created_trigger.dart

@override
Future<void> execute(ActivityModel activity, Map<String, dynamic> context) async {
  final nearbyUsers = await _findUsersInRadius(...);
  final creatorInfo = await getUserInfo(activity.createdBy);

  // Usa template
  final template = NotificationTemplates.activityCreated(
    creatorName: creatorInfo['fullName'],
    activityName: activity.name,
    emoji: activity.emoji,
  );

  // Envia para cada usuário
  for (final userId in nearbyUsers) {
    await createNotification(
      receiverId: userId,
      type: ActivityNotificationTypes.activityCreated,
      params: {
        'title': template.title,
        'body': template.body,
        'preview': template.preview,
        ...template.extra,
      },
      senderId: activity.createdBy,
      senderName: creatorInfo['fullName'],
      senderPhotoUrl: creatorInfo['photoUrl'],
      relatedId: activity.id,
    );
  }
}
```

### Exemplo 2: Join Request Trigger

```dart
// activity_join_request_trigger.dart

@override
Future<void> execute(ActivityModel activity, Map<String, dynamic> context) async {
  final requesterId = context['requesterId'] as String;
  final ownerId = await _getActivityOwner(activity.id);
  final requesterInfo = await getUserInfo(requesterId);

  // Usa template
  final template = NotificationTemplates.activityJoinRequest(
    requesterName: requesterInfo['fullName'],
    activityName: activity.name,
    emoji: activity.emoji,
  );

  // Notifica apenas o dono
  await createNotification(
    receiverId: ownerId,
    type: ActivityNotificationTypes.activityJoinRequest,
    params: {
      'title': template.title,
      'body': template.body,
      'preview': template.preview,
      ...template.extra,
    },
    senderId: requesterId,
    senderName: requesterInfo['fullName'],
    senderPhotoUrl: requesterInfo['photoUrl'],
    relatedId: activity.id,
  );
}
```

---

## 🎓 Perguntas Frequentes

**Q: Preciso adicionar traduções no assets/lang?**  
A: Não neste momento. Os textos estão hardcoded no template. Futuramente, quando internacionalizar, sim.

**Q: Posso customizar o texto de uma notificação específica?**  
A: Use `NotificationTemplates.custom()` para casos especiais.

**Q: Como adiciono interesses comuns no template?**  
A: Use o parâmetro `commonInterests` no `activityCreated()`. O helper `formatInterests()` formata automaticamente.

**Q: O que vai no `extra`?**  
A: Dados adicionais que não aparecem na notificação mas podem ser úteis no app (ex: contadores, listas).

**Q: Posso chamar template direto no UI?**  
A: Não. Templates são para triggers. No UI, leia a notificação salva no Firestore.

---

## ✅ Status da Implementação

- [x] Arquivo `notification_templates.dart` criado
- [x] Template `activityCreated`
- [x] Template `activityJoinRequest`
- [x] Template `activityJoinApproved`
- [x] Template `activityJoinRejected`
- [x] Template `activityNewParticipant`
- [x] Template `activityHeatingUp`
- [x] Template `activityExpiringSoon`
- [x] Template `activityCanceled`
- [x] Template `newMessage`
- [x] Template `systemAlert`
- [x] Template `custom`
- [x] Todos os triggers atualizados
- [x] Documentação completa
- [ ] Testes unitários
- [ ] Internacionalização

---

**Última atualização**: 06/12/2025  
**Responsável**: Sistema de Notificações Partiu  
**Versão**: 1.0.0
