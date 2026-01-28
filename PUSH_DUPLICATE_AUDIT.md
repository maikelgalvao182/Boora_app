# 🧾 Auditoria — Push Duplicado (Flutter + FCM)

Data: 28/01/2026

Escopo analisado:
- Client Flutter: [lib/features/notifications/services/push_notification_manager.dart](lib/features/notifications/services/push_notification_manager.dart), [lib/features/notifications/services/fcm_token_service.dart](lib/features/notifications/services/fcm_token_service.dart), [lib/main.dart](lib/main.dart)
- iOS AppDelegate: [ios/Runner/AppDelegate.swift](ios/Runner/AppDelegate.swift)
- Cloud Functions: [functions/src/services/pushDispatcher.ts](functions/src/services/pushDispatcher.ts), [functions/src/activityPushNotifications.ts](functions/src/activityPushNotifications.ts), [functions/src/activityNotifications.ts](functions/src/activityNotifications.ts), [functions/src/chatPushNotifications.ts](functions/src/chatPushNotifications.ts), [functions/src/eventChatNotifications.ts](functions/src/eventChatNotifications.ts), [functions/src/reviews/reviewNotifications.ts](functions/src/reviews/reviewNotifications.ts), [functions/src/index.ts](functions/src/index.ts), [functions/src/profileViewNotifications.ts](functions/src/profileViewNotifications.ts), [functions/src/users/followSystem.ts](functions/src/users/followSystem.ts)

> Observação: não há evidência direta de “duplicação real” nos logs aqui. Abaixo estão respostas baseadas no código + pontos que exigem confirmação em logs/telemetria.

---

## A) Definição do problema (pra não caçar fantasma)

O “duplicado” é:
- ⬜ duas notificações idênticas no tray (central do sistema)
- ⬜ uma notificação no tray + outra dentro do app (in-app)
- ⬜ duas vezes o mesmo deep link / navegação ao tocar
- ⬜ duplicado só no Android
- ⬜ duplicado só no iOS

Acontece quando o app está:
- ⬜ foreground
- ⬜ background
- ⬜ killed
- ⬜ qualquer estado

O duplicado aparece:
- ⬜ sempre
- ⬜ só às vezes (ex: 1/10)
- ⬜ depois de hot reload / restart

O duplicado é sempre do mesmo “tipo” (ex: activity_created)?
- ⬜ sim
- ⬜ não

**Nota de auditoria:** não dá para inferir esse bloco apenas pelo código. É necessário validar com logs de entrega do FCM e logs do app.

---

## B) Origem do disparo (quem está mandando 2 pushes)

Esse push é disparado por:
- ⬜ Firebase Console (manual)
- ✅ Cloud Functions (trigger Firestore / HTTP / onCall)
- ⬜ Backend próprio (Nest, etc.)
- ⬜ ambos / não tenho certeza

**Evidências:** envios via `sendPush()` em múltiplas funções e envio direto via Admin Messaging em follow system.

Você tem mais de um lugar que pode disparar o mesmo push para o mesmo evento?
- ✅ sim (lista abaixo)
- ⬜ não

**Locais identificados:**
- Atividades via Notifications → push: [functions/src/activityPushNotifications.ts](functions/src/activityPushNotifications.ts)
- Criação de Notifications in-app: [functions/src/activityNotifications.ts](functions/src/activityNotifications.ts)
- Chat 1-1: [functions/src/chatPushNotifications.ts](functions/src/chatPushNotifications.ts)
- Chat de evento: [functions/src/eventChatNotifications.ts](functions/src/eventChatNotifications.ts)
- Reviews: [functions/src/reviews/reviewNotifications.ts](functions/src/reviews/reviewNotifications.ts)
- Profile views agregadas: [functions/src/profileViewNotifications.ts](functions/src/profileViewNotifications.ts)
- Activity new participant (push direto): [functions/src/index.ts](functions/src/index.ts)
- Follow system (via dispatcher): [functions/src/users/followSystem.ts](functions/src/users/followSystem.ts)

O push é disparado em onCreate e também em onUpdate do mesmo documento?
- ⬜ sim
- ✅ não (para Notifications; há onWrite/onUpdate em EventApplications)
- ⬜ não sei

Existe algum fluxo que “cria” e logo em seguida “atualiza” o documento (ex: set + patch status)?
- ✅ sim (EventApplications muda status e possui múltiplos triggers)
- ⬜ não

A function tem proteção de idempotência (ex: grava um notificationId enviado e não reenvia)?
- ✅ sim (parcial) → `push_sent` em Notifications
- ⬜ não

**Evidência:** [functions/src/activityPushNotifications.ts](functions/src/activityPushNotifications.ts)

Você tem mais de uma function observando a mesma coleção (ou caminhos parecidos)?
- ✅ sim (EventApplications)
- ⬜ não

**Evidências:**
- onWrite: [functions/src/index.ts](functions/src/index.ts)
- onWrite: [functions/src/activityNotifications.ts](functions/src/activityNotifications.ts)
- onUpdate: [functions/src/activityNotifications.ts](functions/src/activityNotifications.ts)

Você tem retries automáticos no backend/function (timeout, erro, 5xx)?
- ⬜ sim
- ⬜ não
- ✅ não sei (não há configuração explícita no código)

Você consegue confirmar nos logs do servidor/function se houve duas execuções para o mesmo eventId/notificationId?
- ⬜ sim
- ✅ não (não encontrei confirmação no repositório)

---

## C) Estrutura do payload (causa duplicação no device)

Seu payload usa:
- ✅ notification + data (padrão)
- ✅ só data (quando `silent` ou `dataOnly`)
- ⬜ só notification

**Evidência:** [functions/src/services/pushDispatcher.ts](functions/src/services/pushDispatcher.ts)

Quando você envia notification e também cria notificação local no app, você sabe que isso pode duplicar?
- ✅ já considerei (há dedupe por `n_origin` e iOS guard)
- ⬜ não

No Android, você usa flutter_local_notifications pra exibir no foreground?
- ✅ sim
- ⬜ não

**Evidência:** [lib/features/notifications/services/push_notification_manager.dart](lib/features/notifications/services/push_notification_manager.dart)

No iOS, você exibe manualmente no foreground e o iOS também está apresentando?
- ⬜ sim
- ✅ não (se `notification` existe, não exibe local)
- ⬜ não sei

Você seta setForegroundNotificationPresentationOptions(alert: true, ...)?
- ✅ sim
- ⬜ não

**Evidência:** [lib/features/notifications/services/push_notification_manager.dart](lib/features/notifications/services/push_notification_manager.dart)

Se sim: você também mostra notificação local no onMessage?
- ✅ apenas para data-only
- ⬜ não

---

## D) Handlers do app (onde o mesmo push é processado duas vezes)

Onde você registra listeners?
- ✅ FirebaseMessaging.onMessage.listen
- ✅ FirebaseMessaging.onMessageOpenedApp.listen
- ✅ getInitialMessage()
- ✅ flutterLocalNotificationsPlugin.initialize(onDidReceiveNotificationResponse...)
- ✅ notificationTapBackground(...)

Você garante que cada listener é registrado uma única vez durante a vida do app?
- ✅ sim (inicialização única com guard)
- ⬜ não
- ⬜ não sei

**Evidências:**
- Inicialização única: [lib/main.dart](lib/main.dart)
- Handlers: [lib/features/notifications/services/push_notification_manager.dart](lib/features/notifications/services/push_notification_manager.dart)

Esse código de registro roda em:
- ⬜ main() (ideal)
- ✅ initState() de um widget (AppBootstrap) com guard `_didBootstrap`
- ⬜ dentro de Provider/Riverpod que pode recriar

Você já logou um “ID do listener” (hash) pra ver se ele foi registrado 2x?
- ⬜ sim
- ✅ não

O app cria notificação local no onMessage e também trata onMessageOpenedApp para navegar:
- ✅ sim
- ⬜ não

Você já confirmou se o duplicado é “duas exibições” ou “duas navegações”?
- ⬜ exibição
- ⬜ navegação
- ⬜ ambos

---

## E) Notificação local (maior causa de duplicação em Flutter)

Você chama show() no flutter_local_notifications com um id fixo?
- ⬜ sim
- ✅ não (usa `stableKey` por evento/relatedId)

Você está usando message.messageId.hashCode como id local?
- ⬜ sim
- ✅ não

Você chama show() mais de uma vez para o mesmo message (ex: em dois serviços diferentes)?
- ⬜ sim
- ✅ não evidente no código
- ⬜ não sei

Você tem mais de um “notification service” (ex: AppNotifications + FirebaseMessagingBackgroundHandler) mostrando local?
- ✅ sim (foreground + background dentro do mesmo PushNotificationManager)
- ⬜ não

No Android, você tem canal configurado e o importance/high certinho?
- ✅ sim
- ⬜ não

---

## F) Logs e rastreio (pra achar o ponto exato)

Você loga sempre estes campos quando chega push?
- ✅ messageId
- ✅ sentTime
- ✅ data
- ✅ notification.title/body
- ⬜ collapseKey (não logado)

Você tem um pushTraceId único no payload (ex: traceId)?
- ⬜ sim
- ✅ não

Você consegue responder:
“o mesmo messageId chegou 2x?”
- ⬜ sim
- ✅ não (precisa log agregado)

“vieram messageIds diferentes mas com mesmo eventId?”
- ⬜ sim
- ✅ não (precisa log agregado)

---

## G) Firestore/Evento (causas clássicas quando não é token)

O push é disparado por evento em Firestore (trigger)?
- ✅ sim
- ⬜ não

O documento que dispara o push sofre múltiplas escritas rápidas (ex: cria → adiciona participantes → atualiza status)?
- ✅ sim (EventApplications + Events)
- ⬜ não

Você tem algum processo que escreve o mesmo doc duas vezes (ex: app + cloud function pós-processando)?
- ✅ sim (EventApplications e Events recebem writes de app + functions)
- ⬜ não
- ⬜ não sei

Você usa “fan-out” (escreve notificações em vários docs) que pode acionar mais de uma trigger?
- ✅ sim (criação de Notifications em batch + trigger de push)
- ⬜ não

---

# ✅ Achados principais (prováveis causas de duplicação)

1) **Múltiplas fontes de envio**
   - Há vários emissores de push dependendo do evento (chat, activity, review, profile views, follow).
   - Para alguns fluxos, o push é enviado diretamente (sem in-app) e para outros via Notifications + trigger.

2) **Coleções com múltiplos triggers**
   - `EventApplications` tem pelo menos três listeners (onWrite/onUpdate), podendo gerar efeitos colaterais em cascata.

3) **Payload híbrido (notification + data)**
   - No iOS, o banner é mostrado pelo SO quando há `notification` e `alert:true`.
   - O app só mostra local em data-only, o que está correto, mas qualquer duplicidade no backend vira duplicidade visual no tray.

4) **Sem traceId/UUID único no payload**
   - Falta `traceId` para rastrear duplicidade cross-sistema. Hoje o dedupe é por `messageId` ou payload.

---

# ✅ Checklist rápido: provar duplicação real vs exibição

- ⬜ O mesmo `messageId` chegou 2x no app?
- ⬜ Chegaram `messageId` diferentes com o mesmo `relatedId/eventId`?
- ⬜ As duas notificações aparecem no tray com segundos de diferença?
- ⬜ O duplicado só acontece em foreground?

# ✅ Ajuste obrigatório: rastreio 1:1 + idempotência no envio

## Payload mínimo recomendado (em TODOS os envios)

- `traceId` (UUID por tentativa de envio)
- `idempotencyKey` (determinístico)
- `origin` (nome da função que disparou)
- `n_type` (já existe)
- `relatedId/eventId` (já existe)

## Como montar `idempotencyKey`

Formato sugerido:

```
$nType:$relatedId:$recipientUserId:$variant
```

Exemplos:

```
activity_created:AkKqaME3:user123:v1
chat_message:chat987:user123:v1
```

Se duas funções tentarem enviar o “mesmo” push, elas vão gerar o mesmo `idempotencyKey`.

# ✅ Recomendações mínimas (diagnóstico + prova)

- ✅ **Adicionar `traceId`, `idempotencyKey`, `origin` no payload** em [functions/src/services/pushDispatcher.ts](functions/src/services/pushDispatcher.ts).
- ✅ **Logar `collapseKey`, `messageId`, `traceId`, `idempotencyKey` no app** em [lib/features/notifications/services/push_notification_manager.dart](lib/features/notifications/services/push_notification_manager.dart).
- ⬜ **Consolidar logs com `messageId + idempotencyKey + n_type`** para confirmar duplicação real.

Se quiser, preparo um patch com:
- ✅ `traceId`/`idempotencyKey` no dispatcher
- ✅ logs completos no cliente
- ✅ idempotência real no envio (Firestore cache por `idempotencyKey`)

# ✅ Hotspots — checklist com evidências do código

## 🔥 Hotspot 1: EventApplications com múltiplos listeners

Listeners identificados:
- onWrite em [functions/src/index.ts](functions/src/index.ts) (onApplicationApproved)
- onWrite em [functions/src/activityNotifications.ts](functions/src/activityNotifications.ts) (onActivityHeatingUp)
- onUpdate em [functions/src/activityNotifications.ts](functions/src/activityNotifications.ts) (onJoinDecisionNotification)

Checklist:
- ⬜ Existe trigger A que cria Notification + trigger B que também manda push direto no mesmo evento?
   - **Não encontrei** um par explícito para o MESMO `n_type`. O push direto em `onApplicationApproved` é `activity_new_participant`, enquanto as Notifications criadas em `activityNotifications` geram outros tipos.

- ✅ Um update (ex: status) está causando 2 caminhos: “approved” e “activity_created/heating_up”?
   - **Sim, potencialmente**: `EventApplications` aprovada dispara **onApplicationApproved** (push direto) e **onActivityHeatingUp** (cria Notifications → push) quando atinge thresholds. Não é o mesmo tipo/recipiente, mas são múltiplos caminhos a partir do mesmo write.

- ✅ Um onWrite está tratando “create” e “update” no mesmo handler sem diferenciar before.exists/after.exists?
   - **Sim** em `onApplicationApproved` e `onActivityHeatingUp` (ambos são onWrite). Eles diferenciam via `before/after`, mas tratam create+update no mesmo handler, o que exige idempotência global.

Conclusão do hotspot:
- Sem idempotência global, esse ponto pode duplicar em cenários de retry e múltiplos caminhos por write.

## 🔥 Hotspot 2: fan-out de Notifications + trigger de push

Checklist:
- ⬜ Algum fluxo manda push direto e também escreve Notification?
   - **Sim (mesmo fluxo)**: `followSystem` cria Notification e envia push (agora via dispatcher). Ver [functions/src/users/followSystem.ts](functions/src/users/followSystem.ts).
   - **Sim (mesmo fluxo)**: `profileViewNotifications` cria Notifications e também envia push (agora via dispatcher). Ver [functions/src/profileViewNotifications.ts](functions/src/profileViewNotifications.ts).

- ✅ O mesmo “evento” gera dois Notification docs diferentes (ex: “activity_created” + “activity_heating_up” mas com texto muito parecido)?
   - **Sim** em atividades: `activity_created` e `activity_heating_up` são eventos distintos, mas podem parecer duplicados ao usuário. Ambos criam docs em Notifications e geram push via [functions/src/activityPushNotifications.ts](functions/src/activityPushNotifications.ts).

Conclusão do hotspot:
- O risco não é o Notifications trigger em si, mas **fluxos paralelos** que enviam push direto para o mesmo usuário e, ao mesmo tempo, criam Notifications em lote.

# ✅ Auditoria linha‑a‑linha (foco em duplicação)

## Novo seguidor (`new_follower`)

Arquivo: [functions/src/users/followSystem.ts](functions/src/users/followSystem.ts)

- **Única origem de push** para `new_follower`:
   - `followUser` → `sendNewFollowerPush()` → `sendPush()`.
- **Sem trigger adicional** em Notifications para `new_follower`.
- **Transação** impede duplicação lógica de follow:
   - se `followingDoc` existe → status `already_following` → **não envia push**.
- **Conclusão**: duplicação de `new_follower` **não é causada por múltiplas functions**.
   - Causas mais prováveis: **duas chamadas do cliente** ou **mais de um token válido** no `DeviceTokens` para o mesmo device.

## EventApplications (múltiplos listeners)

Arquivos:
- [functions/src/index.ts](functions/src/index.ts) (`onApplicationApproved`)
- [functions/src/activityNotifications.ts](functions/src/activityNotifications.ts) (`onActivityHeatingUp`, `onJoinDecisionNotification`)

Achados:
- `onApplicationApproved` (onWrite) envia **`activity_new_participant`** para o criador do evento.
- `onActivityHeatingUp` (onWrite) cria Notifications **`activity_heating_up`** para usuários no raio quando bate threshold.
- `onJoinDecisionNotification` (onUpdate) cria Notifications **`activity_join_approved/rejected`** para o solicitante.

**Conclusão:** múltiplos handlers no mesmo write, mas **tipos/recipientes distintos**. Não há duplicação explícita do **mesmo** push nesse fluxo.

# ✅ Checklist final de auditoria (com prova)

Após implementar `idempotencyKey` + `push_receipts`, para cada duplicado você consegue responder:

- ⬜ `idempotencyKey` igual? (mesmo evento percebido)
- ⬜ `origin` diferente? (duas funções tentando enviar)
- ⬜ `traceId` diferente? (duas tentativas distintas)
- ⬜ `push_receipts` criado por qual `origin`? (quem venceu a corrida)

Com isso, a causa fica objetiva e rastreável em 1–2 dias.
