#!/bin/bash

# Script para compilar regras modulares do Firestore em um único arquivo
# Uso: ./build-rules.sh

echo "🔨 Compilando regras do Firestore..."

OUTPUT_FILE="firestore.rules"
RULES_DIR="rules"

# Criar início do arquivo
cat > "$OUTPUT_FILE" << 'EOF'
/// 🧩 Firestore Security Rules - Arquitetura Modular
/// 
/// ⚠️ ARQUIVO GERADO AUTOMATICAMENTE
/// NÃO EDITE DIRETAMENTE - Edite os arquivos em /rules/ e execute ./build-rules.sh
/// 
/// Estrutura:
/// - rules/helpers.rules        → Funções auxiliares reutilizáveis
/// - rules/users.rules          → Coleção Users/{userId}
/// - rules/app_config.rules     → Coleção AppInfo/{configName}
/// - rules/notifications.rules  → Subcoleção Users/{userId}/Notifications/{notificationId}
/// - rules/device_tokens.rules  → Coleção DeviceTokens/{tokenId}
/// - rules/device_blacklist.rules → Coleção BlacklistDevices/{deviceIdHash}
/// - rules/reviews.rules        → Coleção Reviews/{reviewId}
/// - rules/events.rules         → Coleção events/{eventId}
/// - rules/applications.rules   → Coleção EventApplications/{applicationId} [CORRIGIDO: permite leitura de aprovados]
/// - rules/event_chats.rules    → Coleção EventChats/{eventId} + subcoleções
/// - rules/connections.rules    → Coleção Connections/{userId}/Conversations/{withUserId}
/// - rules/messages.rules       → Coleção Messages/{userId}/{partnerId}/{messageId}
/// - rules/ranking.rules        → Coleções userRanking/{userId} e locationRanking/{placeId}
/// - rules/reports.rules        → Coleção reports/{reportId}

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

EOF

# Adicionar conteúdo de cada arquivo de regras
echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🔧 Funções Auxiliares" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/helpers.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 👤 Usuários" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/users.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // ⚙️ Configurações da Aplicação" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/app_config.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🔔 Notificações" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/notifications.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🔑 Tokens FCM" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/device_tokens.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🚫 Dispositivos Bloqueados" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/device_blacklist.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // ⭐ Reviews/Avaliações" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/reviews.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🎉 Eventos" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/events.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🎴 Previews de Eventos" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/events_card_preview.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🗺️ Eventos no Mapa" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/events_map.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🎫 Aplicações para Eventos" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/applications.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 💬 Chats de Eventos" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/event_chats.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 💬 Connections (Conversas 1-1)" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/connections.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 💬 Messages (Mensagens 1-1)" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/messages.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 👁️ Visitas ao Perfil" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/profile_visits.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🏆 Rankings" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/ranking.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🚩 Reports/Denúncias" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/reports.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🎭 Verificações Didit" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/didit.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // �️ Feed de Fotos (EventPhotos)" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/event_photos.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 🚫 Bloqueio de Usuários" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/blocked_users.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 📰 Feed de Atividades" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/activity_feed.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 📰 Feeds (Fanout)" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/feeds.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 💳 Status de Assinatura" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/subscription_status.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "    // ======================================" >> "$OUTPUT_FILE"
echo "    // 📬 Push Receipts (Idempotência)" >> "$OUTPUT_FILE"
echo "    // ======================================" >> "$OUTPUT_FILE"
cat "$RULES_DIR/push_receipts.rules" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Fechar o arquivo
cat >> "$OUTPUT_FILE" << 'EOF'
    // ======================================
    // 🚫 Bloquear outras coleções
    // ======================================
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
EOF

echo "✅ Regras compiladas com sucesso em $OUTPUT_FILE"
echo "📦 Execute: firebase deploy --only firestore:rules"
