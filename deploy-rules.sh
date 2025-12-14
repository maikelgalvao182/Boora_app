#!/bin/bash

# 🚀 Script para editar, compilar e fazer deploy das regras do Firestore
# Uso: ./deploy-rules.sh [arquivo_opcional]

set -e

RULES_FILE="${1:-}"

echo "🔨 Firestore Rules - Deploy Pipeline"
echo "===================================="

# Se um arquivo foi especificado, abrir no editor
if [ -n "$RULES_FILE" ]; then
  if [ ! -f "rules/$RULES_FILE" ]; then
    echo "❌ Arquivo não encontrado: rules/$RULES_FILE"
    echo "📁 Arquivos disponíveis em rules/:"
    ls -1 rules/*.rules | xargs -n1 basename
    exit 1
  fi
  
  echo "📝 Abrindo rules/$RULES_FILE no editor..."
  ${EDITOR:-vim} "rules/$RULES_FILE"
fi

# Compilar regras
echo ""
echo "🔨 Compilando regras..."
./build-rules.sh

# Mostrar diff
echo ""
echo "📊 Mudanças detectadas:"
git diff firestore.rules | head -50 || echo "Nenhuma mudança"

# Confirmar deploy
echo ""
read -p "🚀 Fazer deploy para Firebase? (s/N) " -n 1 -r
echo

if [[ $REPLY =~ ^[SsYy]$ ]]; then
  echo "🚀 Fazendo deploy..."
  firebase deploy --only firestore:rules
  
  echo ""
  echo "✅ Deploy concluído com sucesso!"
  echo "📋 Console: https://console.firebase.google.com/project/partiu-479902/firestore/rules"
else
  echo "⏭️  Deploy cancelado"
  echo "💡 Para fazer deploy manualmente: firebase deploy --only firestore:rules"
fi
