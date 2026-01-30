# Diagnóstico Final — Simplified Notifications

## Respostas

**Você já salva fromUserName e fromUserPhotoUrl no doc da notificação hoje?**
(x) sim (para Nome) / (x) não (para Foto)
*Detalhe: O código salva `n_sender_fullname`, mas explicitamente salva `n_sender_photo_link: ''` (string vazia) para forçar o uso do `StableAvatar`/`UserStore`.*

**No card, você realmente precisa de “dados frescos” do usuário, ou só em casos raros?**
(x) sempre fresco
*O código tem um comentário explícito: "⚠️ ARQUITETURA: senderName/senderPhotoUrl da notificação são APENAS fallback. Para usuários reais, SEMPRE usar UserStore/StableAvatar". Isso privilegia consistência em todo o app sobre performance de leitura.*

**Quantos tipos existem no whereIn?**
(x) até 10
*O maior grupo é o filtro de "Activities" com 8 tipos (`activity_created`, `join_request`, `approved`, `rejected`, `new_participant`, `heating_up`, `expiring_soon`, `canceled`).*

**Você agrupa notificações repetidas? (ex: “Fulano e +12 curtiram…”)**
(x) não
*Cada documento do Firestore vira um item na lista. Não há lógica de agregação no client.*
