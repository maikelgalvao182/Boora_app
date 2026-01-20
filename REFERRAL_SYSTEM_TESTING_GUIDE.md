# 🎯 Sistema de Referral - Guia Completo de Testes

## 📋 Sumário Executivo

Sistema de referral implementado usando **AppsFlyer OneLink** para rastreamento de instalações e conversões. Usuários compartilham links de convite personalizados e ganham **90 dias de premium** a cada **10 amigos** que instalarem o app e criarem conta.

---

## ✅ Status da Implementação

### 1. **Geração de Links de Convite** ✅
- **Arquivo**: `lib/services/appsflyer_service.dart` (linha 92)
- **Método**: `generateInviteLink()`
- **API**: AppsFlyer User Invite API oficial
- **Formato**: `https://boora.onelink.me/bFrs/eranp59q?pid=af_app_invites&c=user_invite&deep_link_value=invite&deep_link_sub2=USER_ID`

### 2. **Captura de Deep Links** ✅
- **Arquivo**: `lib/services/appsflyer_service.dart` (linhas 221-289)
- **Callbacks**:
  - `onDeepLinking` - Deep links diretos (app já instalado)
  - `onInstallConversionData` - Deferred deep links (primeira instalação)
- **Extração**: Prioridade `deep_link_sub2` → `deep_link_sub1` → `af_sub1`

### 3. **Armazenamento Temporário** ✅
- **Arquivo**: `lib/services/referral_service.dart` (linhas 16-54)
- **Método**: `captureReferral()`
- **Storage**: SharedPreferences (antes do signup)
- **Keys**: `pending_referrer_id`, `pending_deep_link_value`, `pending_referral_captured_at`

### 4. **Integração com Signup** ✅
- **Arquivo**: `lib/features/auth/presentation/controllers/cadastro_view_model.dart` (linha 210)
- **Método**: `createAccount()`
- **Ação**: Consome `referrerId` pendente e salva no documento do novo usuário
- **Campos Firestore**:
  - `referrerId` - ID do usuário que indicou
  - `referralSource` - `"appsflyer"`
  - `referralCapturedAt` - Timestamp da captura

### 5. **Cloud Function de Processamento** ✅
- **Arquivo**: `functions/src/referrals.ts`
- **Trigger**: `onCreate` em `Users/{userId}`
- **Ações**:
  1. Valida `referrerId` no documento do novo usuário
  2. Cria documento em `ReferralInstalls/{userId}`
  3. Incrementa `referralInstallCount` do referrer
  4. A cada 10 conversões: adiciona 90 dias de VIP
  5. Atualiza `vipExpiresAt` (acumula se já for VIP)

### 6. **UI - Drawer de Convites** ✅
- **Arquivo**: `lib/features/home/presentation/widgets/invite_drawer.dart`
- **Funcionalidades**:
  - Geração assíncrona de link de convite
  - Copiar link para área de transferência
  - Lista de usuários convidados (Firestore query)
  - Contador de conversões real-time
  - Indicador de progresso (X/10 para próximo premio)

---

## 🧪 Tela de Debug

### Acesso
```dart
// Via código
context.push(AppRoutes.referralDebug);

// Via URL (se deep link configurado)
boora://referral-debug
```

### Funcionalidades
1. **Gerar Link** - Testa a API do AppsFlyer e copia link para clipboard
2. **Capturar Referral** - Simula captura de deep link com `referrerId` customizado
3. **Verificar Pendente** - Mostra `referrerId` armazenado no SharedPreferences
4. **Consumir Pendente** - Consome e remove `referrerId` pendente (simula signup)
5. **Limpar Pendente** - Remove todos os dados de referral do SharedPreferences
6. **Verificar Firestore** - Busca dados do usuário e ReferralInstalls
7. **AppsFlyer ID** - Mostra o AppsFlyer Unique ID do dispositivo

---

## 🔬 Procedimentos de Teste

### Teste 1: Geração de Link (Básico)
**Objetivo**: Verificar se links são gerados corretamente

1. Abrir tela de debug (`/referral-debug`)
2. Clicar em **"Gerar Link"**
3. ✅ **Esperado**: Link copiado para clipboard no formato:
   ```
   https://boora.onelink.me/bFrs/XXXXXXX?pid=af_app_invites&c=user_invite&deep_link_value=invite&deep_link_sub2=USER_ID&af_sub1=USER_ID
   ```
4. Validar que `deep_link_sub2` contém o ID do usuário atual

---

### Teste 2: Captura Manual de Referral
**Objetivo**: Simular recebimento de deep link

1. Fazer **logout** (importante: usuário não pode estar logado)
2. Abrir tela de debug
3. Digitar `TEST_REFERRER_123` no campo "Test ReferrerId"
4. Clicar em **"Capturar Referral"**
5. ✅ **Esperado**: Log mostrando `✅ Referral capturado: TEST_REFERRER_123`
6. Clicar em **"Verificar Pendente"**
7. ✅ **Esperado**: Log mostrando `✅ Referral pendente encontrado: TEST_REFERRER_123`

---

### Teste 3: Consumo Durante Signup
**Objetivo**: Verificar integração com cadastro

1. Criar referral pendente (Teste 2)
2. Fazer signup completo com novo usuário
3. No **último step** do wizard, antes de clicar "Finalizar":
   - Abrir logs do Firebase (opcional)
   - Abrir Firestore em outra aba
4. Clicar em **"Finalizar Cadastro"**
5. ✅ **Esperado no Firestore**:
   ```javascript
   Users/{newUserId} {
     fullName: "...",
     referrerId: "TEST_REFERRER_123",
     referralSource: "appsflyer",
     referralCapturedAt: Timestamp(...)
   }
   ```
6. Aguardar 2-5 segundos (execução da Cloud Function)
7. ✅ **Esperado em ReferralInstalls**:
   ```javascript
   ReferralInstalls/{newUserId} {
     userId: newUserId,
     referrerId: "TEST_REFERRER_123",
     createdAt: Timestamp(...),
     source: "appsflyer"
   }
   ```
8. ✅ **Esperado em Users/{TEST_REFERRER_123}**:
   ```javascript
   referralInstallCount: 1, // incrementado
   referralUpdatedAt: Timestamp(...)
   ```

---

### Teste 4: Deep Link Real (Crítico)
**Objetivo**: Testar fluxo completo end-to-end

#### Pré-requisitos:
- App não pode estar instalado no device de teste
- Usar dispositivo físico (simulator não funciona para deep links)
- iOS: Permissões ATT aceitas

#### Passo a Passo:

**Dispositivo A (Referrer):**
1. Abrir InviteDrawer (botão 🎁 na home)
2. Copiar link de convite
3. Compartilhar via WhatsApp/Telegram/SMS

**Dispositivo B (Invited User):**
1. Receber e **clicar no link**
2. ✅ **Esperado**: App Store/Play Store abre
3. Se app não instalado: instalar
4. Se app já instalado: abrir (mas não vai funcionar - ver "Importante" abaixo)
5. App abre após instalação
6. Verificar logs do AppsFlyer:
   ```
   [APPSFLYER] Deep link encontrado: ...
   [REFERRAL] 📥 captureReferral chamado - referrerId: USER_ID_A
   [REFERRAL] ✅ Referral capturado e salvo: USER_ID_A
   ```
7. Fazer signup completo
8. Verificar Firestore (ver Teste 3, step 5-8)

#### ⚠️ **IMPORTANTE**: Deep Links só funcionam em **primeira instalação**

Se o app já estiver instalado no dispositivo, o AppsFlyer não consegue capturar deep link parameters. Soluções:

- **iOS**: Deletar app, clicar no link, reinstalar do zero
- **Android**: Deletar app + limpar cache, clicar no link, reinstalar
- **Simulator**: Não funciona para deep links - usar device físico

---

### Teste 5: Recompensa VIP
**Objetivo**: Verificar concessão automática de premium

1. Criar 10 usuários fake que usam o mesmo `referrerId`
   - Opção A: Signup manual (trabalhoso)
   - Opção B: Script (ver abaixo)
2. No 10º signup, verificar Cloud Function logs
3. ✅ **Esperado em Users/{referrerId}**:
   ```javascript
   referralInstallCount: 10,
   referralRewardedCount: 1,
   user_is_vip: true,
   user_level: "vip",
   vip_priority: 1,
   vipExpiresAt: Timestamp(+90 dias),
   vipProductId: "referral_bonus_3m",
   referralRewardedAt: Timestamp(...)
   ```

#### Script Helper (Node.js):
```javascript
// Executar no Firebase Console > Functions > Testes
const admin = require('firebase-admin');
const db = admin.firestore();

async function createFakeReferrals(referrerId, count) {
  for (let i = 1; i <= count; i++) {
    const fakeUserId = `FAKE_USER_${Date.now()}_${i}`;
    
    await db.collection('Users').doc(fakeUserId).set({
      fullName: `Test User ${i}`,
      referrerId: referrerId,
      referralSource: 'test',
      referralCapturedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      age: 25,
      status: 'active'
    });
    
    console.log(`✅ Created fake user ${i}/${count}`);
  }
}

// Usar o ID real do usuário que vai receber VIP
createFakeReferrals('USER_ID_AQUI', 10);
```

---

## 🐛 Troubleshooting

### Problema: Link não gera
**Sintomas**: `_generatedLink` é `null` no InviteDrawer

**Diagnóstico**:
1. Verificar logs: `grep -i "appsflyer" logs.txt`
2. Verificar `APPSFLYER_DEV_KEY` em constants.dart
3. Testar na tela de debug

**Soluções**:
- ❌ Dev Key vazia → Adicionar em `lib/core/constants/constants.dart`
- ❌ SDK não inicializado → Verificar `main.dart` (linha 111)
- ❌ Timeout → Aumentar timeout em `appsflyer_service.dart` (linha 140)

---

### Problema: Deep link não captura
**Sintomas**: Após clicar no link, `referrerId` não salva no SharedPreferences

**Diagnóstico**:
```dart
// Adicionar log em appsflyer_service.dart linha 221
AppLogger.info('🔍 onDeepLinking callback EXECUTADO', tag: 'APPSFLYER');
```

**Soluções**:
- ❌ Callback não executa → Verificar inicialização (linha 52)
- ❌ `deep_link_sub2` null → Verificar geração do link (linha 105)
- ❌ App já instalado → **Desinstalar e reinstalar** (crítico!)
- ❌ iOS ATT bloqueado → Aceitar permissão de tracking

---

### Problema: Cloud Function não dispara
**Sintomas**: `ReferralInstalls` não cria documento após signup

**Diagnóstico**:
1. Firebase Console > Functions > Logs
2. Filtrar por `[Referral]`
3. Verificar erros

**Soluções**:
- ❌ `referrerId` não existe no user doc → Verificar `cadastro_view_model.dart` linha 210
- ❌ Function não deployada → `firebase deploy --only functions:onUserCreatedReferral`
- ❌ Permissões Firestore → Verificar `firestore.rules`

---

### Problema: Recompensa VIP não concede
**Sintomas**: `referralInstallCount` = 10 mas `user_is_vip` = false

**Diagnóstico**:
```bash
# Verificar logs da Cloud Function
firebase functions:log --only onUserCreatedReferral --limit 50
```

**Soluções**:
- ❌ Lógica de threshold errada → Verificar `referrals.ts` linha 6
- ❌ Transaction falhou → Verificar erro nos logs
- ❌ Campo `referralRewardedCount` desatualizado → Resetar manualmente

---

## 📊 Métricas e Monitoramento

### AppsFlyer Dashboard
1. Login: https://hq1.appsflyer.com
2. Navegar: **Engagement** > **User Invite**
3. Métricas disponíveis:
   - Total de links gerados
   - Clicks em links
   - Instalações atribuídas
   - Taxa de conversão

### Firestore Queries Úteis

**Contar total de conversões**:
```javascript
db.collection('ReferralInstalls')
  .where('referrerId', '==', 'USER_ID')
  .get()
  .then(snap => console.log('Total:', snap.size));
```

**Listar usuários que ganharam VIP via referral**:
```javascript
db.collection('Users')
  .where('vipProductId', '==', 'referral_bonus_3m')
  .get()
  .then(snap => snap.forEach(doc => console.log(doc.data())));
```

**Top referrers**:
```javascript
db.collection('Users')
  .orderBy('referralInstallCount', 'desc')
  .limit(10)
  .get()
  .then(snap => snap.forEach(doc => 
    console.log(doc.data().fullName, doc.data().referralInstallCount)
  ));
```

---

## 🚀 Deploy Checklist

Antes de lançar em produção:

- [ ] Testar deep links em device físico iOS
- [ ] Testar deep links em device físico Android
- [ ] Verificar App ID correto em `constants.dart` (quando app publicado)
- [ ] Deploy Cloud Function: `firebase deploy --only functions:onUserCreatedReferral`
- [ ] Configurar Firestore indexes (se query falhar)
- [ ] Testar recompensa VIP (criar 10 fake users)
- [ ] Verificar permissões Firestore Rules
- [ ] Configurar ATT no iOS (Info.plist)
- [ ] Validar OneLink no AppsFlyer Dashboard
- [ ] Adicionar analytics events (opcional)
- [ ] Documentar troubleshooting para suporte

---

## 📚 Recursos Adicionais

- **AppsFlyer Docs**: https://dev.appsflyer.com/hc/docs/dl_user_invite
- **Flutter SDK**: https://github.com/AppsFlyerSDK/appsflyer-flutter-plugin
- **OneLink Tester**: https://hq1.appsflyer.com/tools/onelink-tester
- **Deep Link Debugger**: `adb logcat | grep -i appsflyer` (Android)

---

## 🔐 Segurança

### Pontos de Atenção:
1. **Auto-indicação**: Cloud Function bloqueia `referrerId === userId` (linha 31)
2. **Duplicate prevention**: Verifica se `ReferralInstalls/{userId}` já existe (linha 47)
3. **Validação de tipo**: Garante `referrerId` é string não-vazia (linha 26)
4. **Transaction safety**: Usa Firestore transaction para evitar race conditions (linha 41)

### Possíveis Abusos:
- **Fake accounts**: Implementar verificação de email/telefone no signup
- **Click farms**: Monitorar padrões suspeitos (muitos installs do mesmo IP/device)
- **Bots**: Adicionar CAPTCHA no signup (opcional)

---

## ✨ Melhorias Futuras

1. **Push notification** quando amigo cria conta
2. **Ranking de referrers** na UI
3. **Badges/achievements** para milestones (5, 25, 50 convites)
4. **Dynamic reward tiers** (10 = 90 dias, 25 = 180 dias, etc)
5. **Social proof** ("João indicou 15 amigos!")
6. **A/B testing** de incentivos diferentes
7. **Referral code** customizado (além do link)
8. **WhatsApp share button** com deep link
9. **Analytics** de qual canal gera mais conversões
10. **Admin panel** para revisar/aprovar referrals suspeitos

---

**Última atualização**: ${DateTime.now().toIso8601String()}
**Versão do SDK**: AppsFlyer 6.17.8 (Flutter)
