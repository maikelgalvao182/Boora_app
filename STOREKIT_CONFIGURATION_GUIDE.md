# Guia: Configuração StoreKit para Desenvolvimento iOS

## ⚠️ Problema Identificado

```
CONFIGURATION_ERROR: None of the products registered in the RevenueCat dashboard 
could be fetched from App Store Connect (or the StoreKit Configuration file if one is being used)
```

## ✅ Solução: Configurar StoreKit no Xcode

O arquivo `Configuration.storekit` já foi criado com seus produtos, mas o **Xcode precisa ser configurado** para usá-lo.

---

## 📋 Passo a Passo (SIGA EXATAMENTE)

### ✅ Passo 1: Verificar se o arquivo existe no Xcode

O Xcode já deve estar aberto. Se não estiver:
```bash
open ios/Runner.xcworkspace
```

**No navegador de arquivos do Xcode (lado esquerdo):**
1. Procure pelo arquivo `Configuration.storekit` na pasta `ios/`
2. Se **NÃO APARECER**, você precisa adicioná-lo ao projeto:
   - Arraste o arquivo `ios/Configuration.storekit` para dentro do Xcode
   - Na janela que abrir, marque: ✅ "Copy items if needed"
   - Target: ✅ Runner
   - Clique "Finish"

---

### ✅ Passo 2: CONFIGURAR O SCHEME (PASSO CRÍTICO!)

Este é o passo que está faltando! Sem isso, o iOS não usará o StoreKit Configuration.

1. **Abrir o Scheme Editor:**
   - No Xcode, vá em: `Product` → `Scheme` → `Edit Scheme...`
   - **OU** pressione: `⌘` + `Shift` + `,` (vírgula)

2. **Configurar StoreKit:**
   - No painel esquerdo, selecione: **"Run"** (deve estar selecionado por padrão)
   - Clique na aba: **"Options"** (no topo)
   - Role até encontrar a seção: **"StoreKit Configuration"**
   - No dropdown, selecione: **"Configuration.storekit"**
   
   ```
   ┌─────────────────────────────────────────┐
   │ Run ▼                                   │
   │ ├─ Info                                │
   │ ├─ Arguments                           │
   │ ├─ Options ◄── CLIQUE AQUI            │
   │ └─ Diagnostics                         │
   │                                         │
   │ StoreKit Configuration:                 │
   │ [Configuration.storekit ▼] ◄── SELECIONE│
   └─────────────────────────────────────────┘
   ```

3. **Salvar:**
   - Clique em "Close" para fechar o Scheme Editor
   - As configurações são salvas automaticamente

---

### ✅ Passo 3: Verificar Product IDs

**CRÍTICO:** Os Product IDs no StoreKit Configuration **devem ser EXATAMENTE iguais** aos configurados no RevenueCat Dashboard.

**Seus produtos atuais no StoreKit:**
- `semanal_01` (weekly - R$ 3.99)
- `mensal_02` (monthly - R$ 9.99)
- `anual_03` (annual - R$ 79.99)

**Verifique no RevenueCat Dashboard:**
1. Acesse: https://app.revenuecat.com
2. Vá em: **Products**
3. Confirme que os Product IDs são EXATAMENTE:
   - ✅ `semanal_01`
   - ✅ `mensal_02`
   - ✅ `anual_03`

**Se forem diferentes no RevenueCat, você tem 2 opções:**
- **Opção A:** Atualizar o StoreKit para usar os IDs do RevenueCat
- **Opção B:** Atualizar os IDs no RevenueCat para corresponder ao StoreKit

---

### ✅ Passo 4: Verificar Offering no RevenueCat

1. No RevenueCat Dashboard, vá em: **Offerings**
2. Verifique se existe uma offering chamada **"Assinaturas"**
3. Confirme que os 3 produtos estão adicionados a essa offering
4. Marque essa offering como **"Current"** (offering padrão)

---

### ✅ Passo 5: Rebuild Completo

Após configurar o Scheme, você DEVE fazer rebuild completo:

```bash
# Pare o app no simulador/device

# Limpe tudo
flutter clean
cd ios
rm -rf Pods
rm Podfile.lock
pod deintegrate
pod install
cd ..

# Rebuild
flutter pub get
flutter run
```

---

## 🔍 Verificação Final

Após o rebuild, os logs devem mostrar:

```
✅ Usando current offering com 3 packages
   📦 weekly | Type: weekly | Product: semanal_01
   📦 monthly | Type: monthly | Product: mensal_02
   📦 annual | Type: annual | Product: anual_03
```

---

## ❌ Troubleshooting

### "Configuration.storekit não aparece no dropdown"

**Causa:** O arquivo não foi adicionado ao target Runner no Xcode

**Solução:**
1. Selecione `Configuration.storekit` no navegador do Xcode
2. No painel direito (File Inspector), verifique:
   - ✅ Target Membership: Runner deve estar marcado
3. Se não estiver marcado, marque a caixa "Runner"

### "Produtos ainda não aparecem após configurar"

**Causa:** Scheme não foi salvo ou app não foi reconstruído

**Solução:**
1. Feche COMPLETAMENTE o Xcode (`⌘` + `Q`)
2. Reabra: `open ios/Runner.xcworkspace`
3. Verifique o Scheme novamente
4. Faça rebuild completo (Passo 5)

### "Invalid Product IDs"

**Causa:** Mismatch entre StoreKit e RevenueCat

**Solução:**
1. Abra `ios/Configuration.storekit` no Xcode
2. Verifique os `productID` de cada subscription
3. Compare com os IDs no RevenueCat Dashboard
4. Devem ser EXATAMENTE iguais (case-sensitive)

---

## 📱 Testando no Device Físico (Alternativa)

Se o StoreKit Configuration não funcionar, teste em um device físico:

1. **Crie uma Sandbox Tester Account:**
   - App Store Connect → Users and Access → Sandbox Testers
   - Crie um novo tester com email válido

2. **Configure o Device:**
   - Settings → App Store → Sandbox Account
   - Login com o Sandbox Tester criado

3. **Faça build no device:**
   ```bash
   flutter run --release
   ```

4. Os produtos virão diretamente do App Store Connect

---

### Passo 4: Verificar Product IDs

Você precisa garantir que os Product IDs estão consistentes em 3 lugares:

1. **RevenueCat Dashboard** → Products
2. **App Store Connect** → In-App Purchases
3. **StoreKit Configuration File**

#### Exemplo de Product IDs Comuns:
```
com.seuapp.mensal
com.seuapp.anual
```

### Passo 5: Rebuild do App

```bash
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter run
```

## Verificação Rápida

Após configurar, os logs devem mostrar:

```
✅ Usando current offering com 2 packages
   📦 monthly | Type: monthly | Product: com.seuapp.mensal
   📦 annual | Type: annual | Product: com.seuapp.anual
```

## Alternativa para Testes Rápidos (Modo Sandbox)

Se você tem os produtos já configurados no App Store Connect, pode testar em:

1. **Device físico** com conta de teste (Sandbox Tester)
2. **TestFlight** build

## Links Úteis

- 🔗 [RevenueCat - Why are offerings empty?](https://rev.cat/why-are-offerings-empty)
- 🔗 [Apple - Testing In-App Purchases](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases_in_xcode)
- 🔗 [RevenueCat - StoreKit Configuration](https://www.revenuecat.com/docs/test-and-launch/sandbox/ios-subscription-testing)

## Troubleshooting

### "Products not found" mesmo com StoreKit configurado

- Verifique se o Product ID está exatamente igual em todos os lugares (case-sensitive)
- Limpe build: `flutter clean && cd ios && pod deintegrate && pod install`
- Reinicie Xcode completamente

### "Invalid Product ID"

- O formato geralmente é: `com.seudominio.produto`
- Não use espaços ou caracteres especiais
- Use apenas letras minúsculas, números e pontos

### Para Produção

O StoreKit Configuration File é apenas para **desenvolvimento**. 

Em produção (TestFlight/App Store), o iOS busca automaticamente do App Store Connect.
