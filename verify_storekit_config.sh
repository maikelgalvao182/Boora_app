#!/bin/bash

# Script para verificar configuração do StoreKit e RevenueCat
# Execute: bash verify_storekit_config.sh

echo "🔍 Verificando configuração StoreKit e RevenueCat..."
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Verificar se Configuration.storekit existe
echo "1️⃣  Verificando arquivo Configuration.storekit..."
if [ -f "ios/Configuration.storekit" ]; then
    echo -e "${GREEN}✅ Arquivo encontrado: ios/Configuration.storekit${NC}"
    
    # Extrair Product IDs do arquivo
    echo ""
    echo "📦 Product IDs encontrados no StoreKit:"
    grep -o '"productID":"[^"]*"' ios/Configuration.storekit | cut -d'"' -f4 | while read -r product; do
        echo "   - $product"
    done
else
    echo -e "${RED}❌ Arquivo NÃO encontrado: ios/Configuration.storekit${NC}"
    echo "   Execute: flutter pub get (o arquivo foi criado recentemente)"
    exit 1
fi

echo ""
echo "---"
echo ""

# 2. Verificar Bundle ID
echo "2️⃣  Verificando Bundle ID no Info.plist..."
BUNDLE_ID=$(grep -A 1 "CFBundleIdentifier" ios/Runner/Info.plist | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
echo -e "${GREEN}Bundle ID: $BUNDLE_ID${NC}"

echo ""
echo "---"
echo ""

# 3. Instruções para verificar no Xcode
echo "3️⃣  PRÓXIMOS PASSOS - Execute no Xcode:"
echo ""
echo -e "${YELLOW}📱 No Xcode (já deve estar aberto):${NC}"
echo ""
echo "   A. Verificar se Configuration.storekit está no projeto:"
echo "      - Navegador de arquivos (esquerda) → procure 'Configuration.storekit'"
echo "      - Se NÃO aparecer: arraste ios/Configuration.storekit para dentro do Xcode"
echo ""
echo "   B. CONFIGURAR O SCHEME (PASSO CRÍTICO!):"
echo "      1. Product → Scheme → Edit Scheme... (ou ⌘+Shift+,)"
echo "      2. Selecione: Run → Options"
echo "      3. StoreKit Configuration: selecione 'Configuration.storekit'"
echo "      4. Clique 'Close' para salvar"
echo ""
echo "   C. REBUILD COMPLETO:"
echo "      - Pare o app"
echo "      - Execute: flutter clean && cd ios && pod install && cd .. && flutter run"
echo ""
echo "---"
echo ""

# 4. Checklist final
echo "4️⃣  CHECKLIST - Verifique no RevenueCat Dashboard:"
echo ""
echo "   🌐 Acesse: https://app.revenuecat.com"
echo ""
echo "   ✅ Products configurados:"
echo "      - semanal_01"
echo "      - mensal_02"
echo "      - anual_03"
echo ""
echo "   ✅ Offering 'Assinaturas':"
echo "      - Existe e está marcada como 'Current'"
echo "      - Contém os 3 produtos acima"
echo ""
echo "   ✅ Bundle ID no RevenueCat:"
echo "      - Deve ser: $BUNDLE_ID"
echo ""
echo "---"
echo ""
echo -e "${GREEN}✅ Verificação concluída!${NC}"
echo ""
echo "📖 Guia completo: STOREKIT_CONFIGURATION_GUIDE.md"
