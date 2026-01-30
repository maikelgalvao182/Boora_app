# 🚀 Guia de Deploy: users_preview Collection

## 📋 Overview

**Objetivo**: Reduzir custos de leitura do Ranking Tab em 40-60% adicional usando coleção otimizada.

**Economia total estimada**:
- Antes: ~2.000-3.000 reads/sessão
- Com otimizações anteriores: ~300-600 reads/sessão (**-80-85%**)
- Com users_preview: ~150-300 reads/sessão (**-90-92% total**)

**Zero Downtime**: Implementação segura sem quebrar a aplicação atual.

---

## ⚙️ O que foi implementado

### 1. Cloud Function: `onUserWriteUpdatePreview`
**Arquivo**: `functions/src/users/usersPreviewSync.ts`

**Trigger**: `Users/{userId}` (onCreate, onUpdate, onDelete)

**Comportamento**:
- Cria/atualiza `users_preview/{userId}` automaticamente
- Mantém 6 campos de exibição + `updatedAt`: `fullName`, `photoUrl`, `locality`, `state`, `overallRating`, `jobTitle`, `updatedAt`
- Delete cascade: se User for deletado, preview também é

### 2. Script de Migração: `migrate_users_preview.js`
**Arquivo**: `functions/migrate_users_preview.js`

**Funcionalidade**:
- Popula `users_preview` com dados de todos os usuários existentes
- Batch processing (500 docs por lote)
- Suporta dry-run para simular sem escrever
- Validação automática pós-migração

### 3. Service Layer: `people_ranking_service.dart`
**Arquivo**: `lib/features/home/data/services/people_ranking_service.dart`

**Mudança**:
```dart
// ANTES:
.collection('Users')

// DEPOIS:
.collection('users_preview')
```

---

## 🛡️ Estratégia de Deploy (Zero Downtime)

### **FASE 1: Preparação (Backend)**

#### 0. Regras do Firestore (obrigatório)
Adicionar regra de leitura para `users_preview` em [rules/users.rules](rules/users.rules) e rebuildar:
```bash
./build-rules.sh
firebase deploy --only firestore:rules
```

#### 1.1. Deploy da Cloud Function
```bash
cd functions
npm install
firebase deploy --only functions:onUserWriteUpdatePreview
```

**Validação**:
- [ ] Function deployed com sucesso
- [ ] Verificar logs: `firebase functions:log --only onUserWriteUpdatePreview`
- [ ] Criar um usuário de teste e verificar se `users_preview` é criado automaticamente

#### 1.2. Popular dados existentes (Migração)
```bash
cd functions

# Simular primeiro (dry-run)
node migrate_users_preview.js --dry-run

# Se tudo OK, executar migração real
node migrate_users_preview.js
```

**Validação**:
- [ ] Script completou sem erros
- [ ] Contagem: `Users` = `users_preview` (output do próprio script)
- [ ] Spot check: comparar 3-5 documentos manualmente no Firebase Console

**Exemplo de validação manual**:
```javascript
// No Firebase Console (Firestore)
// 1. Pegar um ID aleatório de Users
// 2. Verificar se existe em users_preview com os 6 campos corretos
```

---

### **FASE 2: Teste em Dev (App)**

#### 2.1. Mudança isolada e testável
Já aplicada em: [people_ranking_service.dart](lib/features/home/data/services/people_ranking_service.dart#L206-L208)

```dart
final usersSnapshot = await _firestore
    .collection('users_preview')  // ✅ Mudança aplicada
    .where(FieldPath.documentId, whereIn: chunk)
    .get();
```

#### 2.2. Testes locais
```bash
# Rodar app em dev/staging com Firebase Emulators (opcional)
flutter run -d <device>

# OU usar Firebase dev/staging project
flutter run --dart-define=FIREBASE_ENV=dev
```

**Checklist de validação**:
- [ ] Ranking Tab carrega normalmente
- [ ] Cards exibem: foto, nome, cidade, rating, ocupação ✅
- [ ] Filtros de estado/cidade funcionam
- [ ] Sem crashes ou erros de "field not found"
- [ ] Performance melhorou (verificar logs de tempo)

---

### **FASE 3: Deploy em Produção**

#### 3.1. Preparação
```bash
# Garantir que branch main está atualizada
git checkout main
git pull origin main

# Verificar que todas as changes estão committed
git status
```

#### 3.2. Build e deploy do app
```bash
# Android
flutter build apk --release
# ou
flutter build appbundle --release

# iOS
flutter build ios --release
```

#### 3.3. Deploy via CI/CD ou manual
- Upload para Play Console / App Store Connect
- Rollout gradual recomendado: 10% → 50% → 100%

---

## 🚨 Rollback Strategy

### Se algo der errado no app (cards não aparecem, crashes):

**Rollback instantâneo** (1 linha):
```dart
// people_ranking_service.dart, linha ~206
final usersSnapshot = await _firestore
    .collection('Users')  // ⬅️ Voltar para Users
    .where(FieldPath.documentId, whereIn: chunk)
    .get();
```

**Rebuild e redeploy**:
```bash
flutter build apk --release
# Upload emergencial para Play Store
```

**Nota**: Cloud Function e `users_preview` podem permanecer ativos sem causar problemas - são apenas custos extras de write (mínimo). O app só deve apontar para `users_preview` após migração concluída + rules liberadas.

---

## 📊 Monitoramento Pós-Deploy

### Métricas para acompanhar (manual ou via Analytics):

1. **Firestore Reads**:
   - Firebase Console → Firestore → Usage tab
   - Verificar redução de ~40-60% nos reads da collection Users
   - Aumento proporcional em users_preview (muito menor em bytes)

2. **Custos**:
   - Firebase Console → Billing → Firestore costs
   - Comparar custo/dia antes e depois

3. **Performance do App**:
   - Tempo de carregamento do Ranking Tab
   - Verificar logs: `[PeopleRankingService] PASSO 3` duration

4. **Erros**:
   - Firebase Console → Functions → Logs
   - Verificar se `onUserWriteUpdatePreview` está rodando sem erros

---

## ✅ Checklist Final de Validação

### Antes de considerar deploy completo:

- [ ] **Cloud Function**:
  - [ ] Deployed e ativa
  - [ ] Logs sem erros críticos (últimas 24h)
  - [ ] Teste de criação/update de usuário funciona

- [ ] **Collection users_preview**:
  - [ ] Existe no Firestore
  - [ ] Contém todos os usuários (count = Users)
  - [ ] Documentos têm os 6 campos corretos

- [ ] **App (Dev)**:
  - [ ] Ranking carrega corretamente
  - [ ] Cards exibem todos os dados
  - [ ] Filtros funcionam
  - [ ] Sem crashes

- [ ] **App (Prod)**:
  - [ ] Rollout gradual iniciado
  - [ ] Nenhum spike de crashes no Firebase Crashlytics
  - [ ] Reads de Firestore reduziram conforme esperado

---

## 🎯 Estimativa de Impacto

### Antes (sem otimizações):
```
Ranking load: 500 Reviews + 500 Users (full docs ~5KB cada)
= 1.000 reads × 2,5KB média = ~2,5 MB transferidos
Custo: ~1.000 reads × $0.06/100k = $0.0006/load
Sessões/dia: 10.000 × 2.5 loads = 25.000 reads/dia
Custo/dia: ~$0.15
Custo/mês: ~$4.50
```

### Depois (com todas otimizações + users_preview):
```
Ranking load: 150 Reviews + 150 users_preview (500 bytes cada)
= 300 reads × 500 bytes média = ~150 KB transferidos
Custo: ~300 reads × $0.06/100k = $0.00018/load
Sessões/dia: 10.000 × 1.5 loads = 4.500 reads/dia
Custo/dia: ~$0.027
Custo/mês: ~$0.81
```

**Economia mensal**: ~$3.69 (**-82%**)

---

## 🛠️ Troubleshooting

### Problema: Cards não aparecem após deploy

**Diagnóstico**:
```bash
# Verificar se users_preview existe
# Firebase Console → Firestore → users_preview

# Verificar logs da migração
grep "users_preview" functions/migrate_users_preview.log
```

**Solução**:
1. Verificar se migração rodou completamente
2. Se necessário, rodar novamente: `node migrate_users_preview.js`
3. Se ainda falhar: rollback para `Users` collection

### Problema: Alguns usuários faltando no ranking

**Diagnóstico**:
- Verificar se esses usuários têm documento em `users_preview`
- Verificar logs da Cloud Function: erros ao sincronizar?

**Solução**:
1. Identificar IDs faltantes
2. Re-sync manual via script:
```javascript
const admin = require('firebase-admin');
const userIds = ['userId1', 'userId2', ...];
// ... buscar de Users e criar em users_preview
```

### Problema: Cloud Function falhando

**Diagnóstico**:
```bash
firebase functions:log --only onUserWriteUpdatePreview --limit 50
```

**Soluções comuns**:
- Verificar quotas do Firebase (writes/day)
- Verificar se há erros de permissão
- Redeploy: `firebase deploy --only functions:onUserWriteUpdatePreview`

---

## 📚 Arquivos Modificados

1. `functions/src/users/usersPreviewSync.ts` ✅ (criado)
2. `functions/src/index.ts` ✅ (export adicionado)
3. `functions/migrate_users_preview.js` ✅ (criado)
4. `lib/features/home/data/services/people_ranking_service.dart` ✅ (1 linha modificada)

---

## 🔮 Próximos Passos Opcionais

1. **Telemetria**: Adicionar analytics para medir reads reais
2. **Índices Firestore**: Otimizar queries com composite indexes
3. **Ranking Agregado**: Considerar rankings pré-computados (só se >70% usa filtros globais/estado)

---

**✅ Deploy pronto para execução!**

Qualquer dúvida ou problema, consulte este guia ou verifique os logs em cada etapa.
