# 🐛 RELATÓRIO DE DEBUG - NOTIFICAÇÕES PUSH NÃO RECEBIDAS

## 📊 Status do Teste

✅ **Backend**: FCM enviou as notificações com sucesso  
✅ **Tokens**: Ambos os tokens são válidos e ativos  
❌ **Cliente**: Notificações não chegaram nos dispositivos  

### Resposta do FCM
```json
{
  "success": true,
  "summary": {
    "totalTokens": 2,
    "successCount": 2,
    "failureCount": 0
  },
  "results": [
    {
      "index": 1,
      "success": true,
      "messageId": "projects/partiu-479902/messages/1765725663569377"
    },
    {
      "index": 2,
      "success": true,
      "messageId": "projects/partiu-479902/messages/1765725663568676"
    }
  ]
}
```

**Conclusão**: O Firebase Cloud Messaging **aceitou e processou** as notificações. O problema está no **lado do cliente** (app Flutter).

---

## 🔍 PROBLEMAS IDENTIFICADOS

### ❌ PROBLEMA 1: PushNotificationManager NÃO inicializado

**Arquivo**: `lib/main.dart`

**Problema**: O `PushNotificationManager.initialize()` **não é chamado** no `main()`.

**Código atual**:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ❌ FALTANDO: PushNotificationManager.initialize()
  
  await Firebase.initializeApp(...);
  await GoogleMapsInitializer.initialize();
  await SessionManager.instance.initialize();
  CacheManager.instance.initialize();
  
  runApp(MyApp());
}
```

**Impacto**: 
- Handlers de notificação (foreground/background) não são configurados
- Permissões não são solicitadas
- Android channel não é criado
- App não escuta mensagens FCM

---

### ❌ PROBLEMA 2: AndroidManifest sem permissões

**Arquivo**: `android/app/src/main/AndroidManifest.xml`

**Problema**: Permissões necessárias para notificações push **não estão declaradas**.

**Faltando**:
```xml
<!-- Permissão para notificações (Android 13+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<!-- Permissão para vibração -->
<uses-permission android:name="android.permission.VIBRATE"/>

<!-- Meta-data do FCM -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="partiu_high_importance" />
```

**Impacto**:
- Android 13+ bloqueia notificações sem permissão POST_NOTIFICATIONS
- FCM não consegue criar notificações default
- Channel ID não é reconhecido

---

### ⚠️ PROBLEMA 3: handleInitialMessageAfterRunApp não chamado

**Arquivo**: `lib/main.dart`

**Problema**: Após `runApp()`, o método `handleInitialMessageAfterRunApp()` não é chamado.

**Faltando**:
```dart
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // ❌ FALTANDO
    PushNotificationManager.instance.handleInitialMessageAfterRunApp();
  }
  
  @override
  Widget build(BuildContext context) { ... }
}
```

**Impacto**:
- App não detecta se foi aberto por uma notificação
- Navegação inicial via push não funciona

---

## ✅ SOLUÇÕES

### SOLUÇÃO 1: Inicializar PushNotificationManager

**Arquivo**: `lib/main.dart`

Adicionar **ANTES do `runApp()`**:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ... Firebase, GoogleMaps, SessionManager ...
  
  // ✅ ADICIONAR AQUI
  await PushNotificationManager.instance.initialize();
  print('✅ PushNotificationManager inicializado');
  
  runApp(MyApp());
}
```

---

### SOLUÇÃO 2: Adicionar permissões no AndroidManifest

**Arquivo**: `android/app/src/main/AndroidManifest.xml`

Adicionar dentro de `<manifest>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- ✅ ADICIONAR PERMISSÕES -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    
    <application
        android:name="${applicationName}"
        ...>
        
        <!-- ✅ ADICIONAR META-DATA FCM -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="partiu_high_importance" />
        
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@mipmap/ic_launcher" />
        
        <activity android:name=".MainActivity" ...>
            ...
        </activity>
    </application>
</manifest>
```

---

### SOLUÇÃO 3: Chamar handleInitialMessageAfterRunApp

**Arquivo**: `lib/main.dart`

Modificar MyApp para StatefulWidget e adicionar no `initState`:

```dart
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // ✅ Processa mensagem inicial (app aberto via notificação)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationManager.instance.handleInitialMessageAfterRunApp();
    });
  }

  @override
  Widget build(BuildContext context) {
    // ... MaterialApp, MultiProvider, etc
  }
}
```

---

## 📋 CHECKLIST DE IMPLEMENTAÇÃO

### 1️⃣ Código (lib/main.dart)
- [ ] Importar `PushNotificationManager`
- [ ] Adicionar `await PushNotificationManager.instance.initialize();` antes do `runApp()`
- [ ] Converter `MyApp` para `StatefulWidget`
- [ ] Adicionar `handleInitialMessageAfterRunApp()` no `initState()`

### 2️⃣ Android (AndroidManifest.xml)
- [ ] Adicionar permissão `POST_NOTIFICATIONS`
- [ ] Adicionar permissão `VIBRATE`
- [ ] Adicionar meta-data `default_notification_channel_id`
- [ ] Adicionar meta-data `default_notification_icon`

### 3️⃣ iOS (Info.plist)
- [ ] Verificar se existe `UIBackgroundModes` com `remote-notification`
- [ ] Verificar se `GoogleService-Info.plist` está presente

### 4️⃣ Testes
- [ ] Rebuild completo do app
- [ ] Testar permissões (deve aparecer popup solicitando)
- [ ] Testar notificação com app em foreground
- [ ] Testar notificação com app em background
- [ ] Testar notificação com app fechado
- [ ] Testar navegação ao tocar na notificação

---

## 🧪 COMANDOS PARA TESTAR

### 1. Rebuild completo
```bash
cd /Users/maikelgalvao/partiu
flutter clean
flutter pub get
flutter run --release
```

### 2. Testar push novamente
```bash
curl "https://us-central1-partiu-479902.cloudfunctions.net/testPushWithToken?useHardcoded=true"
```

### 3. Verificar logs do app
```bash
# Android
adb logcat -s flutter

# iOS
flutter logs
```

---

## 🎯 PRÓXIMOS PASSOS

1. ✅ **Implementar SOLUÇÃO 1** (PushNotificationManager.initialize no main.dart)
2. ✅ **Implementar SOLUÇÃO 2** (Permissões no AndroidManifest.xml)
3. ✅ **Implementar SOLUÇÃO 3** (handleInitialMessageAfterRunApp)
4. 🔄 **Rebuild do app** (flutter clean + flutter run)
5. 🧪 **Testar push novamente**

---

## 📊 DIAGNÓSTICO ADICIONAL

### Verificar se FCM Token está sendo salvo

Execute no app (após implementar as correções):

```dart
// Adicionar temporariamente no main.dart após initialize()
final token = await PushNotificationManager.instance.getToken();
print('🔑 MEU TOKEN FCM: $token');
```

Compare este token com os tokens hardcoded no `testPushWithToken`:
- `fPWZo72uRUKZlq605N09RJ:APA91bG8...Fu43JWZvfs`
- `cLJhgrIscUsWqdes_VMLbH:APA91bFp...oRp_wpPv88`

Se forem **diferentes**, você está testando tokens **de outros dispositivos/instalações antigas**.

### Verificar DeviceTokens no Firestore

Acesse o Firebase Console:
```
https://console.firebase.google.com/project/partiu-479902/firestore/data/DeviceTokens
```

Procure pelos tokens hardcoded e verifique:
- `userId`: De quem são esses tokens?
- `platform`: android ou ios?
- `updatedAt`: Quando foram atualizados pela última vez?

---

## 🔍 POSSÍVEIS CAUSAS ADICIONAIS

Se após as correções ainda não funcionar:

### 1. Tokens de dispositivos diferentes
Os tokens hardcoded podem ser de dispositivos que:
- Não têm o app instalado atualmente
- Desinstalaram e reinstalaram o app (token mudou)
- Estão com app em versão antiga (sem handlers)
- Estão offline ou sem internet

**Solução**: Obter tokens **dos seus dispositivos atuais** rodando o app com as correções.

### 2. Google Play Services desatualizado (Android)
FCM requer Google Play Services atualizado.

**Solução**: Atualizar Google Play Services no dispositivo.

### 3. APNs certificate inválido (iOS)
Push em iOS requer certificado APNs válido.

**Solução**: Verificar certificado no Firebase Console → Project Settings → Cloud Messaging.

### 4. App em modo Debug vs Release
Algumas versões do Android tratam notificações diferentemente em debug mode.

**Solução**: Testar com `flutter run --release`.

---

## 📱 VERIFICAÇÃO RÁPIDA

Execute este comando no seu terminal:

```bash
# Verificar se o código do PushNotificationManager está correto
grep -n "firebaseMessagingBackgroundHandler" /Users/maikelgalvao/partiu/lib/features/notifications/services/push_notification_manager.dart
```

Deve retornar algo como:
```
16:Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
```

Se retornar vazio, o arquivo foi modificado incorretamente.

---

## ✅ RESUMO EXECUTIVO

**Problema**: Notificações FCM não chegam nos dispositivos  
**Causa Raiz**: PushNotificationManager não está sendo inicializado no app  
**Solução**: Adicionar `PushNotificationManager.instance.initialize()` no main.dart  
**Impacto**: CRÍTICO - Sistema de notificações completamente inativo  
**Prioridade**: 🔴 ALTA  

**Tempo estimado de correção**: 15 minutos  
**Requer**: Rebuild do app após modificações  

---

**Data**: 14 de dezembro de 2025  
**Projeto**: Partiu  
**FCM Project**: partiu-479902  
**Tokens testados**: 2 (ambos válidos segundo FCM)
