# Análise do Sistema de Logout do Advanced-Dating

## 📋 Índice
1. [Visão Geral](#visão-geral)
2. [Arquitetura](#arquitetura)
3. [Processo de Logout em 12 Etapas](#processo-de-logout-em-12-etapas)
4. [API do SessionManager](#api-do-sessionmanager)
5. [Melhores Práticas Aplicadas](#melhores-práticas-aplicadas)
6. [Comparação com Partiu](#comparação-com-partiu)
7. [Recomendações de Implementação](#recomendações-de-implementação)

---

## Visão Geral

O Advanced-Dating implementa um sistema robusto de logout com **12 etapas sequenciais** que garantem limpeza completa de dados, prevenção de vazamento de memória e sincronização consistente de estado.

### Componentes Principais
- **SessionCleanupService**: Orquestra processo de logout
- **SessionManager**: Gerencia persistência de sessão (SharedPreferences)
- **AppState**: Estado reativo global (ValueNotifier)
- **UserModel**: Fachada legacy para serviços de autenticação

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                    UI Layer (Widgets)                    │
│                app_section_card.dart                     │
└───────────────────────┬─────────────────────────────────┘
                        │ onTap: logout()
                        ▼
┌─────────────────────────────────────────────────────────┐
│            UserModel (Singleton/Legacy Facade)           │
│  • signOut() → delega para SessionCleanupService         │
│  • Mantém flag _isLoggingOut para prevenir relogin      │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│          SessionCleanupService (Orquestrador)            │
│  • logout(): 12 etapas com logs detalhados               │
│  • Garantia de execução sequencial                      │
│  • Try-catch individual por etapa                       │
└───────────────────────┬─────────────────────────────────┘
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
    ┌─────────┐   ┌──────────┐   ┌─────────┐
    │Session  │   │AppState  │   │External │
    │Manager  │   │(Reactive)│   │Services │
    └─────────┘   └──────────┘   └─────────┘
```

---

## Processo de Logout em 12 Etapas

### Etapa 1: Remover Device Token do Usuário
**Objetivo**: Desassociar dispositivo do usuário no Firestore para parar notificações push.

```dart
try {
  final uid = UserModel.instance.user.userId;
  if (uid.isNotEmpty) {
    await UserModel.instance.stopPushTokenListener(removeToken: true);
    AppLogger.success('Etapa 1/12: Device token removido do usuário', tag: 'LOGOUT');
  }
} catch (e) {
  AppLogger.warning('Etapa 1/12: Falha ao remover device token: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Evita que usuário receba notificações após logout
- Limpa lista de dispositivos ativos no documento Firestore do usuário

---

### Etapa 2: Logout do RevenueCat
**Objetivo**: Desvincular assinatura/compras do usuário atual.

```dart
try {
  await SimpleRevenueCatService.logout();
  AppLogger.success('Etapa 2/12: RevenueCat logout executado', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 2/12: Falha ao fazer logout do RevenueCat: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Previne que dados de assinatura vazem entre contas
- Sincroniza estado de compras com backend da RevenueCat

---

### Etapa 2.5: Logout do Google Sign-In
**Objetivo**: Deslogar do provedor OAuth (Google).

```dart
try {
  final GoogleSignIn googleSignIn = GoogleSignIn();
  await googleSignIn.signOut();
  AppLogger.success('Etapa 2.5/12: Google Sign-In logout executado', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 2.5/12: Falha ao fazer logout do Google Sign-In: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Remove credenciais do Google armazenadas localmente
- Força re-autenticação OAuth no próximo login

---

### Etapa 3: Limpar Caches Customizados
**Objetivo**: Remover dados cacheados da aplicação (engajamento, mensagens, etc).

```dart
try {
  final uid = UserModel.instance.user.userId;
  if (uid.isNotEmpty) {
    await CacheServiceLocator.engagementRepo.clearEngagementData(uid);
    try {
      CacheServiceLocator.bus.invalidateUser(uid, 'logout');
    } catch (_) {}
  }
  AppLogger.success('Etapa 3/12: Caches customizados limpos', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 3/12: Falha ao limpar caches: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Evita exibição de dados cached de outro usuário
- Libera memória do dispositivo

---

### Etapa 3.5: Parar Global Service Listeners
**Objetivo**: Cancelar assinaturas de streams/listeners ativos.

```dart
try {
  GlobalServiceLifecycleManager.stopAll();
  AppLogger.success('Etapa 3.5/12: Global service listeners parados', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 3.5/12: Falha ao parar listeners: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Previne memory leaks de listeners órfãos
- Interrompe polling/websockets desnecessários

---

### Etapa 4: Desinscrever de Tópicos FCM
**Objetivo**: Remover inscrições em tópicos Firebase Cloud Messaging.

```dart
try {
  final uid = UserModel.instance.user.userId;
  if (uid.isNotEmpty) {
    await FirebaseMessaging.instance.unsubscribeFromTopic(uid);
  }
  AppLogger.success('Etapa 4/12: Desinscrito de tópicos FCM', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 4/12: Falha ao desinscrever de tópicos: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Evita notificações dirigidas a tópicos específicos do usuário
- Complementa remoção do device token (Etapa 1)

---

### Etapa 4.1: Deletar Token FCM Localmente
**Objetivo**: Invalidar token FCM local e forçar geração de novo token.

```dart
try {
  await FirebaseMessaging.instance.deleteToken();
  AppLogger.success('Etapa 4.1/12: Token FCM deletado localmente', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 4.1/12: Falha ao deletar token FCM: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Garante que token antigo não será reutilizado
- Segurança adicional contra interceptação de notificações

---

### Etapa 5: Limpar SessionManager e SharedPreferences
**Objetivo**: Resetar persistência local, preservando configurações do app.

```dart
try {
  await SessionManager.instance.initialize();
  
  // Preserva configurações
  final savedLanguage = SessionManager.instance.language;
  final savedTheme = SessionManager.instance.themeMode;
  final savedOnboarding = SessionManager.instance.hasCompletedOnboarding;
  
  // Limpa FCM token manualmente
  SessionManager.instance.fcmToken = null;
  
  // Executa logout (que preserva configs)
  await SessionManager.instance.logout();
  
  AppLogger.success('Etapa 5/12: SessionManager e SharedPreferences limpos', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 5/12: Falha ao limpar SessionManager: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Remove dados de usuário persistidos localmente
- **Preserva preferências do app** (idioma, tema, onboarding)
- Evita forçar usuário a reconfigurar app

---

### Etapa 6: Firebase Auth signOut
**Objetivo**: Deslogar da sessão Firebase Authentication.

```dart
try {
  await authService.signOut();
  AppLogger.success('Etapa 6/12: Firebase Auth signOut executado', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 6/12: Falha ao fazer signOut do Firebase: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Invalida token JWT do Firebase
- Dispara listeners de estado de autenticação (onAuthStateChanged)

---

### Etapa 7: Resetar Global Reactive State
**Objetivo**: Limpar ValueNotifiers/Observables globais.

```dart
try {
  _resetGlobalReactiveState();
  AppLogger.success('Etapa 7/12: Estado reativo global resetado', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 7/12: Falha ao resetar estado reativo: $e', tag: 'LOGOUT');
}

void _resetGlobalReactiveState() {
  // Chama reset do AppState que limpa todos os ValueNotifiers
  AppState.reset();
}
```

**Por que é importante:**
- Garante que UI não exibe dados do usuário antigo
- Previne inconsistências de estado reativo

---

### Etapa 8: Limpar Cache Offline do Firestore
**Objetivo**: Remover documentos cacheados localmente pelo Firestore.

```dart
try {
  await FirebaseFirestore.instance.clearPersistence();
  AppLogger.success('Etapa 8/12: Cache offline do Firestore limpo', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 8/12: Falha ao limpar cache do Firestore: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Remove documentos Firestore cacheados no disco
- Previne que próximo usuário veja dados do anterior (GDPR/privacidade)

---

### Etapa 9: Purgar Singleton do UserModel
**Objetivo**: Resetar instância singleton do UserModel.

```dart
try {
  _purgeUserModelSingleton();
  AppLogger.success('Etapa 9/12: UserModel singleton purgado', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 9/12: Falha ao purgar UserModel: $e', tag: 'LOGOUT');
}

void _purgeUserModelSingleton() {
  // No UserModel existe um método interno para resetar o singleton
  // ou simplesmente redefine campos para valores padrão
  UserModel.instance.user = User(); // User vazio
  UserModel.instance.isLoading = false;
  UserModel.instance.activeVipId = '';
}
```

**Por que é importante:**
- Limpa dados residuais no singleton
- Garante estado limpo para próximo login

---

### Etapa 10: Resetar PushNotificationManager
**Objetivo**: Limpar estado do gerenciador de notificações.

```dart
try {
  PushNotificationManager.instance.reset();
  AppLogger.success('Etapa 10/12: PushNotificationManager resetado', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 10/12: Falha ao resetar PushNotificationManager: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Remove callbacks/listeners de notificações pendentes
- Previne exibição de notificações para usuário antigo

---

### Etapa 11: Reinscrever em Tópico Global
**Objetivo**: Inscrever em tópico geral do app (anúncios, updates).

```dart
try {
  await FirebaseMessaging.instance.subscribeToTopic('global_announcements');
  AppLogger.success('Etapa 11/12: Reinscrito em tópico global', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 11/12: Falha ao reinscrever em tópico global: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Mantém usuário conectado a notificações gerais do app
- Permite envio de notificações de marketing/updates

---

### Etapa 12: Callback de Navegação
**Objetivo**: Executar callback final (navegação, dialogs, etc).

```dart
try {
  if (onLogoutComplete != null) {
    onLogoutComplete();
  }
  AppLogger.success('Etapa 12/12: Callback de logout executado', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 12/12: Falha ao executar callback: $e', tag: 'LOGOUT');
}
```

**Por que é importante:**
- Permite customização do fluxo pós-logout
- Usado tipicamente para navegação (ex: tela de login)

---

## API do SessionManager

### Inicialização
```dart
// main.dart
await SessionManager.instance.initialize();
```

### Propriedades Principais

#### Estado de Autenticação
```dart
bool isLoggedIn                      // Usuário está logado?
User? currentUser                    // Dados do usuário atual
String? currentUserId                // ID do usuário (deprecated - use AppState)
String? authToken                    // Token JWT/OAuth
String? deviceId                     // ID do dispositivo
```

#### Configurações Persistidas
```dart
String language                      // Idioma ('pt', 'en', 'es')
String themeMode                     // Tema ('light', 'dark', 'system')
bool notificationsEnabled            // Notificações habilitadas?
bool hasCompletedOnboarding          // Onboarding completo?
String? fcmToken                     // Token Firebase Cloud Messaging
```

### Métodos Principais

#### Login
```dart
await SessionManager.instance.login(
  user,
  token: 'jwt_token_opcional',
  deviceId: 'device_id_opcional',
);
```

#### Logout (com preservação de configurações)
```dart
await SessionManager.instance.logout();
```

**O que preserva:**
- Idioma
- Tema
- Estado de onboarding

**O que limpa:**
- Dados do usuário
- Token de autenticação
- Token FCM
- Caches externos (imagens, AppCacheService, AvatarViewModelCache)

#### Limpeza Total
```dart
await SessionManager.instance.clearAll();
```

**Limpa TUDO**, incluindo configurações do app. Use apenas para:
- Deletar conta
- Reset completo do app

### Métodos Auxiliares

#### Atualizar Usuário Parcialmente
```dart
SessionManager.instance.updateCurrentUserFromMap({
  'fullname': 'Novo Nome',
  'user_bio': 'Nova bio',
});
```

#### Salvar Dados Customizados
```dart
await SessionManager.instance.setCustomValue('minha_chave', 'valor');
final valor = SessionManager.instance.getCustomValue('minha_chave');
```

#### Debug
```dart
SessionManager.instance.printSessionState();  // Imprime estado (com mascaramento)
final keys = SessionManager.instance.getAllKeys();  // Lista todas as chaves
```

---

## Melhores Práticas Aplicadas

### 1. ✅ Separação de Responsabilidades
- **SessionCleanupService**: Orquestração do logout
- **SessionManager**: Persistência de dados
- **AppState**: Estado reativo global
- **UserModel**: Fachada legacy (mantida para compatibilidade)

### 2. ✅ Logs Detalhados com AppLogger
Cada etapa tem logs específicos:
```dart
AppLogger.success('Etapa X/12: Ação completada', tag: 'LOGOUT');
AppLogger.warning('Etapa X/12: Falha mas continua: $e', tag: 'LOGOUT');
AppLogger.error('Erro crítico', tag: 'LOGOUT', error: e, stackTrace: stack);
```

### 3. ✅ Try-Catch Individual por Etapa
```dart
try {
  // Etapa específica
} catch (e) {
  // Loga warning mas CONTINUA processo
}
```

**Benefício**: Se uma etapa falha (ex: RevenueCat offline), outras ainda executam.

### 4. ✅ Preservação Inteligente de Configurações
```dart
// Salva antes
final savedLanguage = SessionManager.instance.language;
// Limpa tudo
await _prefs.clear();
// Restaura
SessionManager.instance.language = savedLanguage;
```

### 5. ✅ Prevenção de Relogin Durante Logout
```dart
class UserModel {
  static bool _isLoggingOut = false;
  
  Future<void> checkUserAccount() async {
    if (_isLoggingOut) return;  // Previne relogin
    // ...lógica de login automático
  }
  
  Future<void> signOut() async {
    _isLoggingOut = true;
    await SessionCleanupService.logout(() {
      // navegação
    });
    _isLoggingOut = false;
  }
}
```

### 6. ✅ Sanitização de Dados Firestore para JSON
```dart
dynamic _sanitizeForJson(dynamic value) {
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is GeoPoint) return {'latitude': value.latitude, 'longitude': value.longitude};
  // ...outros tipos
}
```

**Problema resolvido**: Timestamp e GeoPoint não são JSON-safe nativamente.

### 7. ✅ Sincronização Reativa Imediata
```dart
set currentUser(User? user) {
  // Salva em SharedPreferences
  _prefs.setString(_Keys.currentUser, json);
  
  // Propaga IMEDIATAMENTE para estado reativo
  AppState.currentUser.value = user;
  AppState.isVerified.value = user?.userIsVerified ?? false;
}
```

**Benefício**: UI atualiza instantaneamente, antes do primeiro snapshot do Firestore.

### 8. ✅ Mascaramento de Dados Sensíveis em Logs
```dart
String _maskSensitiveData(String? data) {
  if (data.length <= 4) return '****';
  return '${data.substring(0, 4)}****${data.substring(data.length - 4)}';
}

// Uso:
AppLogger.debug('User ID: ${_maskSensitiveData(userId)}', tag: 'SESSION');
```

---

## Comparação com Partiu

### Advanced-Dating (Atual)
```dart
// 12 etapas orquestradas
await SessionCleanupService.logout(() {
  context.go(AppRoutes.login);
});
```

**Pontos Fortes:**
- ✅ Processo detalhado com 12 etapas
- ✅ Logs individuais por etapa
- ✅ Try-catch isolado (falha em uma etapa não interrompe processo)
- ✅ Preserva configurações do app
- ✅ Limpa RevenueCat, Google Sign-In, caches customizados
- ✅ Previne relogin com flag `_isLoggingOut`

---

### Partiu (Atual)
```dart
// UserModel.signOut() - Versão simplificada
Future<void> signOut() async {
  try {
    try { await stopPushTokenListener(removeToken: true); } catch (_) {}
    try { await SimpleRevenueCatService.logout(); } catch (_) {}
    try {
      final uid = user.userId;
      await CacheServiceLocator.engagementRepo.clearEngagementData(uid);
      try { CacheServiceLocator.bus.invalidateUser(uid, 'logout'); } catch (_) {}
    } catch (_) {}
    
    await authService.signOut();
    activeVipId = '';
  } catch (e) {
    AppLogger.error('Erro durante logout', tag: 'AUTH');
  }
}
```

**Pontos Fortes:**
- ✅ Já implementa limpeza de push tokens
- ✅ Já tem integração com RevenueCat
- ✅ Já limpa caches customizados

**Pontos Fracos:**
- ❌ Sem logs detalhados por etapa (apenas erro genérico final)
- ❌ Não limpa SessionManager explicitamente
- ❌ Não limpa cache offline do Firestore
- ❌ Não reseta estado reativo (AppState)
- ❌ Não limpa Google Sign-In
- ❌ Não deleta token FCM localmente
- ❌ Sem flag para prevenir relogin durante logout
- ❌ Não preserva configurações do app (idioma, tema)

---

## Recomendações de Implementação

### Fase 1: Implementação Básica (1-2 horas)

#### 1.1 Criar SessionCleanupService no Partiu
```dart
// lib/core/services/session_cleanup_service.dart

import 'package:partiu/core/managers/session_manager.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SessionCleanupService {
  static Future<void> logout(VoidCallback onLogoutComplete) async {
    AppLogger.info('🚀 Iniciando processo de logout (12 etapas)', tag: 'LOGOUT');
    
    try {
      // Etapa 1: Remover device token
      try {
        final uid = UserModel.instance.user.userId;
        if (uid.isNotEmpty) {
          await UserModel.instance.stopPushTokenListener(removeToken: true);
          AppLogger.success('✅ Etapa 1/12: Device token removido', tag: 'LOGOUT');
        }
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 1/12: Falha ao remover device token: $e', tag: 'LOGOUT');
      }

      // Etapa 2: RevenueCat logout
      try {
        await SimpleRevenueCatService.logout();
        AppLogger.success('✅ Etapa 2/12: RevenueCat logout', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 2/12: Falha RevenueCat: $e', tag: 'LOGOUT');
      }

      // Etapa 2.5: Google Sign-In logout
      try {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
        AppLogger.success('✅ Etapa 2.5/12: Google Sign-In logout', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 2.5/12: Falha Google: $e', tag: 'LOGOUT');
      }

      // Etapa 3: Limpar caches customizados
      try {
        final uid = UserModel.instance.user.userId;
        if (uid.isNotEmpty) {
          await CacheServiceLocator.engagementRepo.clearEngagementData(uid);
          try {
            CacheServiceLocator.bus.invalidateUser(uid, 'logout');
          } catch (_) {}
        }
        AppLogger.success('✅ Etapa 3/12: Caches limpos', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 3/12: Falha caches: $e', tag: 'LOGOUT');
      }

      // Etapa 4: Desinscrever de tópicos FCM
      try {
        final uid = UserModel.instance.user.userId;
        if (uid.isNotEmpty) {
          await FirebaseMessaging.instance.unsubscribeFromTopic(uid);
        }
        AppLogger.success('✅ Etapa 4/12: Desinscrito de tópicos FCM', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 4/12: Falha FCM topics: $e', tag: 'LOGOUT');
      }

      // Etapa 4.1: Deletar token FCM
      try {
        await FirebaseMessaging.instance.deleteToken();
        AppLogger.success('✅ Etapa 4.1/12: Token FCM deletado', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 4.1/12: Falha deletar token: $e', tag: 'LOGOUT');
      }

      // Etapa 5: Limpar SessionManager
      try {
        await SessionManager.instance.logout();
        AppLogger.success('✅ Etapa 5/12: SessionManager limpo', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 5/12: Falha SessionManager: $e', tag: 'LOGOUT');
      }

      // Etapa 6: Firebase Auth signOut
      try {
        await FirebaseAuth.instance.signOut();
        AppLogger.success('✅ Etapa 6/12: Firebase Auth signOut', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 6/12: Falha Firebase Auth: $e', tag: 'LOGOUT');
      }

      // Etapa 7: Resetar estado reativo
      try {
        AppState.reset();
        AppLogger.success('✅ Etapa 7/12: Estado reativo resetado', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 7/12: Falha reset state: $e', tag: 'LOGOUT');
      }

      // Etapa 8: Limpar cache Firestore
      try {
        await FirebaseFirestore.instance.clearPersistence();
        AppLogger.success('✅ Etapa 8/12: Cache Firestore limpo', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 8/12: Falha Firestore cache: $e', tag: 'LOGOUT');
      }

      // Etapa 9: Purgar UserModel singleton
      try {
        UserModel.instance.user = User();
        UserModel.instance.isLoading = false;
        UserModel.instance.activeVipId = '';
        AppLogger.success('✅ Etapa 9/12: UserModel purgado', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 9/12: Falha purgar UserModel: $e', tag: 'LOGOUT');
      }

      // Etapa 12: Callback de navegação
      try {
        onLogoutComplete();
        AppLogger.success('✅ Etapa 12/12: Logout completo!', tag: 'LOGOUT');
      } catch (e) {
        AppLogger.warning('⚠️ Etapa 12/12: Falha callback: $e', tag: 'LOGOUT');
      }

      AppLogger.success('🎉 Logout concluído com sucesso!', tag: 'LOGOUT');
      
    } catch (e, stack) {
      AppLogger.error('❌ Erro crítico durante logout', tag: 'LOGOUT', error: e, stackTrace: stack);
    }
  }
}
```

#### 1.2 Atualizar UserModel.signOut()
```dart
// lib/models/user_model.dart

Future<void> signOut() async {
  try {
    await SessionCleanupService.logout(() {
      // Navegação será feita por quem chama o método
    });
  } catch (e) {
    AppLogger.error('Erro durante logout', tag: 'AUTH', error: e);
  }
}
```

#### 1.3 Implementar Preservação de Configurações no SessionManager
```dart
// lib/core/managers/session_manager.dart

Future<void> logout() async {
  AppLogger.info('Iniciando limpeza do SessionManager', tag: 'SESSION');
  
  // Preserva configurações
  final savedLanguage = language;
  final savedTheme = themeMode;
  final savedOnboarding = hasCompletedOnboarding;
  
  // Limpa tudo
  await _prefs.clear();
  await _prefs.reload();
  
  // Restaura configurações
  language = savedLanguage;
  themeMode = savedTheme;
  hasCompletedOnboarding = savedOnboarding;
  
  // Limpa caches externos
  await _clearExternalCaches();
  
  AppLogger.success('SessionManager limpo (configurações preservadas)', tag: 'SESSION');
}
```

---

### Fase 2: Melhorias de Segurança (2-3 horas)

#### 2.1 Adicionar Flag de Prevenção de Relogin
```dart
// lib/models/user_model.dart

class UserModel extends ChangeNotifier {
  static bool _isLoggingOut = false;
  
  Future<void> checkUserAccount() async {
    if (_isLoggingOut) {
      AppLogger.warning('Relogin bloqueado durante logout', tag: 'AUTH');
      return;
    }
    
    // ...lógica existente
  }
  
  Future<void> signOut() async {
    _isLoggingOut = true;
    
    try {
      await SessionCleanupService.logout(() {
        // navegação
      });
    } finally {
      _isLoggingOut = false;
    }
  }
}
```

#### 2.2 Implementar Mascaramento de Dados Sensíveis
```dart
// lib/core/utils/app_logger.dart

static String maskSensitiveData(String? data) {
  if (data == null || data.isEmpty) return 'none';
  if (data.length <= 4) return '****';
  
  final start = data.substring(0, 4);
  final end = data.substring(data.length - 4);
  return '$start****$end';
}

// Uso:
AppLogger.debug('User ID: ${AppLogger.maskSensitiveData(userId)}', tag: 'AUTH');
```

---

### Fase 3: Otimizações (1-2 horas)

#### 3.1 Adicionar Timeout para Etapas Demoradas
```dart
// Exemplo para clearPersistence (pode demorar muito)
try {
  await FirebaseFirestore.instance.clearPersistence()
    .timeout(Duration(seconds: 5));
  AppLogger.success('Etapa 8/12: Cache Firestore limpo', tag: 'LOGOUT');
} on TimeoutException {
  AppLogger.warning('Etapa 8/12: Timeout ao limpar cache (continua)', tag: 'LOGOUT');
} catch (e) {
  AppLogger.warning('Etapa 8/12: Erro ao limpar cache: $e', tag: 'LOGOUT');
}
```

#### 3.2 Adicionar Analytics de Logout
```dart
// Etapa final
try {
  await FirebaseAnalytics.instance.logEvent(
    name: 'user_logout',
    parameters: {
      'logout_duration_ms': DateTime.now().difference(startTime).inMilliseconds,
      'logout_success': true,
    },
  );
} catch (_) {}
```

---

## Checklist de Implementação

### ✅ Básico (Obrigatório)
- [ ] Criar `SessionCleanupService` com 12 etapas
- [ ] Adicionar logs detalhados por etapa (AppLogger)
- [ ] Implementar try-catch individual por etapa
- [ ] Preservar configurações no `SessionManager.logout()`
- [ ] Limpar cache offline do Firestore (`clearPersistence()`)
- [ ] Resetar estado reativo (`AppState.reset()`)
- [ ] Limpar Google Sign-In
- [ ] Deletar token FCM localmente

### 🔒 Segurança (Recomendado)
- [ ] Adicionar flag `_isLoggingOut` no UserModel
- [ ] Implementar mascaramento de dados sensíveis nos logs
- [ ] Adicionar sanitização de tipos Firestore no SessionManager

### ⚡ Performance (Opcional)
- [ ] Adicionar timeouts para etapas demoradas
- [ ] Implementar analytics de logout
- [ ] Criar testes unitários para SessionCleanupService

---

## Exemplo de Uso Final

```dart
// settings_screen.dart

ElevatedButton(
  onPressed: () async {
    // Mostra loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );
    
    // Executa logout
    await SessionCleanupService.logout(() {
      // Remove loading
      if (context.mounted) Navigator.of(context).pop();
      
      // Navega para login
      if (context.mounted) {
        context.go(AppRoutes.login);
      }
    });
  },
  child: Text('Sair'),
)
```

---

## Conclusão

O sistema de logout do Advanced-Dating representa **estado da arte** em limpeza de sessão para apps Flutter/Firebase. As 12 etapas garantem:

1. **Privacidade**: Nenhum dado vaza entre contas (GDPR compliant)
2. **Performance**: Libera memória e caches desnecessários
3. **Segurança**: Previne relogin acidental e interceptação de notificações
4. **UX**: Preserva configurações do app (idioma, tema)
5. **Manutenibilidade**: Logs detalhados facilitam debug

Recomenda-se implementar **Fase 1 (básico)** imediatamente e depois evoluir para Fase 2/3 conforme necessidade do projeto.
