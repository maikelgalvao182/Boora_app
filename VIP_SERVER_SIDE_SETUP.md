# 🔒 VIP SERVER-SIDE — SETUP COMPLETO

## ✅ IMPLEMENTAÇÃO CONCLUÍDA

Controle de acesso VIP implementado com **segurança server-side real**.

---

## 📋 O QUE FOI IMPLEMENTADO

### 1. **Webhook RevenueCat → Firestore** ✅
- **Arquivo**: `functions/src/webhooks/revenuecat-webhook.ts`
- **Responsabilidade**: Sincronizar status VIP do RevenueCat para o Firestore
- **Campos atualizados no Firestore**:
  - `vipExpiresAt`: Timestamp de expiração
  - `vipProductId`: ID do produto (monthly/annual)
  - `vipUpdatedAt`: Última atualização

### 2. **Firestore Security Rules** ✅
- **Arquivo**: `firestore.rules`
- **Função adicionada**: `isVip(userId)` — valida se `vipExpiresAt > request.time`
- **Proteção em**: `ProfileVisits/{visitId}`
  - ❌ **Leitura bloqueada** para não-VIPs
  - ✅ **Escrita liberada** para registrar visitas

### 3. **Client-Side UX** ✅
- **ProfileVisitsChip**: Check VIP antes de navegar
- **AppNotifications**: Check VIP antes de navegar para profile visits
- **Objetivo**: Evitar navegação inútil (UX apenas, não substitui Rules)

### 4. **Modelo User atualizado** ✅
- Campos VIP adicionados:
  - `vipExpiresAt` (DateTime?)
  - `vipProductId` (String?)
  - `vipUpdatedAt` (DateTime?)
- Getter: `hasActiveVip` → valida se `vipExpiresAt > DateTime.now()`

---

## 🚀 DEPLOY CHECKLIST

### **1. Configurar Secret no Firebase**

```bash
# Na pasta functions/
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
```

**Valor recomendado**: Um token seguro (32+ caracteres)
```bash
openssl rand -base64 32
```

---

### **2. Deploy das Cloud Functions**

```bash
cd functions
npm install
npm run build
firebase deploy --only functions:revenueCatWebhook
```

---

### **3. Deploy das Firestore Rules**

```bash
firebase deploy --only firestore:rules
```

---

### **4. Configurar Webhook no RevenueCat**

1. Acesse: **RevenueCat Dashboard** → Project Settings → Integrations → Webhooks
2. Configure:
   - **URL**: `https://us-central1-<YOUR_PROJECT_ID>.cloudfunctions.net/revenueCatWebhook`
   - **Authorization**: `Bearer <SEU_SECRET_DO_PASSO_1>`
   - **Events para ativar**:
     - ✅ `INITIAL_PURCHASE`
     - ✅ `RENEWAL`
     - ✅ `EXPIRATION`
     - ✅ `CANCELLATION`
     - ✅ `UNCANCELLATION`

3. **Testar webhook**: RevenueCat tem opção "Send Test" no dashboard

---

### **5. Migração de Usuários Existentes (Opcional)**

Se já tem usuários VIP no RevenueCat, rode este script para sincronizar:

```typescript
// functions/src/scripts/syncVipUsers.ts
import * as admin from 'firebase-admin';
import {Purchases} from '@revenuecat/purchases-typescript';

async function syncExistingVipUsers() {
  const db = admin.firestore();
  
  // Configure RevenueCat API
  const rc = new Purchases({apiKey: 'YOUR_REVENUECAT_API_KEY'});
  
  const usersSnapshot = await db.collection('Users').get();
  
  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;
    
    try {
      // Busca customer info do RevenueCat
      const customer = await rc.getCustomerInfo(userId);
      
      // Verifica se tem entitlement ativo
      const entitlement = customer.entitlements.active['vip']; // Seu entitlement ID
      
      if (entitlement && entitlement.expirationDate) {
        await userDoc.ref.update({
          vipExpiresAt: admin.firestore.Timestamp.fromDate(
            new Date(entitlement.expirationDate)
          ),
          vipProductId: entitlement.productIdentifier,
          vipUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        console.log(`✅ Sincronizado: ${userId}`);
      }
    } catch (error) {
      console.error(`❌ Erro ao sincronizar ${userId}:`, error);
    }
  }
}
```

---

## 🔍 VALIDAÇÃO

### **Teste 1: Webhook funcionando**

```bash
# Logs da Cloud Function
firebase functions:log --only revenueCatWebhook
```

Deve mostrar:
```
📥 RevenueCat: INITIAL_PURCHASE → userId123
✅ userId123 → VIP até 2026-01-12
```

---

### **Teste 2: Firestore Rules bloqueando**

No console do Firebase:
1. Vá em **Firestore → Rules Playground**
2. Teste:
   ```
   Operação: get
   Path: /ProfileVisits/abc123
   Simulate: Como usuário sem VIP
   ```
   
   ❌ Deve retornar: **Permission Denied**

---

### **Teste 3: Client-side funcionando**

1. **Usuário SEM VIP**:
   - Tenta clicar em "Profile Visits" → VIP Dialog aparece ✅
   - Se tentar forçar navegação → Firestore retorna erro ✅

2. **Usuário COM VIP**:
   - Clica em "Profile Visits" → Navega normalmente ✅
   - Vê lista de visitas ✅

---

## 🛡️ SEGURANÇA

### **Camadas de proteção**:

1. ✅ **RevenueCat Webhook** (fonte da verdade)
2. ✅ **Firestore Rules** (bloqueio real)
3. ✅ **Client-side check** (UX apenas)

### **O que acontece se alguém burlar o app**:

❌ Modificar código do app → **Firestore Rules bloqueiam**
❌ Manipular `vipExpiresAt` no Firestore → **Rules validam automaticamente**
❌ Forçar requisição direta → **Rules bloqueiam**

---

## 📊 COMPARAÇÃO

| Antes | Depois |
|-------|--------|
| ❌ Validação apenas client-side | ✅ Validação server-side |
| ❌ RevenueCat não sincroniza Firestore | ✅ Webhook mantém Firestore atualizado |
| ❌ Rules não sabem sobre VIP | ✅ Rules validam `vipExpiresAt` |
| ❌ Facilmente burlável | ✅ Segurança real |

---

## 🔧 TROUBLESHOOTING

### **Webhook não está disparando**

1. Verifique se a URL está correta no RevenueCat Dashboard
2. Teste o webhook manualmente no RevenueCat ("Send Test")
3. Verifique logs: `firebase functions:log --only revenueCatWebhook`

### **Usuário VIP não consegue acessar**

1. Verifique se `vipExpiresAt` está no futuro:
   ```javascript
   db.collection('Users').doc('userId').get()
   ```
2. Verifique se Rules estão atualizadas:
   ```bash
   firebase deploy --only firestore:rules
   ```

### **RevenueCat diz que é VIP mas Firestore não**

Execute sync manual do usuário:
```typescript
// No webhook, faça POST manual com o userId
```

---

## 📚 ARQUIVOS MODIFICADOS

1. ✅ `functions/src/webhooks/revenuecat-webhook.ts` (novo)
2. ✅ `functions/src/index.ts` (export adicionado)
3. ✅ `firestore.rules` (função `isVip` + proteção ProfileVisits)
4. ✅ `lib/core/models/user.dart` (campos VIP)
5. ✅ `lib/features/notifications/helpers/app_notifications.dart` (check VIP)
6. ✅ `lib/features/profile/presentation/widgets/profile_visits_chip.dart` (já tinha check)

---

## ✅ CONCLUSÃO

**Agora você tem segurança real server-side.**

- ✅ Firestore Rules **bloqueiam** acesso não autorizado
- ✅ RevenueCat Webhook **mantém** Firestore sincronizado
- ✅ Client-side apenas **melhora UX** (não é segurança)

**Nada de overengineering. Só o essencial. 🎯**
