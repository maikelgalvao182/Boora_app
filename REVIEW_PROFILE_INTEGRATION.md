# 🎯 Integração do Novo Sistema de Reviews no Profile

## 📋 O que foi criado

### 1. **Novos Widgets Compatíveis**

#### ✅ `ReviewCardV2` (`review_card_v2.dart`)
- **Substitui:** `ReviewCard` antigo
- **Novo modelo:** `ReviewModel` de `/lib/features/reviews/`
- **Features:**
  - Display de critérios unificados (💬 Papo, ⚡ Energia, 🤝 Convivência, 🎯 Participação)
  - Badges de elogios (😄 Simpático, 😂 Engraçado, 🧠 Inteligente, etc.)
  - Comentário expandível
  - Avatar e nome reativos com `ReactiveUserNameWithBadge`
  - Data formatada (Hoje, Ontem, X dias atrás)

#### ✅ `ReviewStatsSection` (`review_stats_section.dart`)
- **Substitui:** `ReviewsHeader` antigo
- **Novo modelo:** `ReviewStatsModel`
- **Features:**
  - Overall rating com estrelas
  - Total de reviews
  - Breakdown por critério com barra de progresso
  - Top 3 badges mais recebidos com contador

#### ✅ `ProfileContentBuilderV2` (`profile_content_builder_v2.dart`)
- **Substitui:** `ProfileContentBuilder` antigo
- **Integração:** Usa `ReviewRepository` diretamente
- **Features:**
  - Streams reativos (watchUserStats + watchUserReviews)
  - Mostra até 5 reviews recentes
  - Botão "Ver todas" se tiver mais de 5
  - Mantém compatibilidade com seções antigas (AboutMe, Gallery, etc.)

---

## 🔄 Como Integrar no Profile

### **Opção 1: Substituição Gradual (Recomendado)**

Manter os dois sistemas durante migração:

```dart
// Em profile_screen_optimized.dart

import 'package:partiu/features/profile/presentation/components/profile_content_builder_v2.dart'; // 🆕

// No método _buildContent():
Widget _buildContent(bool myProfile) {
  return CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      CupertinoSliverRefreshControl(/* ... */),
      
      SliverToBoxAdapter(
        child: ValueListenableBuilder<User?>(
          valueListenable: _controller.profile,
          builder: (context, profile, _) {
            final displayUser = profile ?? widget.user;

            return ProfileContentBuilderV2( // 🔄 Trocar aqui
              controller: _controller,
              displayUser: displayUser,
              myProfile: myProfile,
              i18n: _i18n,
              currentUserId: widget.currentUserId,
            ).build(); // ← Remover .build() pois agora é StatefulWidget
          },
        ),
      ),
    ],
  );
}
```

### **Opção 2: Migração Completa**

Remover sistema antigo:

1. ❌ **Deletar:**
   - `/lib/core/models/review_model.dart` (modelo antigo)
   - `/lib/features/profile/presentation/widgets/review_card.dart`
   - `/lib/features/profile/presentation/widgets/reviews_header.dart`
   - `/lib/features/home/presentation/screens/review/*` (pasta antiga)

2. ✅ **Atualizar:**
   - `profile_screen_optimized.dart` usar `ProfileContentBuilderV2`
   - Remover imports antigos de review

---

## 📊 Comparação: Antigo vs Novo

| Feature | Sistema Antigo | Sistema Novo ✅ |
|---------|----------------|-----------------|
| **Modelo** | `Review` com `announcementId` | `ReviewModel` com `event_id` |
| **Critérios** | Diferentes por user role | 4 unificados para todos |
| **Badges** | ❌ Não tinha | ✅ 7 badges com emoji |
| **Repository** | HTTP API | Firestore direto |
| **State** | ValueNotifier no controller | Streams reativos |
| **UI** | `ReviewCard` + `ReviewsHeader` | `ReviewCardV2` + `ReviewStatsSection` |

---

## 🚀 Checklist de Integração

### 1. **Atualizar ProfileScreen**
```bash
# Trocar ProfileContentBuilder por ProfileContentBuilderV2
✅ Import correto
✅ Remover .build() (agora é StatefulWidget)
✅ Testar navegação
```

### 2. **Testar Funcionalidades**
```bash
✅ Profile exibe stats agregadas
✅ Reviews aparecem com badges
✅ Critérios unificados funcionam
✅ Botão "Ver todas" aparece (se > 5)
✅ Pull-to-refresh atualiza reviews
```

### 3. **Migrar Dados (Opcional)**
Se já existem reviews antigas no Firestore:

```typescript
// Cloud Function para migrar reviews
async function migrateOldReviews() {
  const oldReviews = await db.collection('reviews')
    .where('announcementId', '!=', null)
    .get();

  for (const doc of oldReviews.docs) {
    const old = doc.data();
    
    await db.collection('reviews').doc(doc.id).update({
      event_id: old.announcementId, // ← renomear campo
      criteria_ratings: {
        conversation: old.detailedRatings?.communication || 0,
        energy: old.detailedRatings?.energy || 0,
        coexistence: old.detailedRatings?.coexistence || 0,
        participation: old.detailedRatings?.participation || 0,
      },
      badges: [], // ← inicializar vazio
      reviewer_role: 'participant', // ← definir role padrão
    });
  }
}
```

---

## 🎨 Exemplo Visual

### Antes (Sistema Antigo):
```
┌─────────────────────────────┐
│ ⭐ 4.5 - João Silva         │
│ "Ótimo profissional"        │
│ [Ratings antigos]           │
└─────────────────────────────┘
```

### Depois (Sistema Novo): ✨
```
┌─────────────────────────────────────┐
│ 📊 Avaliações                       │
│ ⭐ 4.8 ★★★★★ (12 avaliações)        │
│                                     │
│ 💬 Papo & Conexão    ████████░ 4.9 │
│ ⚡ Energia & Presença ███████░░ 4.7 │
│ 🤝 Convivência       █████████ 5.0 │
│ 🎯 Participação      ████████░ 4.6 │
│                                     │
│ Elogios mais recebidos:             │
│ [😄 Mega simpático 8]               │
│ [🎉 Anima todo mundo 5]             │
│ [🧠 Muito inteligente 3]            │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 👤 Maria Santos    ⭐ 4.9          │
│ 2 dias atrás                        │
│                                     │
│ [😄 Mega simpático]                 │
│ [🎉 Anima todo mundo]               │
│                                     │
│ 💬 Papo ★★★★★                       │
│ ⚡ Energia ★★★★★                    │
│ 🤝 Convivência ★★★★★                │
│ 🎯 Participação ★★★★☆               │
│                                     │
│ "Pessoa incrível! Super alto        │
│  astral e sempre participa..."      │
│  [Ver mais]                         │
└─────────────────────────────────────┘
```

---

## 🔧 Troubleshooting

### Problema: "Reviews não aparecem no profile"
**Solução:**
```dart
// Verificar se ReviewRepository está inicializado
final repo = ReviewRepository();
final stats = await repo.getUserStats(userId);
print('Total reviews: ${stats.totalReviews}');
```

### Problema: "Badges não aparecem"
**Solução:**
```dart
// Verificar se ReviewBadge.fromKey() está retornando corretamente
import 'package:partiu/features/reviews/domain/constants/review_badges.dart';

final badge = ReviewBadge.fromKey('funny');
print(badge?.emoji); // Deve printar 😂
```

### Problema: "Erro de tipo no ReviewModel"
**Solução:**
```dart
// Garantir que está importando o modelo NOVO
import 'package:partiu/features/reviews/data/models/review_model.dart'; // ✅

// NÃO usar:
// import 'package:partiu/core/models/review_model.dart'; // ❌ Antigo
```

---

## 📚 Próximos Passos

1. ✅ **Integração básica** - Usar `ProfileContentBuilderV2`
2. ⏳ **Tela de todas as reviews** - Criar `AllReviewsScreen`
3. ⏳ **Badge no AppBar** - Mostrar pending reviews
4. ⏳ **Deep links** - Navegação direta para reviews
5. ⏳ **Notificações push** - Alertar sobre novas reviews

---

## 🎯 Conclusão

**Widgets antigos (`review_card.dart`, `reviews_header.dart`) NÃO podem ser totalmente reaproveitados** devido à incompatibilidade de modelos.

**Solução criada:**
- ✅ `ReviewCardV2` - Novo card compatível
- ✅ `ReviewStatsSection` - Nova seção de stats
- ✅ `ProfileContentBuilderV2` - Integração completa

**Para usar:**
```dart
// Trocar em profile_screen_optimized.dart
ProfileContentBuilderV2(/* ... */) // 🆕 Usar este
```

---

**Status:** Pronto para integração! 🚀
