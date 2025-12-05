# Home Screen - Estrutura e Implementação

## 📁 Estrutura de Arquivos Criados

### Telas Principais
- `lib/features/home/presentation/screens/home_screen_refactored.dart` - Tela principal com navegação por tabs
- `lib/features/home/presentation/screens/discover_tab.dart` - Tab de descoberta (placeholder)
- `lib/features/home/presentation/screens/actions_tab.dart` - Tab de ações (placeholder)
- `lib/features/home/presentation/screens/ranking_tab.dart` - Tab de ranking (placeholder)
- `lib/features/home/presentation/screens/conversations_tab.dart` - Tab de conversas (placeholder)
- `lib/features/home/presentation/screens/profile_tab.dart` - Tab de perfil (placeholder)

### Widgets do Home
- `lib/features/home/presentation/widgets/home_app_bar.dart` - AppBar customizado com avatar e ícones
- `lib/features/home/presentation/widgets/home_app_bar_controller.dart` - Controller para gerenciar estado do AppBar
- `lib/features/home/presentation/widgets/home_app_bar_skeleton.dart` - Skeleton loader para o AppBar
- `lib/features/home/presentation/widgets/home_bottom_navigation_bar.dart` - Bottom navigation bar com 5 tabs
- `lib/features/home/presentation/widgets/auto_updating_badge.dart` - Badge de contador para notificações

### Widgets Compartilhados
- `lib/shared/widgets/stable_avatar.dart` - Widget de avatar reativo e otimizado
- `lib/shared/stores/avatar_store.dart` - Store para gerenciar cache de avatares

## 🎨 Estrutura da Home

### 1. HomeScreenRefactored
Tela principal que gerencia:
- **5 tabs** com navegação preservando estado (IndexedStack)
- **Lazy loading** de páginas (carrega apenas quando necessário)
- **AppBar customizado** exibido apenas na tab 0 (Descobrir)
- **Bottom navigation bar** fixo em todas as tabs

### 2. HomeAppBar
AppBar customizado com:
- **Avatar do usuário** com StableAvatar
- **Saudação personalizada** ("Oi, [Nome] 👋")
- **Localização** (Cidade, Estado)
- **Botão de notificações** com badge
- **Botão de filtros**
- **Modo visitante** para usuários não logados

### 3. HomeBottomNavigationBar
Bottom navigation com 5 tabs:
1. **Descobrir** (explore) - Tab principal
2. **Matches** (favorite)
3. **Ranking** (trophy)
4. **Conversas** (chat) - Com badge de mensagens não lidas
5. **Perfil** (person)

## 🔧 Otimizações Implementadas

### Performance
- ✅ **RepaintBoundary** em cada tab para isolar repaints
- ✅ **Lazy loading** de páginas com IndexedStack
- ✅ **Const widgets** para ícones pré-compilados
- ✅ **ValueNotifier** para atualizações reativas eficientes
- ✅ **Gapless playback** em imagens para evitar flicker

### UX
- ✅ **Haptic feedback** ao trocar de tab
- ✅ **Skeleton loading** enquanto carrega dados
- ✅ **AnimatedSwitcher** para transições suaves
- ✅ **Preservação de estado** entre tabs

## 📝 TODOs Pendentes

### Integrações Necessárias
- [ ] Integrar com sistema de autenticação (AppState/UserStore)
- [ ] Implementar carregamento real de avatares do Firebase
- [ ] Conectar contador de notificações com sistema real
- [ ] Conectar contador de mensagens com sistema de chat
- [ ] Implementar navegação para tela de notificações
- [ ] Implementar drawer/modal de filtros

### Funcionalidades das Tabs
- [ ] Implementar tela de descoberta (DiscoverTab)
- [ ] Implementar tela de ações (ActionsTab)
- [ ] Implementar tela de ranking (RankingTab)
- [ ] Implementar tela de conversas (ConversationsTab)
- [ ] Implementar tela de perfil (ProfileTab)

### Melhorias Visuais
- [ ] Adicionar anel de progresso de completude do perfil no avatar
- [ ] Implementar animações de transição entre tabs
- [ ] Adicionar indicador visual de filtros ativos

## 🎯 Como Usar

### Navegação Básica
```dart
// Em qualquer lugar do app, navegue para a home:
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => const HomeScreenRefactored(),
  ),
);

// Ou com índice inicial específico:
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => const HomeScreenRefactored(initialIndex: 2),
  ),
);
```

### Personalização
```dart
// Modificar cor dos ícones:
// Edite _TabIcons em home_bottom_navigation_bar.dart

// Modificar espaçamentos:
// Edite constantes em GlimpseStyles (glimpse_styles.dart)

// Adicionar nova tab:
// 1. Criar nova tela em features/home/presentation/screens/
// 2. Adicionar ícone em _TabIcons
// 3. Adicionar item em HomeBottomNavigationBar
// 4. Adicionar case em _buildPage()
```

## 📦 Dependências Utilizadas

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.2.1  # Para tipografia consistente
```

## 🏗️ Arquitetura

```
HomeScreenRefactored (StatefulWidget)
├── HomeAppBar (apenas tab 0)
│   ├── StableAvatar (com AvatarStore)
│   ├── AutoUpdatingBadge (notificações)
│   └── Filter button
├── IndexedStack (preserva estado)
│   ├── DiscoverTab
│   ├── ActionsTab
│   ├── RankingTab
│   ├── ConversationsTab
│   └── ProfileTab
└── HomeBottomNavigationBar (5 tabs)
    └── MessagesBadge (tab conversas)
```

## 🎨 Design System

### Cores
- `GlimpseColors.primaryColorLight` - Cor principal (preto)
- `GlimpseColors.textSubTitle` - Cinza para texto secundário
- `GlimpseColors.lightTextField` - Fundo claro para skeleton

### Tipografia
- **Font**: Plus Jakarta Sans
- **AppBar Nome**: 16px, Bold (w700)
- **AppBar Localização**: 13px, Medium (w500)
- **Bottom Nav Label**: 12px, Semibold/Regular (w600/w400)

### Espaçamentos
- **Horizontal Margin**: 20px (GlimpseStyles.horizontalMargin)
- **Icon Size**: 24-26px
- **Avatar Size**: 38-44px
- **Tab Spacing**: 2px entre ícone e label

---

**Status**: ✅ Estrutura básica implementada e funcional  
**Próximo passo**: Implementar funcionalidades das tabs individuais
