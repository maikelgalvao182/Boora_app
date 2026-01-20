# 🎯 Sistema de Referral - Fluxo Visual

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUXO COMPLETO DE REFERRAL                    │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  USUÁRIO A       │  (Referrer)
│  "João"          │
└────────┬─────────┘
         │
         │ 1. Clica botão 🎁 na Home
         ▼
┌────────────────────────────────────────────────────┐
│  InviteDrawer.dart                                 │
│  ├─ Chama: ReferralService.generateInviteLink()   │
│  ├─ Chama: AppsflyerService.generateInviteLink()  │
│  └─ Gera: https://boora.onelink.me/bFrs/XYZ...    │
│           ?deep_link_sub2=JOAO_USER_ID            │
└────────────────┬───────────────────────────────────┘
                 │
                 │ 2. Copia e compartilha link
                 ▼
         ┌───────────────┐
         │  WhatsApp     │
         │  Telegram     │
         │  SMS          │
         └───────┬───────┘
                 │
                 │ 3. Link enviado
                 ▼
         ┌────────────────┐
         │  USUÁRIO B     │  (Invited User)
         │  "Maria"       │
         └────────┬───────┘
                  │
                  │ 4. Clica no link
                  ▼
         ┌─────────────────┐
         │  App Store /    │
         │  Play Store     │
         └────────┬────────┘
                  │
                  │ 5. Instala app
                  ▼
         ┌─────────────────────────────────────────┐
         │  App abre após instalação               │
         │  ├─ AppsFlyer captura deep link         │
         │  ├─ Extrai: deep_link_sub2=JOAO_USER_ID│
         │  └─ Salva em SharedPreferences:         │
         │     pending_referrer_id = "JOAO_USER_ID"│
         └────────┬────────────────────────────────┘
                  │
                  │ 6. Usuário faz signup
                  ▼
         ┌──────────────────────────────────────────┐
         │  SignupWizardScreen                      │
         │  └─ Preenche dados (nome, foto, etc)     │
         └────────┬─────────────────────────────────┘
                  │
                  │ 7. Clica "Finalizar"
                  ▼
         ┌──────────────────────────────────────────────┐
         │  CadastroViewModel.createAccount()           │
         │  ├─ Consome: ReferralService.consume...()    │
         │  ├─ Lê: pending_referrer_id                  │
         │  └─ Cria documento em Firestore:             │
         │                                              │
         │     Users/MARIA_USER_ID {                    │
         │       fullName: "Maria",                     │
         │       referrerId: "JOAO_USER_ID",            │
         │       referralSource: "appsflyer",           │
         │       referralCapturedAt: Timestamp(...)     │
         │     }                                         │
         └────────┬─────────────────────────────────────┘
                  │
                  │ 8. onCreate trigger
                  ▼
         ┌───────────────────────────────────────────────┐
         │  Cloud Function: onUserCreatedReferral        │
         │  ├─ Lê: Users/MARIA_USER_ID.referrerId        │
         │  ├─ Valida: referrerId !== userId             │
         │  ├─ Cria: ReferralInstalls/MARIA_USER_ID      │
         │  │                                            │
         │  │   ReferralInstalls/MARIA_USER_ID {         │
         │  │     userId: "MARIA_USER_ID",               │
         │  │     referrerId: "JOAO_USER_ID",            │
         │  │     source: "appsflyer",                   │
         │  │     createdAt: Timestamp(...)              │
         │  │   }                                        │
         │  │                                            │
         │  └─ Atualiza: Users/JOAO_USER_ID              │
         │                                               │
         │      Users/JOAO_USER_ID {                     │
         │        referralInstallCount: 1,  // +1        │
         │        referralUpdatedAt: Timestamp(...)      │
         │      }                                        │
         └────────┬──────────────────────────────────────┘
                  │
                  │ Se referralInstallCount % 10 == 0
                  ▼
         ┌───────────────────────────────────────────────┐
         │  🎁 RECOMPENSA VIP (a cada 10 conversões)     │
         │                                               │
         │  Users/JOAO_USER_ID {                         │
         │    referralInstallCount: 10,                  │
         │    referralRewardedCount: 1,                  │
         │    user_is_vip: true,                         │
         │    user_level: "vip",                         │
         │    vip_priority: 1,                           │
         │    vipExpiresAt: Timestamp(+90 dias),         │
         │    vipProductId: "referral_bonus_3m",         │
         │    referralRewardedAt: Timestamp(...)         │
         │  }                                            │
         └───────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  VISUALIZAÇÃO NO APP (João)                      │
└─────────────────────────────────────────────────────────────────┘

         ┌────────────────────────────────────────┐
         │  InviteDrawer                          │
         │  ├─ "Convide amigos"                   │
         │  ├─ Link: boora.onelink.me/...         │
         │  ├─ Progresso: 1/10 para próximo premio│
         │  └─ Lista de amigos:                   │
         │     ┌──────────────────────────────┐   │
         │     │ 👤 Maria                     │   │
         │     │    Entrou hoje               │   │
         │     └──────────────────────────────┘   │
         └────────────────────────────────────────┘

```

---

## 🔄 Fluxo de Dados Técnico

```
┌─────────────────────────────────────────────────────────────────┐
│  CAMADA                 ARQUIVO                  RESPONSABILIDADE│
├─────────────────────────────────────────────────────────────────┤
│  🎨 UI                  invite_drawer.dart       Mostra link e   │
│                         invite_button.dart       lista de amigos │
├─────────────────────────────────────────────────────────────────┤
│  🧠 Business Logic      referral_service.dart    Gera links,     │
│                                                  captura/consome │
│                                                  referrals       │
├─────────────────────────────────────────────────────────────────┤
│  📡 SDK Integration     appsflyer_service.dart   Comunica com    │
│                                                  AppsFlyer API   │
│                                                  e callbacks     │
├─────────────────────────────────────────────────────────────────┤
│  💾 Local Storage       SharedPreferences        Armazena pending│
│                                                  referral        │
├─────────────────────────────────────────────────────────────────┤
│  👤 Auth/Signup         cadastro_view_model.dart Consome referral│
│                         signup_wizard_screen.dart durante signup │
├─────────────────────────────────────────────────────────────────┤
│  ☁️ Backend            referrals.ts             Cloud Function   │
│                         (Firebase Functions)    processa        │
│                                                 conversões       │
├─────────────────────────────────────────────────────────────────┤
│  🗄️ Database           Firestore Collections    Persiste dados: │
│                         ├─ Users/               - User docs      │
│                         └─ ReferralInstalls/    - Conversões     │
└─────────────────────────────────────────────────────────────────┘
```

---

## ⚙️ Configuração Necessária

```yaml
AppsFlyer Dashboard:
  ├─ Dev Key: vNSZa9dsyauCnc6zZEdtnR ✅
  ├─ OneLink Template ID: bFrs ✅
  └─ OneLink Domain: boora.onelink.me ✅

constants.dart:
  ├─ APPSFLYER_DEV_KEY ✅
  ├─ APPSFLYER_APP_ID_IOS (vazio até publicar) ✅
  ├─ APPSFLYER_ONELINK_TEMPLATE_ID ✅
  ├─ APPSFLYER_ONELINK_DOMAIN ✅
  └─ REFERRAL_DEEP_LINK_VALUE: "invite" ✅

main.dart:
  └─ AppsflyerService.instance.initialize() ✅

firebase deploy:
  └─ functions:onUserCreatedReferral ⚠️ (verificar status)
```

---

## 🧪 Pontos de Teste Críticos

```
┌───────────────────────────────────────────────────────────────┐
│  #   TESTE                        COMO VALIDAR                │
├───────────────────────────────────────────────────────────────┤
│  1   Link Generation              Copiar link e ver formato   │
│                                   correto com deep_link_sub2  │
├───────────────────────────────────────────────────────────────┤
│  2   Deep Link Capture            Desinstalar app, clicar     │
│      (CRÍTICO!)                   link, reinstalar, verificar │
│                                   SharedPreferences           │
├───────────────────────────────────────────────────────────────┤
│  3   Signup Integration           Criar conta e verificar     │
│                                   Users/{id}.referrerId       │
├───────────────────────────────────────────────────────────────┤
│  4   Cloud Function               Verificar ReferralInstalls  │
│                                   e referralInstallCount      │
├───────────────────────────────────────────────────────────────┤
│  5   VIP Reward                   Criar 10 fake users,        │
│                                   verificar vipExpiresAt      │
└───────────────────────────────────────────────────────────────┘
```

---

## 🚨 Erros Comuns

```
❌ "Link não gera"
   └─ Verificar: APPSFLYER_DEV_KEY em constants.dart
   └─ Verificar: AppsflyerService.initialize() no main.dart

❌ "Deep link não captura"
   └─ Causa: App já estava instalado (deep links só primeira instalação)
   └─ Solução: Desinstalar completamente e reinstalar via link

❌ "Cloud Function não dispara"
   └─ Verificar: referrerId existe no documento do novo usuário
   └─ Verificar: Function foi deployada (firebase deploy --only functions)

❌ "ReferralInstalls vazio"
   └─ Causa: Cloud Function falhou ou não foi deployada
   └─ Solução: Verificar logs no Firebase Console > Functions

❌ "VIP não concede"
   └─ Verificar: referralInstallCount está incrementando
   └─ Verificar: Threshold correto (10 conversões)
```

---

## 🎯 Quick Start para Testes

**Teste Rápido (5 minutos):**

1. Abrir app no simulador
2. Navegar para `/referral-debug`
3. Clicar "Gerar Link" → Copiar
4. Clicar "Capturar Referral" com ID fake
5. Clicar "Verificar Pendente" → Validar armazenamento
6. Clicar "Consumir Pendente" → Simular signup
7. Clicar "Verificar Firestore" → Ver dados reais

**Teste Completo (30 minutos):**

1. Device A: Gerar link real no InviteDrawer
2. Compartilhar via WhatsApp para Device B
3. Device B: Desinstalar app se já instalado
4. Device B: Clicar no link no WhatsApp
5. Device B: Instalar app pela App Store
6. Device B: Fazer signup completo
7. Firebase Console: Verificar ReferralInstalls
8. Device A: Abrir InviteDrawer → Ver usuário convidado

---

**Documentação completa**: `REFERRAL_SYSTEM_TESTING_GUIDE.md`
