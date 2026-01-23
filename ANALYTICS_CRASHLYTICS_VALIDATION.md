# 📊 Guia de Validação - Firebase Analytics & Crashlytics

## 🔧 Setup Completo

### Pacotes Instalados
- `firebase_analytics: ^12.1.1`
- `firebase_crashlytics: ^5.0.7`

### Configurações Android
- ✅ Plugin `com.google.firebase.crashlytics` adicionado em `settings.gradle.kts`
- ✅ Plugin aplicado em `app/build.gradle.kts`

### Configurações iOS
- O Firebase Crashlytics já é configurado automaticamente via CocoaPods

---

## ✅ Checklist de Validação

### 1. Validar Crashlytics (Erros)

#### Opção A: Crash Fatal (recomendado para primeira validação)
```dart
// Em qualquer lugar do app (ex: botão de debug)
import 'package:partiu/core/services/analytics_service.dart';

// Isso vai crashar o app propositalmente
AnalyticsService.instance.forceCrashForTesting();
```

**Passos:**
1. Rode o app em **release mode**: `flutter run --release`
2. Chame `forceCrashForTesting()` (via botão ou console)
3. O app vai fechar
4. Abra o app novamente (o crash é enviado ao reabrir)
5. Aguarde ~5 minutos
6. Verifique no [Firebase Console > Crashlytics](https://console.firebase.google.com/)

#### Opção B: Erro Não-Fatal (não fecha o app)
```dart
// Envia um erro de teste sem crashar
await AnalyticsService.instance.sendTestError();
```

---

### 2. Validar Analytics (Eventos)

#### Habilitar DebugView (ver eventos em tempo real)

**Android:**
```bash
# Habilita modo debug para o app
adb shell setprop debug.firebase.analytics.app com.maikelgalvao.partiu

# Para desabilitar depois:
adb shell setprop debug.firebase.analytics.app .none.
```

**iOS:**
1. No Xcode, vá em Product > Scheme > Edit Scheme
2. Em "Run" > "Arguments" > "Arguments Passed On Launch"
3. Adicione: `-FIRDebugEnabled`

#### Verificar Eventos
1. Abra o [Firebase Console > Analytics > DebugView](https://console.firebase.google.com/)
2. Rode o app
3. Você deve ver eventos em tempo real:
   - `session_start` - ao abrir o app
   - `session_end` - ao minimizar (com `duration_sec`)
   - `login` - ao fazer login
   - `sign_up` - ao criar conta

---

### 3. Eventos Implementados

| Evento | Quando Dispara | Parâmetros |
|--------|----------------|------------|
| `session_start` | App entra em foreground | - |
| `session_end` | App vai para background | `duration_sec` |
| `sign_up` | Usuário cria conta | `signUpMethod` (email/google/apple) |
| `login` | Usuário faz login | `loginMethod` (email/google/apple) |
| `event_created` | Usuário cria evento | `event_id`, `category`, `emoji` |
| `event_joined` | Usuário participa de evento | `event_id`, `category` |
| `message_sent` | Usuário envia mensagem | `event_id`, `is_group_chat` |
| `vip_purchase` | Usuário compra VIP | `plan`, `price`, `currency` |

---

## 📈 Métricas para Analisar

### DAU (Daily Active Users)
- **Onde:** Firebase Console > Analytics > Dashboard
- **Métrica:** "Usuários ativos" por dia

### Tempo no App
- **Onde:** Firebase Console > Analytics > Eventos > `session_end`
- **Parâmetro:** `duration_sec` (média por sessão)

### Usuários que Criaram Conta e Não Voltaram
- **Onde:** Firebase Console > Analytics > Explorar (Explorations)
- **Query:** 
  1. Crie uma exploração de funil
  2. Passo 1: `sign_up`
  3. Passo 2: `session_start` (após 1/7/30 dias)
  4. Veja a taxa de drop-off

### Retenção
- **Onde:** Firebase Console > Analytics > Retenção
- **Métrica:** D1, D7, D30 retention

---

## 🔐 Upload de Símbolos (Stack Traces Legíveis)

Se você usa `--obfuscate` ou `--split-debug-info`, precisa enviar os símbolos.

### Android
Os símbolos são enviados automaticamente pelo plugin Gradle do Crashlytics.

### iOS
Adicione um script de build no Xcode:
1. Abra `ios/Runner.xcworkspace`
2. Selecione o target "Runner"
3. Vá em "Build Phases"
4. Adicione "New Run Script Phase" com:

```bash
"${PODS_ROOT}/FirebaseCrashlytics/run"
```

### Flutter com --split-debug-info
```bash
# Build com debug info separado
flutter build apk --release --split-debug-info=build/symbols --obfuscate

# Upload manual dos símbolos (se necessário)
firebase crashlytics:symbols:upload --app=APP_ID build/symbols
```

---

## 🧪 Código de Teste Rápido

Adicione temporariamente em alguma tela de debug:

```dart
import 'package:partiu/core/services/analytics_service.dart';

// Botões de teste
ElevatedButton(
  onPressed: () => AnalyticsService.instance.forceCrashForTesting(),
  child: Text('⚠️ Forçar Crash'),
),
ElevatedButton(
  onPressed: () => AnalyticsService.instance.sendTestError(),
  child: Text('📤 Enviar Erro Teste'),
),
ElevatedButton(
  onPressed: () => AnalyticsService.instance.logEvent('test_event', parameters: {'foo': 'bar'}),
  child: Text('📊 Enviar Evento Teste'),
),
```

---

## ⚠️ Troubleshooting

### Eventos não aparecem no DebugView
1. Verifique se habilitou o debug mode (adb/Xcode)
2. Aguarde 1-2 minutos (há delay)
3. Verifique se o app é o correto no Firebase Console

### Crashes não aparecem
1. O crash é enviado na **próxima abertura** do app
2. Rode em **release mode** (`flutter run --release`)
3. Aguarde ~5 minutos após reabrir o app

### Stack traces não legíveis
1. Verifique se o plugin Crashlytics está configurado
2. Para builds obfuscados, faça upload dos símbolos

---

## 📚 Referências

- [Firebase Analytics para Flutter](https://firebase.google.com/docs/analytics/get-started?platform=flutter)
- [Firebase Crashlytics para Flutter](https://firebase.google.com/docs/crashlytics/get-started?platform=flutter)
- [DebugView do Analytics](https://support.google.com/analytics/answer/7201382)
