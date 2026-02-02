# 📱 Device Registry + Blacklist (Flutter + Firebase)

> Implementação completa de registro de dispositivo e blacklist por deviceIdHash, compatível com Android, iOS e Web.

---

## ✅ Objetivo

- Coletar informações do dispositivo com `client_information`.
- Gerar hash SHA-256 do `deviceId` (nunca salvar o deviceId cru).
- Registrar o dispositivo na subcoleção do usuário via Cloud Function.
- Verificar se o dispositivo está bloqueado antes de permitir login/onboarding.
- Quando `Users/{uid}.status` virar `inactive`, inserir os dispositivos do usuário na blacklist.
- Definir claramente o comportamento de reversão (reativar usuário e/ou reverter blacklist).

---

## 🧱 Estrutura do Firestore

```text
Users/{uid}
  status: "active" | "inactive"
  createdAt
  updatedAt
  ...

Users/{uid}/clients/{deviceIdHash}
  deviceIdHash
  platform
  deviceName
  osName
  osVersion
  appVersion
  buildCode
  applicationName
  firstSeenAt
  lastSeenAt
  createdAt
  updatedAt

BlacklistDevices/{deviceIdHash}
  deviceIdHash
  active
  reason
  banType
  banUntil
  userId
  platform
  deviceName
  osName
  osVersion
  appVersion
  buildCode
  createdAt
  updatedAt
```

**Justificativa:** usar `deviceIdHash` como `docId` reduz leituras e simplifica `upsert`.

### Campos adicionais recomendados

- **banType**: `deviceOnly` | `accountDevice` | `temporary`
- **banUntil**: timestamp (opcional, para ban temporário)

Esses campos aumentam a flexibilidade sem exigir mudanças no app depois.

---

## 🔐 Regras do Firestore

Regras adicionadas:

- **BlacklistDevices**: leitura/escrita bloqueada para o client.
- **Users/{uid}/clients**: escrita **somente** via Cloud Functions.

Se o app não precisa ler `clients`, pode bloquear leitura também para reduzir superfície de dados.

Arquivos:
- rules/device_blacklist.rules
- rules/users.rules

---

## ☁️ Cloud Functions (TypeScript)

Arquivo: `functions/src/devices/deviceBlacklist.ts`

### 1) checkDeviceBlacklist (Callable)

- **Entrada:** `deviceIdHash`, `platform`
- **Saída:** `{ blocked: boolean, reason?: string }`
- **Autenticação:** Não exigida (permite checagem antes do cadastro)

### 2) registerDevice (Callable)

- **Entrada:** `uid`, `deviceIdHash`, `platform`, `deviceName`, `osName`, `osVersion`, `appVersion`, `buildCode`, `applicationName`
- **Validação:** `context.auth.uid` deve ser igual a `uid`
- **Ação:** grava/atualiza em `Users/{uid}/clients/{deviceIdHash}`

### 3) onUserStatusChange (Trigger)

- Dispara quando `Users/{uid}.status` muda para `inactive`
- Busca todos os `clients` do usuário
- Cria/ativa `BlacklistDevices/{deviceIdHash}`

**Idempotência:** como o docId é o `deviceIdHash`, reprocessar não duplica dados.

### Status reversível

Decida o comportamento quando o usuário volta para `active`:

- **Ban permanente por device:** não remove da blacklist.
- **Ban reversível:** ao voltar para `active`, definir `active=false` (ou usar `banUntil`).

Hoje o fluxo apenas ativa. Isso é válido, mas precisa estar explícito na regra de negócio.

---

## 📲 Flutter - Serviço de Identidade

### DeviceIdentityService

Responsável por:
- Coletar `ClientInformation`
- Gerar SHA-256
- Chamar `checkDeviceBlacklist` e `registerDevice`

Arquivo: `lib/core/services/device_identity_service.dart`

### DeviceRepository

Responsável por chamar as Functions:
- `checkDeviceBlacklist`
- `registerDevice`

Arquivo: `lib/shared/repositories/device_repository.dart`

---

## 🔁 Fluxo no app

### ✅ Pós-login

1. Coleta info do dispositivo
2. Gera `deviceIdHash`
3. Chama `checkDeviceBlacklist`
4. Se bloqueado → logout + toast de erro
5. Se ok → chama `registerDevice`

Integrado em: `AuthSyncService`

### ⚠️ UX e loop de login

Para evitar loop de auto-login:

- Se bloqueado, deslogar e navegar para uma **tela de bloqueio** dedicada.
- Cachear localmente o resultado do bloqueio por alguns minutos para evitar chamadas repetidas.

### ✅ Pré-cadastro / onboarding

```dart
final result = await DeviceIdentityService.instance.checkDeviceBlacklist();
if (result.blocked) {
  ToastService.showError(
    message: result.reason ?? 'Dispositivo bloqueado. Contate o suporte.',
  );
  return; // bloqueia cadastro/onboarding
}
```

---

## 🔧 Dependências

Adicionado em `pubspec.yaml`:

```yaml
client_information: ^2.2.0
crypto: ^3.0.6
```

---

## 🔐 Hash com plataforma

Para reduzir colisões entre plataformas, recomenda-se calcular o hash como:

```
sha256("$platform:$deviceId")
```

O `platform` continua salvo no Firestore para análise e auditoria.

---

## 🌐 Observações Web

- No web, `deviceId` é um UUID salvo em cookie.
- Se o usuário limpar cookies, o `deviceId` pode mudar.

---

## 🛠️ Deploy

1. **Gerar regras:**
   ```bash
   ./build-rules.sh
   ```

2. **Deploy rules:**
   ```bash
   firebase deploy --only firestore:rules
   ```

3. **Deploy functions:**
   ```bash
   firebase deploy --only functions
   ```

---

## ✅ Checklist Final

- [x] Cloud Functions criadas
- [x] DeviceIdentityService implementado
- [x] DeviceRepository implementado
- [x] Regras de Firestore bloqueando blacklist
- [x] Registro automático no login
- [x] Checagem antes de onboarding/cadastro

---

## 📌 Arquivos Alterados

- functions/src/devices/deviceBlacklist.ts
- functions/src/index.ts
- lib/core/services/device_identity_service.dart
- lib/core/models/device_identity.dart
- lib/shared/repositories/device_repository.dart
- lib/core/services/auth_sync_service.dart
- rules/device_blacklist.rules
- rules/users.rules
- build-rules.sh
- pubspec.yaml

