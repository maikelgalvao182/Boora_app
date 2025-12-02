# 🚀 Deploy do WebSocket Server - Projeto Partiu

## 📋 PRÉ-REQUISITOS

### 1. Ferramentas necessárias
- ✅ Node.js 20+ instalado
- ✅ Google Cloud CLI instalado (`gcloud`)
- ✅ Conta Google Cloud com billing ativado
- ✅ Projeto Firebase configurado

### 2. Configurar Firebase Admin
O backend precisa de credenciais do Firebase Admin SDK.

**Opção A: Application Default Credentials (Recomendado para Cloud Run)**
```bash
# Fazer login no gcloud
gcloud auth application-default login

# Definir projeto
gcloud config set project partiu-app
```

**Opção B: Service Account (Alternativo)**
1. Acesse: https://console.firebase.google.com/project/partiu-app/settings/serviceaccounts/adminsdk
2. Clique em "Gerar nova chave privada"
3. Salve o arquivo como `partiu-firebase-adminsdk.json` (NÃO commitar!)
4. Configure no código (se necessário)

---

## 🔧 PASSO 1: Configurar Variáveis de Ambiente

### Local (.env)
Edite o arquivo `.env`:
```bash
INTERNAL_SECRET=your-strong-secret-key-here
PORT=8080
FIRESTORE_PROJECT_ID=partiu-app
```

⚠️ **IMPORTANTE**: Gere um secret seguro:
```bash
# Mac/Linux
openssl rand -base64 32

# Use o resultado no INTERNAL_SECRET
```

---

## 📦 PASSO 2: Instalar Dependências

```bash
cd wedding-websocket
npm install
```

---

## 🧪 PASSO 3: Testar Localmente

### Iniciar servidor de desenvolvimento:
```bash
npm run start:dev
```

### Verificar se está funcionando:
```bash
# Abrir em outro terminal
curl http://localhost:8080/health
```

**Resposta esperada:**
```json
{
  "status": "ok",
  "connectedClients": 0,
  "uptime": 1234
}
```

### Testar conexão WebSocket (opcional):
```bash
node test-socket-connection.js
```

---

## 🌐 PASSO 4: Build para Produção

```bash
npm run build
```

Verifique se a pasta `dist/` foi criada com sucesso.

---

## 🚀 PASSO 5: Deploy no Google Cloud Run

### 5.1 - Configurar projeto do Google Cloud
```bash
# Fazer login
gcloud auth login

# Definir projeto
gcloud config set project partiu-app

# Habilitar APIs necessárias
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
```

### 5.2 - Deploy com Cloud Build
```bash
# Certifique-se de estar na pasta wedding-websocket
cd /Users/maikelgalvao/partiu/wedding-websocket

# Deploy (substitua YOUR_SECRET_KEY por um valor gerado)
gcloud run deploy partiu-websocket \
  --source . \
  --port=8080 \
  --allow-unauthenticated \
  --use-http2 \
  --region=us-central1 \
  --memory=512Mi \
  --cpu=1 \
  --timeout=3600 \
  --max-instances=10 \
  --set-env-vars INTERNAL_SECRET=YOUR_SECRET_KEY,FIRESTORE_PROJECT_ID=partiu-app
```

### 5.3 - Aguardar deploy
O processo pode levar 3-5 minutos. Ao final, você verá:
```
✓ Service [partiu-websocket] deployed successfully
  URL: https://partiu-websocket-XXXXXXXXXX-uc.a.run.app
```

⚠️ **IMPORTANTE**: Copie essa URL!

---

## ✅ PASSO 6: Testar Deploy

### Health check
```bash
curl https://partiu-websocket-XXXXXXXXXX-uc.a.run.app/health
```

### Verificar logs
```bash
gcloud run services logs read partiu-websocket \
  --region=us-central1 \
  --limit=50
```

---

## 🔄 PASSO 7: Atualizar App Flutter

Edite `lib/core/services/socket_service.dart`:

```dart
// Antes
static const String _prodUrl = 'wss://wedding-websocket-dux2nu33ua-uc.a.run.app';

// Depois
static const String _prodUrl = 'wss://partiu-websocket-XXXXXXXXXX-uc.a.run.app';
```

---

## 🧩 PASSO 8: Integração com Cloud Functions (Opcional)

Se você tiver Cloud Functions que precisam notificar o WebSocket:

### 8.1 - Configurar variáveis nas Cloud Functions
```bash
firebase functions:config:set \
  websocket.url="https://partiu-websocket-XXXXXXXXXX-uc.a.run.app" \
  websocket.secret="YOUR_SECRET_KEY"
```

### 8.2 - Exemplo de código na Cloud Function
```typescript
import * as functions from 'firebase-functions';
import axios from 'axios';

export const notifyWebSocket = functions.firestore
  .document('messages/{messageId}')
  .onCreate(async (snap, context) => {
    const config = functions.config();
    
    await axios.post(
      `${config.websocket.url}/notify`,
      {
        event: 'messages:new',
        data: snap.data(),
      },
      {
        headers: {
          'x-internal-secret': config.websocket.secret,
        },
      }
    );
  });
```

---

## 🔍 TROUBLESHOOTING

### Problema: "Permission denied"
```bash
# Dar permissões corretas ao serviço
gcloud run services add-iam-policy-binding partiu-websocket \
  --region=us-central1 \
  --member="allUsers" \
  --role="roles/run.invoker"
```

### Problema: "502 Bad Gateway"
Verifique os logs:
```bash
gcloud run services logs read partiu-websocket --region=us-central1 --limit=100
```

Causas comuns:
- App não está escutando na porta correta (deve usar `process.env.PORT`)
- Timeout muito curto (aumentar `--timeout`)
- Erro de autenticação do Firebase

### Problema: WebSocket não conecta
1. Verifique se usou `wss://` (não `ws://`)
2. Verifique se a URL está correta no Flutter
3. Verifique token do Firebase no app

### Verificar se serviço está rodando
```bash
gcloud run services describe partiu-websocket \
  --region=us-central1 \
  --format="value(status.url)"
```

---

## 📊 MONITORAMENTO

### Ver métricas no console
https://console.cloud.google.com/run/detail/us-central1/partiu-websocket/metrics

### Logs em tempo real
```bash
gcloud run services logs tail partiu-websocket \
  --region=us-central1
```

### Verificar conexões ativas
```bash
curl https://partiu-websocket-XXXXXXXXXX-uc.a.run.app/health
```

---

## 🔄 ATUALIZAR DEPLOY

Quando fizer mudanças no código:

```bash
cd wedding-websocket

# Fazer mudanças no código...

# Re-deploy (mantém as mesmas configurações)
gcloud run deploy partiu-websocket \
  --source . \
  --region=us-central1
```

---

## 💰 CUSTOS ESTIMADOS

Cloud Run é pago por uso:
- **Gratuito até**: 2 milhões de requisições/mês
- **Custo típico**: ~$5-20/mês para apps pequenos
- **Escala automática**: 0 instâncias quando não há tráfego

---

## 🔒 SEGURANÇA

### Recomendações:
1. ✅ Usar INTERNAL_SECRET forte (gerado com `openssl rand -base64 32`)
2. ✅ Nunca commitar `.env` ou service account keys
3. ✅ Usar HTTPS/WSS sempre
4. ✅ Validar tokens do Firebase em todas as conexões
5. ✅ Limitar `--max-instances` para evitar custos inesperados

### Adicionar ao .gitignore:
```
wedding-websocket/.env
wedding-websocket/node_modules/
wedding-websocket/dist/
wedding-websocket/*-firebase-adminsdk*.json
```

---

## 📝 CHECKLIST FINAL

- [ ] Node.js e npm instalados
- [ ] gcloud CLI configurado
- [ ] Projeto Firebase configurado
- [ ] `.env` criado com valores corretos
- [ ] `npm install` executado
- [ ] Testado localmente (`npm run start:dev`)
- [ ] Deploy no Cloud Run executado
- [ ] URL do WebSocket copiada
- [ ] URL atualizada no Flutter (`socket_service.dart`)
- [ ] Health check funcionando
- [ ] Logs verificados
- [ ] App Flutter testado com backend

---

## 📚 RECURSOS ADICIONAIS

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [NestJS Documentation](https://docs.nestjs.com/)
- [Socket.IO Documentation](https://socket.io/docs/v4/)
- [Firebase Admin SDK](https://firebase.google.com/docs/admin/setup)

---

**Data de criação**: 2 de dezembro de 2025  
**Projeto**: Partiu WebSocket Backend  
**Status**: ✅ Pronto para deploy
