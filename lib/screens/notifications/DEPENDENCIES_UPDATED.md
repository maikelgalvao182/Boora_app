# ✅ DEPENDÊNCIAS ATUALIZADAS - SISTEMA DE NOTIFICAÇÕES PARTIU

## 📦 Imports Corretos (Partiu)

### Widgets Compartilhados
```dart
import 'package:partiu/shared/widgets/stable_avatar.dart';
import 'package:partiu/shared/widgets/reactive/reactive_user_name_with_badge.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
```

### Constantes
```dart
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/constants.dart';
```

### Utils
```dart
import 'package:partiu/core/utils/app_localizations.dart';
```

### Sistema de Notificações
```dart
import 'package:partiu/models/notification_event.dart';
import 'package:partiu/screens/notifications/repositories/notifications_repository_interface.dart';
import 'package:partiu/screens/notifications/repositories/notifications_repository.dart';
import 'package:partiu/screens/notifications/controllers/simplified_notification_controller.dart';
import 'package:partiu/screens/notifications/helpers/notification_text_sanitizer.dart';
```

## ✅ Constantes Disponíveis

Todas as constantes de notificação já existem em `lib/core/constants/constants.dart`:

```dart
// Campos do Firestore
const N_SENDER_ID = 'n_sender_id';
const N_SENDER_FULLNAME = 'n_sender_fullname';
const N_SENDER_PHOTO_LINK = 'n_sender_photo_link';
const N_RECEIVER_ID = 'n_receiver_id';
const N_TYPE = 'n_type';
const N_PARAMS = 'n_params';
const N_METADATA = 'n_metadata';
const N_READ = 'n_read';
const N_RELATED_ID = 'n_related_id';
const TIMESTAMP = 'timestamp';

// Tipos de notificação
const String NOTIF_TYPE_LIKE = 'like';
const String NOTIF_TYPE_VISIT = 'visit';
const String NOTIF_TYPE_MESSAGE = 'message';

// Feature Flags
const bool NOTIFICATIONS_REQUIRE_VIP_SUBSCRIPTION = true;
```

## ✅ Widgets Disponíveis

### StableAvatar
**Path:** `lib/shared/widgets/stable_avatar.dart`
```dart
StableAvatar(
  userId: senderId,
  size: 42,
  enableNavigation: false,
)
```

### ReactiveUserNameWithBadge
**Path:** `lib/shared/widgets/reactive/reactive_user_name_with_badge.dart`
```dart
ReactiveUserNameWithBadge(
  userId: senderId,
  style: textStyle,
)
```

### GlimpseBackButton
**Path:** `lib/shared/widgets/glimpse_back_button.dart`
```dart
GlimpseBackButton.iconButton(
  onPressed: () => Navigator.pop(context),
  width: 24,
  height: 24,
)
```

### GlimpseColors
**Path:** `lib/core/constants/glimpse_colors.dart`
```dart
GlimpseColors.bgColorLight
GlimpseColors.bgColorDark
GlimpseColors.textColorLight
GlimpseColors.primaryColorLight
GlimpseColors.lightTextField
```

### AppLocalizations
**Path:** `lib/core/utils/app_localizations.dart`
```dart
final i18n = AppLocalizations.of(context);
final text = i18n.translate('key');
```

## 🎯 Status da Migração

### ✅ Arquivos Atualizados (Dependencies OK)
1. ✅ `notification_event.dart` - Usando constantes do Partiu
2. ✅ `notifications_repository_interface.dart` - Sem dependências externas
3. ✅ `notifications_repository.dart` - Firestore direto
4. ✅ `simplified_notification_controller.dart` - Imports corretos
5. ✅ `notification_text_sanitizer.dart` - Sem dependências

### 🔄 Próximos Arquivos (Precisam dos imports acima)
6. ⏳ `notification_message_translator.dart`
7. ⏳ `app_notifications.dart`
8. ⏳ `push_notification_manager.dart`
9. ⏳ Widgets UI (7 arquivos)

## 📝 Notas Importantes

1. **Package Name:** Sempre use `package:partiu/` ao invés de `package:dating_app/`
2. **Paths Partiu:**
   - Shared widgets: `lib/shared/widgets/`
   - Core constants: `lib/core/constants/`
   - Core utils: `lib/core/utils/`
   - Screens: `lib/screens/`
   - Models: `lib/models/`
   - Services: `lib/services/`

3. **Firestore Collection:** Use `'Notifications'` (maiúsculo)

4. **Feature Flags:** O VIP gating está ATIVO por padrão no Partiu (`NOTIFICATIONS_REQUIRE_VIP_SUBSCRIPTION = true`)

## ✅ Ready to Continue

Todas as dependências básicas estão mapeadas e prontas. Podemos prosseguir com:
- Translator simplificado
- Routing simplificado  
- Push notification manager
- Widgets UI
