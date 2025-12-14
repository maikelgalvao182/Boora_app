# 🧩 Firestore Security Rules - Arquitetura Modular

## 📁 Estrutura

Este diretório contém as **regras modulares** do Firestore Security Rules, organizadas por contexto/coleção:

```
rules/
├── README.md                 ← Você está aqui
├── helpers.rules             → Funções auxiliares reutilizáveis
├── users.rules               → Coleção Users/{userId}
├── app_config.rules          → Coleção AppInfo/{configName}
├── notifications.rules       → Coleção Notifications/{notificationId}
├── device_tokens.rules       → Coleção DeviceTokens/{tokenId}
├── reviews.rules             → Coleções Reviews + PendingReviews
├── events.rules              → Coleção events/{eventId}
├── applications.rules        → Coleção EventApplications/{applicationId}
├── event_chats.rules         → Coleção EventChats/{eventId} + subcoleções
├── connections.rules         → Coleção Connections/{userId}/Conversations/{withUserId}
├── messages.rules            → Coleção Messages/{userId}/{partnerId}/{messageId}
├── profile_visits.rules      → Coleções ProfileVisits + ProfileViews
├── ranking.rules             → Coleções userRanking + locationRanking
├── reports.rules             → Coleção reports/{reportId}
└── didit.rules               → Coleções FaceVerifications + DiditSessions + DiditWebhooks
```

---

## ✅ Fluxo Correto de Edição

### 1️⃣ **Editar regras nos arquivos modulares**

```bash
# Exemplo: editar regras de usuários
vim rules/users.rules

# Ou adicionar nova coleção
vim rules/minha_colecao.rules
```

### 2️⃣ **Compilar para arquivo único**

```bash
# Na raiz do projeto
./build-rules.sh
```

Isso gera automaticamente o arquivo `firestore.rules` (que está no `.gitignore`).

### 3️⃣ **Fazer deploy**

```bash
# Deploy APENAS das rules (rápido)
firebase deploy --only firestore:rules

# Ou deploy completo (se necessário)
firebase deploy
```

---

## ❌ Fluxo ERRADO (não faça isso)

```bash
# ❌ NÃO EDITE DIRETAMENTE firestore.rules
vim firestore.rules

# Se fizer isso, suas mudanças serão perdidas quando rodar ./build-rules.sh
```

---

## 🆕 Adicionar Nova Coleção

1. **Criar arquivo modular** (ex: `rules/minha_colecao.rules`)

```javascript
/// 🔥 Descrição da coleção
/// Path: MinhaColecao/{docId}

match /MinhaColecao/{docId} {
  allow read: if isSignedIn();
  allow write: if isOwner(docId);
}
```

2. **Editar `build-rules.sh`** para incluir o novo arquivo:

```bash
echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🔥 Minha Coleção" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/minha_colecao.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
```

3. **Recompilar e fazer deploy**:

```bash
./build-rules.sh
firebase deploy --only firestore:rules
```

---

## 🔍 Testar Regras Localmente

Você pode testar as regras localmente usando o **Firebase Emulator**:

```bash
# Iniciar emulador
firebase emulators:start --only firestore

# Testar em outro terminal
npm test
```

---

## 📝 Convenções

### Comentários

- Use comentários com emojis para facilitar navegação visual
- Documente paths, estrutura de dados e casos de uso

### Helpers

- Todas as funções auxiliares devem estar em `helpers.rules`
- Use nomes descritivos: `isOwner()`, `isEventCreator()`, `isVip()`

### Organização

- Uma coleção principal por arquivo
- Subcoleções no mesmo arquivo da coleção pai
- Mantenha regras simples e legíveis

---

## 🚀 Vantagens da Arquitetura Modular

✅ **Manutenibilidade**: Editar uma coleção sem afetar outras  
✅ **Legibilidade**: Arquivos pequenos e focados  
✅ **Colaboração**: Evita conflitos de merge  
✅ **Reutilização**: Funções auxiliares centralizadas  
✅ **Versionamento**: Git diff mostra exatamente o que mudou  

---

## 🔧 Troubleshooting

### Problema: Deploy falhou

```bash
# Verificar sintaxe
firebase deploy --only firestore:rules --debug

# Testar localmente primeiro
firebase emulators:start --only firestore
```

### Problema: Arquivo gerado está diferente

```bash
# Forçar rebuild
rm firestore.rules
./build-rules.sh
git diff firestore.rules
```

---

## 📚 Referências

- [Firebase Security Rules Docs](https://firebase.google.com/docs/firestore/security/get-started)
- [Rules Playground](https://firebase.google.com/docs/rules/simulator)
- [Common Patterns](https://firebase.google.com/docs/firestore/security/rules-structure)
