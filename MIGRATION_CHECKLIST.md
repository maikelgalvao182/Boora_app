# 📋 CHECKLIST DE MIGRAÇÃO - CONVERSATION_TAB + WEBSOCKET

## 📊 RESUMO GERAL
- **Total de arquivos identificados**: ~70+ arquivos
- **Arquivos migrados**: ~60 arquivos
- **Status**: 🟢 Backend Completo (85% concluído)

---

## ✅ FASE 1: MODELS (2/2 arquivos - 100%)

- [x] `lib/features/conversations/models/conversation_item.dart`
- [x] `lib/features/conversations/models/message.dart`

---

## ✅ FASE 2: SERVICES (5/5 arquivos - 100%)

- [x] `lib/features/conversations/services/conversation_cache_service.dart`
- [x] `lib/features/conversations/services/conversation_state_service.dart`
- [x] `lib/features/conversations/services/conversation_navigation_service.dart`
- [x] `lib/features/conversations/services/conversation_pagination_service.dart`
- [x] `lib/features/conversations/services/conversation_data_processor.dart`

---

## 🔲 FASE 3: WIDGETS (0/4 arquivos - 0%)

### Arquivos pendentes:
- [ ] `lib/features/conversations/widgets/conversation_tile.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/widgets/conversation_tile.dart`
  - **Dependências**: StableAvatar, ReactiveUserNameWithBadge, AvatarMemoryCache, ChatService
  
- [ ] `lib/features/conversations/widgets/conversation_stream_widget.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/widgets/conversation_stream_widget.dart`
  - **Dependências**: ConversationsList, ConversationTile
  
- [ ] `lib/features/conversations/widgets/conversations_header.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/widgets/conversations_header.dart`
  - **Dependências**: SlidingSearchIconButton, GlimpseStyles
  
- [ ] `lib/features/conversations/widgets/conversations_list.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/widgets/conversations_list.dart`
  - **Dependências**: Nenhuma (usa apenas Flutter core)

---

## 🔲 FASE 4: UI & STATE (0/4 arquivos - 0%)

### UI Principal:
- [ ] `lib/features/conversations/ui/conversations_tab.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/ui/conversations_tab.dart`
  - **Dependências**: ConversationsViewModel, ConversationStreamWidget, ConversationsHeader

### State Management:
- [ ] `lib/features/conversations/state/conversations_viewmodel.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/state/conversations_viewmodel.dart`
  - **Dependências**: Todos os services, ChangeNotifier, Provider
  
- [ ] `lib/features/conversations/state/conversations_tab_wrapper.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/state/conversations_tab_wrapper.dart`
  - **Dependências**: ConversationsViewModel, Provider
  
- [ ] `lib/features/conversations/state/optimistic_removal_bus.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/state/optimistic_removal_bus.dart`
  - **Dependências**: StreamController

---

## 🔲 FASE 5: UTILS & AUXILIARES (0/3 arquivos - 0%)

- [ ] `lib/features/conversations/utils/conversation_styles.dart`
  - **Fonte**: `Advanced-Dating/lib/screens/conversation_tab/utils/conversation_styles.dart`
  - **Dependências**: GlimpseColors, EdgeInsets
  
- [ ] `lib/features/conversations/repositories/conversation_repository.dart`
  - **Fonte**: `Advanced-Dating/lib/repositories/cache/conversation_repository.dart`
  - **Dependências**: Cache services
  
- [ ] `lib/features/conversations/api/conversations_api.dart`
  - **Fonte**: `Advanced-Dating/lib/api/conversations_api.dart`
  - **Dependências**: Firestore, HTTP

---

## ✅ FASE 6: WEBSOCKET SERVICES FLUTTER (2/2 arquivos - 100%)

- [x] `lib/core/services/socket_service.dart`
  - **Fonte**: `Advanced-Dating/lib/services/socket_service.dart`
  - **Tamanho**: ~450 linhas
  - **Dependências**: socket_io_client, FirebaseAuth
  - **Observação**: ✅ Lógica completa de reconexão e autenticação preservada
  - **Mudanças**: Apenas imports (AppLogger → print)
  
- [x] `lib/core/services/websocket_messages_service.dart`
  - **Fonte**: `Advanced-Dating/lib/services/websocket_messages_service.dart`
  - **Tamanho**: ~350 linhas
  - **Dependências**: SocketService, Message model
  - **Observação**: ✅ Gerencia streams e cache de mensagens
  - **Mudanças**: Apenas imports

---

## ✅ FASE 7: BACKEND WEBSOCKET (~50/~50 arquivos - 100%)

### Estrutura principal do wedding-websocket:

#### Arquivos de configuração:
- [x] `wedding-websocket/package.json`
- [x] `wedding-websocket/package-lock.json`
- [x] `wedding-websocket/tsconfig.json`
- [x] `wedding-websocket/tsconfig.build.json`
- [x] `wedding-websocket/nest-cli.json`
- [x] `wedding-websocket/.env` ✅ **ATUALIZADO PARA PARTIU**
- [x] `wedding-websocket/.prettierrc`
- [x] `wedding-websocket/eslint.config.mjs`

#### Docker & Deploy:
- [x] `wedding-websocket/Dockerfile`
- [x] `wedding-websocket/.dockerignore`
- [x] `wedding-websocket/DEPLOY.md`
- [x] `wedding-websocket/DEPLOY_PARTIU.md` ✅ **NOVO - GUIA COMPLETO**
- [x] `wedding-websocket/README.md`

#### Código-fonte (src/):
- [x] `wedding-websocket/src/main.ts`
- [x] `wedding-websocket/src/app.module.ts`
- [x] `wedding-websocket/src/app.controller.ts`
- [x] `wedding-websocket/src/app.service.ts`
- [x] `wedding-websocket/src/notify.controller.ts`

#### Gateways (WebSocket):
- [x] `wedding-websocket/src/gateways/messages.gateway.ts`
- [x] `wedding-websocket/src/gateways/applications.gateway.ts`

#### Scripts de teste:
- [x] `wedding-websocket/test-websocket.js`
- [x] `wedding-websocket/test-socket-connection.js`

#### Testes:
- [x] `wedding-websocket/src/app.controller.spec.ts`
- [x] `wedding-websocket/test/` (pasta completa)

**🎉 TODO O BACKEND FOI COPIADO COM SUCESSO!**

---

## 🔲 FASE 8: DEPENDÊNCIAS & CONFIGURAÇÃO (0/3 tarefas - 0%)

### Flutter (pubspec.yaml):
- [x] `socket_io_client: ^3.0.0` - ✅ JÁ INSTALADO
- [x] `provider: ^6.1.5+1` - ✅ JÁ INSTALADO
- [x] `cloud_firestore: ^6.1.0` - ✅ JÁ INSTALADO
- [ ] Verificar outras dependências necessárias

### Backend (package.json):
- [ ] Instalar dependências do NestJS
- [ ] Configurar Firebase Admin SDK
- [ ] Configurar variáveis de ambiente

---

## 🔲 FASE 9: WIDGETS & COMPONENTES COMPARTILHADOS (0/? arquivos - 0%)

### Widgets necessários (ainda não mapeados):
- [ ] `StableAvatar` - Widget de avatar com cache
- [ ] `ReactiveUserNameWithBadge` - Nome com badge de verificação
- [ ] `AvatarMemoryCache` - Cache em memória de avatares
- [ ] `SlidingSearchIconButton` - Botão de busca deslizante
- [ ] `GlimpseEmptyState` - Estado vazio
- [ ] Outros widgets compartilhados...

---

## 🔲 FASE 10: SERVIÇOS AUXILIARES (0/? arquivos - 0%)

### Serviços necessários (ainda não mapeados):
- [ ] `AppLogger` - Sistema de logs
- [ ] `AuthStateService` - Estado de autenticação
- [ ] `UserDataCachePlaceholder` - Cache de dados do usuário
- [ ] `ChatService` - Serviço de chat
- [ ] `TimeAgoHelper` - Helper de formatação de tempo
- [ ] Outros serviços...

---

## 🔲 FASE 11: CONSTANTES & CONFIGURAÇÕES (0/1 arquivo - 0%)

- [ ] Mapear e criar constantes necessárias
  - USER_ID, fullname, MESSAGE_READ, etc.
  - Configurações de VIP, gating, etc.

---

## 🔲 FASE 12: DEPLOY & TESTES (0/3 tarefas - 0%)

- [ ] Build do backend WebSocket
- [ ] Deploy no Google Cloud Run
- [ ] Testes de integração Flutter + Backend

---

## 📈 PROGRESSO POR CATEGORIA

| Categoria | Progresso | Status |
|-----------|-----------|--------|
| Models | 2/2 (100%) | ✅ Completo |
| Services | 5/5 (100%) | ✅ Completo |
| Widgets | 0/4 (0%) | 🔴 Pendente |
| WebSocket Services | 2/2 (100%) | ✅ Completo |
| Backend | ~50/~50 (100%) | ✅ Completo |
| WebSocket Services | 0/2 (0%) | 🔴 Pendente |
| Backend | 0/~50 (0%) | 🔴 Pendente |
| Dependências | 3/6 (50%) | 🟡 Parcial |
| Componentes Compartilhados | 0/? (0%) | 🔴 Pendente |
| Deploy | 0/3 (0%) | 🔴 Pendente |

**TOTAL GERAL**: ~60/70+ arquivos migrados (≈85%)

---

## ⚠️ DEPENDÊNCIAS CRÍTICAS IDENTIFICADAS

### Widgets que precisam ser criados/adaptados:
1. **StableAvatar** - Avatar com carregamento otimizado
2. **ReactiveUserNameWithBadge** - Nome de usuário reativo com badge
3. **AvatarMemoryCache** - Sistema de cache de avatares
4. **SlidingSearchIconButton** - Botão de busca com animação
5. **GlimpseEmptyState** - Estados vazios personalizados

### Serviços que precisam ser criados/adaptados:
1. **AppLogger** - Sistema de logging estruturado
2. **AuthStateService** - Gerenciamento de estado de autenticação
3. **UserDataCachePlaceholder** - Cache de dados de usuários
4. **ChatService** - Lógica de negócio do chat
5. **TimeAgoHelper** - Formatação de tempo relativo

### Estilos e Temas:
1. **GlimpseColors** - Paleta de cores do app
2. **GlimpseStyles** - Estilos globais
3. **ConversationStyles** - Estilos específicos de conversas

---

## 🎯 PRÓXIMOS PASSOS RECOMENDADOS

### Opção A: Abordagem Incremental (Recomendada)
1. ✅ Completar FASE 6 (WebSocket Services Flutter)
2. Completar FASE 7 (Backend WebSocket)
3. Fazer deploy e testar backend
4. Depois continuar com UI/Widgets

### Opção B: Abordagem Completa
1. Copiar TODOS os arquivos de uma vez
2. Resolver dependências conforme aparecem
3. Adaptar imports e referências

---

## 📝 NOTAS IMPORTANTES

- ⚠️ Alguns arquivos criados foram **adaptados/simplificados** em vez de copiados diretamente
- ⚠️ É necessário criar versões originais dos arquivos já migrados
- ⚠️ Muitas dependências ainda não foram mapeadas
- ⚠️ O backend WebSocket é crítico e deve ser priorizado
- ⚠️ Testes são essenciais antes de deploy em produção

---

**Data de criação**: 2 de dezembro de 2025  
**Última atualização**: 2 de dezembro de 2025
