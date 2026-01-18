# 🚀 AppsFlyer SDK - Configuração e Uso

## 📦 Instalação Completa

### ✅ Dependências Adicionadas

**pubspec.yaml:**
```yaml
appsflyer_sdk: ^6.14.4
```

**android/app/build.gradle.kts:**
```kotlin
implementation("com.appsflyer:af-android-sdk:6.14.2")
```

**android/build.gradle.kts:**
```kotlin
repositories {
    google()
    mavenCentral() // ✅ Já configurado
}
```

---

## 🔧 Configuração Inicial

### 1. Obter Credenciais do AppsFlyer

Acesse o [Dashboard do AppsFlyer](https://hq1.appsflyer.com/) e obtenha:

- **Dev Key**: Chave de desenvolvedor (comum para iOS e Android)
- **Apple ID**: ID do app na App Store (apenas iOS) - formato: `id123456789`

### 2. Configurar Android

#### **AndroidManifest.xml** (`android/app/src/main/AndroidManifest.xml`)

Adicione as permissões necessárias:

```xml
<manifest>
    <!-- Permissões existentes -->
    
    <!-- AppsFlyer: Para rastreamento de instalações -->
    <uses-permission android:name="com.google.android.gms.permission.AD_ID"/>
    
    <application
        android:name="${applicationName}"
        android:label="partiu"
        android:icon="@mipmap/ic_launcher">
        
        <!-- Atividades existentes -->
        
        <!-- AppsFlyer: Receiver para instalações -->
        <receiver
            android:name="com.appsflyer.SingleInstallBroadcastReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="com.android.vending.INSTALL_REFERRER" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
```

### 3. Configurar iOS

#### **Info.plist** (`ios/Runner/Info.plist`)

Adicione as configurações de App Tracking Transparency:

```xml
<dict>
    <!-- Configurações existentes -->
    
    <!-- AppsFlyer: Mensagem de ATT (App Tracking Transparency) -->
    <key>NSUserTrackingUsageDescription</key>
    <string>Gostaríamos de rastrear sua atividade para melhorar sua experiência e oferecer conteúdo personalizado.</string>
    
    <!-- AppsFlyer: Esquema de URL para deep links -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLName</key>
            <string>com.maikelgalvao.partiu</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>partiu</string>
            </array>
        </dict>
    </array>
    
    <!-- AppsFlyer: Universal Links -->
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:partiu.app</string>
        <string>applinks:go.partiu.app</string>
    </array>
</dict>
```

---

## 💻 Uso no Código

### 1. Inicializar no Main

**lib/main.dart:**

```dart
import 'package:dating_app/services/appsflyer_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ... Firebase e outras inicializações
  
  // Inicializar AppsFlyer
  await AppsflyerService.instance.initialize(
    devKey: 'SUA_DEV_KEY_AQUI',          // Obter do dashboard
    appId: 'id123456789',                 // iOS App ID (Apple ID)
  );
  
  runApp(const MyApp());
}
```

### 2. Logar Eventos

```dart
import 'package:dating_app/services/appsflyer_service.dart';

// Evento de registro completo
await AppsflyerService.instance.logEvent(
  eventName: AppsflyerService.eventCompleteRegistration,
  eventValues: {
    'registration_method': 'google',
  },
);

// Evento de login
await AppsflyerService.instance.logEvent(
  eventName: AppsflyerService.eventLogin,
  eventValues: {
    'user_id': userId,
  },
);

// Evento customizado
await AppsflyerService.instance.logEvent(
  eventName: 'activity_created',
  eventValues: {
    'activity_type': 'wedding',
    'location': 'São Paulo',
  },
);
```

### 3. Definir ID do Usuário

```dart
// Após o usuário fazer login
await AppsflyerService.instance.setCustomerUserId(userId);
```

### 4. Obter AppsFlyer ID

```dart
final appsflyerId = await AppsflyerService.instance.getAppsFlyerId();
AppLogger.info('AppsFlyer ID: $appsflyerId');
```

---

## 🔗 Deep Links (Deferred Deep Links)

### O que são Deferred Deep Links?

Deferred deep links permitem que você redirecione usuários para conteúdo específico no app **após a instalação**, mesmo que o app não estivesse instalado quando o link foi clicado.

### Fluxo:

1. Usuário clica em um link de campanha (ex: `https://go.partiu.app/activity/abc123`)
2. Se o app não estiver instalado, redireciona para a loja (App Store/Play Store)
3. Após a instalação e abertura do app, o AppsFlyer detecta o link original
4. O app processa o deep link e navega para o conteúdo

### Configuração no Dashboard AppsFlyer:

1. Acesse **Configuration > OneLink**
2. Crie um OneLink template
3. Configure os parâmetros de deep link:
   - `deep_link_value`: rota/parâmetro para navegação
   - Parâmetros customizados

### Processar Deep Links no App:

Edite o método `_processDeepLink` em [appsflyer_service.dart](lib/services/appsflyer_service.dart):

```dart
void _processDeepLink(String deepLinkValue) {
  AppLogger.info('Processando deep link: $deepLinkValue');
  
  // Usar GoRouter ou navegação preferida
  final context = navigatorKey.currentContext;
  if (context == null) return;
  
  // Exemplo de rotas
  if (deepLinkValue.contains('activity/')) {
    final activityId = deepLinkValue.split('activity/').last;
    context.go('/activity/$activityId');
  } else if (deepLinkValue.contains('profile/')) {
    final userId = deepLinkValue.split('profile/').last;
    context.go('/profile/$userId');
  } else if (deepLinkValue == 'discover') {
    context.go('/discover');
  }
}
```

---

## 📊 Eventos Pré-definidos

O serviço já inclui constantes para eventos padrão do AppsFlyer:

| Constante | Valor | Uso |
|-----------|-------|-----|
| `eventCompleteRegistration` | `af_complete_registration` | Após registro completo |
| `eventLogin` | `af_login` | Login do usuário |
| `eventPurchase` | `af_purchase` | Compra realizada |
| `eventSubscribe` | `af_subscribe` | Nova assinatura |
| `eventStartTrial` | `af_start_trial` | Início de trial |
| `eventSearch` | `af_search` | Busca realizada |
| `eventShare` | `af_share` | Compartilhamento |
| `eventContentView` | `af_content_view` | Visualização de conteúdo |

---

## 🧪 Testes

### Teste de Instalação:

1. Desinstale o app
2. Acesse um link OneLink em um dispositivo
3. Instale o app pela loja
4. Abra o app e verifique os logs do AppsFlyer

### Modo Debug:

O serviço está configurado com `showDebug: true`. Verifique os logs:

**Android:**
```bash
adb logcat | grep AppsFlyer
```

**iOS:**
```bash
# No Xcode Console, filtre por "AppsFlyer"
```

### Desativar Debug em Produção:

Em [appsflyer_service.dart](lib/services/appsflyer_service.dart), altere:

```dart
final AppsFlyerOptions options = AppsFlyerOptions(
  afDevKey: devKey,
  appId: appId,
  showDebug: false, // ⚠️ Desativar em produção
  timeToWaitForATTUserAuthorization: 15,
);
```

---

## 📱 Links Úteis

- [Dashboard AppsFlyer](https://hq1.appsflyer.com/)
- [Documentação SDK Flutter](https://github.com/AppsFlyerSDK/appsflyer-flutter-plugin)
- [OneLink Guide](https://support.appsflyer.com/hc/en-us/articles/360001294118)
- [Deep Linking Guide](https://support.appsflyer.com/hc/en-us/articles/208874366-OneLink-deep-linking-guide)

---

## ✅ Checklist de Implementação

- [x] Adicionar dependência no pubspec.yaml
- [x] Adicionar SDK nativo no Android (build.gradle.kts)
- [x] Criar serviço AppsflyerService
- [ ] Obter Dev Key do dashboard
- [ ] Configurar AndroidManifest.xml
- [ ] Configurar Info.plist (iOS)
- [ ] Inicializar no main.dart
- [ ] Criar OneLink no dashboard
- [ ] Implementar processamento de deep links
- [ ] Adicionar eventos nos fluxos principais
- [ ] Testar instalação com deep link
- [ ] Desativar debug em produção

---

## 🎯 Próximos Passos

1. **Obter credenciais** do dashboard do AppsFlyer
2. **Configurar manifestos** (Android e iOS)
3. **Inicializar no main.dart** com as credenciais
4. **Criar OneLink** no dashboard para campanhas
5. **Implementar navegação** no método `_processDeepLink`
6. **Adicionar eventos** nos fluxos principais do app
7. **Testar** instalação via deep link
