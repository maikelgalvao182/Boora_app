# Migração para users_preview (perfil básico/light)

## Objetivo
Centralizar **avatar + perfil básico** em `users_preview/{uid}` e substituir leituras diretas de `Users/{uid}` em todas as telas que só precisam de dados leves.

## Schema sugerido (users_preview)
Campos mínimos (alto ROI):
- `userId`
- `displayName` (ou `fullName`)
- `username`
- `photoUrl`
- `avatarThumbUrl`
- `isVerified`
- `locality` (cidade)
- `state` (UF)
- `country`
- `flag`
- `updatedAt`

Campos opcionais (se necessário em cards/feeds):
- `gender`
- `age`
- `distance`
- `lastActiveAt`
- `badge` (quando houver mais de um selo)
- `cityId` (se existir normalização de cidade)
- `vip` / `isVip` (somente se for exibido em cards)

> **Voláteis** (online/status) ficam fora do preview.

## Fonte de verdade
- `Users/{uid}` continua sendo a fonte completa.
- `users_preview/{uid}` é espelho leve, atualizado por Cloud Function.

## Itens do app que precisam trocar para users_preview
### ⚠️ Fonte central (onde mudar primeiro)
- [lib/shared/widgets/stable_avatar.dart](lib/shared/widgets/stable_avatar.dart)
- [lib/shared/widgets/reactive/reactive_user_name_with_badge.dart](lib/shared/widgets/reactive/reactive_user_name_with_badge.dart)
- [lib/shared/widgets/reactive/reactive_user_location.dart](lib/shared/widgets/reactive/reactive_user_location.dart)
- [lib/shared/stores/user_store.dart](lib/shared/stores/user_store.dart)

> Mudando esses pontos, quase toda UI básica passa a ler `users_preview` automaticamente.
### Widgets/telas que exibem avatar/perfil básico
(estes devem consumir `users_preview` diretamente ou via componentes acima)
- [lib/features/home/presentation/widgets/home_app_bar.dart](lib/features/home/presentation/widgets/home_app_bar.dart)
- [lib/features/home/presentation/widgets/user_card.dart](lib/features/home/presentation/widgets/user_card.dart)
- [lib/features/home/presentation/widgets/list_card.dart](lib/features/home/presentation/widgets/list_card.dart)
- [lib/features/home/presentation/widgets/people_ranking_card.dart](lib/features/home/presentation/widgets/people_ranking_card.dart)
- [lib/features/home/presentation/widgets/event_card/event_card.dart](lib/features/home/presentation/widgets/event_card/event_card.dart)
- [lib/features/home/presentation/widgets/event_card/widgets/participants_avatars_list.dart](lib/features/home/presentation/widgets/event_card/widgets/participants_avatars_list.dart)
- [lib/dialogs/report_user_dialog.dart](lib/dialogs/report_user_dialog.dart)
- [lib/features/profile/presentation/dialogs/profile_completeness_dialog.dart](lib/features/profile/presentation/dialogs/profile_completeness_dialog.dart)
- [lib/features/notifications/widgets/notification_item_widget.dart](lib/features/notifications/widgets/notification_item_widget.dart)
- [lib/screens/chat/chat_screen_refactored.dart](lib/screens/chat/chat_screen_refactored.dart)
- [lib/features/home/presentation/widgets/map_controllers/marker_assets.dart](lib/features/home/presentation/widgets/map_controllers/marker_assets.dart)
- [lib/features/home/presentation/screens/profile_tab.dart](lib/features/home/presentation/screens/profile_tab.dart)
- [lib/features/conversations/widgets/conversation_tile.dart](lib/features/conversations/widgets/conversation_tile.dart)
- [lib/features/notifications/widgets/notification_item_widget.dart](lib/features/notifications/widgets/notification_item_widget.dart)
- [lib/features/profile/presentation/screens/edit_profile_screen_advanced.dart](lib/features/profile/presentation/screens/edit_profile_screen_advanced.dart)
- [lib/features/profile/presentation/screens/blocked_users_screen.dart](lib/features/profile/presentation/screens/blocked_users_screen.dart)

### Fluxo de feed / criação de post (event_photo_feed)
- [lib/features/event_photo_feed/presentation/screens/event_photo_feed_screen.dart](lib/features/event_photo_feed/presentation/screens/event_photo_feed_screen.dart)
- [lib/features/event_photo_feed/presentation/screens/event_photo_composer_screen.dart](lib/features/event_photo_feed/presentation/screens/event_photo_composer_screen.dart)
- [lib/features/event_photo_feed/presentation/widgets/event_photo_feed_item.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_feed_item.dart)
- [lib/features/event_photo_feed/presentation/widgets/event_photo_header.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_header.dart)
- [lib/features/event_photo_feed/presentation/widgets/event_photo_composer_header.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_composer_header.dart)
- [lib/features/event_photo_feed/presentation/widgets/comment_header.dart](lib/features/event_photo_feed/presentation/widgets/comment_header.dart)
- [lib/features/event_photo_feed/presentation/widgets/event_photo_participant_selector_sheet.dart](lib/features/event_photo_feed/presentation/widgets/event_photo_participant_selector_sheet.dart)
- [lib/features/event_photo_feed/presentation/widgets/tagged_participants_avatars.dart](lib/features/event_photo_feed/presentation/widgets/tagged_participants_avatars.dart)

### Fluxos com avatar/identidade em listas
- Cards de participantes (eventos)
- Cards de pessoas (ranking/discover)
- Avatares em chat + notificações
- Widgets de denúncia/bloqueio
- Lista de conversas (Conversations)
- Notificações (Notifications)
- Aba de perfil (Profile tab)
- Edição de perfil (Edit profile)

### Serviços/Helpers que podem depender de Users
- Resolvedores de avatar via UserStore
- Widgets reativos que escutam Users para nome/localização

## Observações
- O foco é **evitar leituras de Users** quando só precisamos de avatar/nome/localidade.
- Após a migração, apenas telas de **perfil completo** e fluxos que exigem dados extensos devem ler `Users/{uid}`.
- Onde hoje existe fallback para `UserStore` (ex.: nome), trocar para `users_preview`.

## Checklist técnico (para migração segura)
1) **Schema final** + campos obrigatórios fechados.
2) **Cloud Function**: espelho `Users/{uid}` → `users_preview/{uid}`.
3) **Backfill**: job 1x para popular preview dos usuários existentes.
4) **Atualizar components base** (`StableAvatar`, `ReactiveUserNameWithBadge`, `ReactiveUserLocation`, `UserStore`).
5) **Auditar telas** acima e remover leituras de `Users` quando só precisa perfil básico.
6) **Telemetria**: medir redução de reads/bytes em Profile + Home.

## Próximos passos
1) Definir schema final e campos obrigatórios.
2) Implementar Cloud Function de espelho `Users/{uid} -> users_preview/{uid}`.
3) Trocar componentes/shared widgets para ler `users_preview`.
4) Auditar e substituir usos diretos de `Users` em UI básica.
