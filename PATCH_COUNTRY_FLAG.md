# Patch: Adicionar Campos de País e Bandeira

## 📋 Descrição

Cloud Function para adicionar os campos `from` (país) e `flag` (bandeira) em todos os usuários da coleção `users`.

## 🎯 O que faz

- Adiciona `from: "Brasil"` em usuários sem país ou com campo vazio
- Adiciona `flag: "🇧🇷"` (emoji da bandeira do Brasil) em todos os usuários

## 🚀 Como Executar

### Opção 1: Via Firebase Console

1. Acesse o [Firebase Console](https://console.firebase.google.com/)
2. Navegue para **Functions** > **patchAddCountryFlag**
3. Clique em **Testing** e execute a função

### Opção 2: Via cURL

```bash
curl -X POST https://southamerica-east1-partiu-479902.cloudfunctions.net/patchAddCountryFlag \
  -H "Content-Type: application/json" \
  -d '{"adminKey": "patch-2025"}'
```

### Opção 3: Via Firebase CLI

```bash
firebase functions:shell
# No shell:
patchAddCountryFlag({adminKey: 'patch-2025'})
```

## 🔒 Segurança

A função requer uma chave administrativa `adminKey` para ser executada. A chave padrão é `patch-2025`.

Para alterar a chave:

```bash
firebase functions:config:set admin.key="SUA_CHAVE_SECRETA"
firebase deploy --only functions:patchAddCountryFlag
```

## 📊 Resposta Esperada

```json
{
  "success": true,
  "totalUpdated": 150,
  "message": "Patch concluído! 150 usuários atualizados."
}
```

## ⚙️ Personalização

Para alterar o país/bandeira padrão, edite o arquivo `functions/src/patchAddCountryFlag.ts`:

```typescript
const DEFAULT_COUNTRY = "Brasil";
const DEFAULT_FLAG = "🇧🇷";
```

Emojis de bandeiras comuns:
- 🇧🇷 Brasil
- 🇺🇸 Estados Unidos
- 🇵🇹 Portugal
- 🇪🇸 Espanha
- 🇲🇽 México
- 🇦🇷 Argentina

## 🔄 Batch Processing

A função processa em lotes de 500 usuários para evitar timeouts e respeitar os limites do Firestore.

## 📝 Logs

Acompanhe os logs em tempo real:

```bash
firebase functions:log --only patchAddCountryFlag
```

Ou no [Firebase Console](https://console.firebase.google.com/) > Functions > Logs
