# Relatório de Correção: Eliminação de N+1 no Mapa

## Problema Diagnosticado
O carregamento de markers do mapa disparava chamadas para `AvatarService.getAvatarUrl` para cada evento único, gerando **N+1 Reads** na coleção `Users` (1 read extra por criador de evento visível).

## Correção Implementada (Denormalização)

### 1. Modelo de Dados (`EventModel`)
- Adicionado campo `creatorAvatarUrl` ao modelo.
- Adicionada lógica de parsing para buscar este campo do documento do evento, suportando múltiplas chaves para retrocompatibilidade e flexibilidade:
  - `organizerAvatarThumbUrl` (Recomendado)
  - `creatorPhotoUrl`
  - `authorPhotoUrl`

### 2. View Model (`MapViewModel`)
- Atualizado método `_syncEventsFromBounds` para extrair e passar o avatar URL diretamente do payload do mapa (`EventLocation` -> `EventModel`), sem fazer queries extras.

### 3. Gerador de Assets (`MapMarkerAssets`)
- Atualizado método `getAvatarPinBestEffort`:
  - **Antes:** Sempre chamava `_avatarService.getAvatarUrl(userId)`.
  - **Agora:** Primeiro verifica se `event.creatorAvatarUrl` está preenchido.
  - **Fallback:** Só chama o `AvatarService` (Firestore Lookups) se o campo estiver vazio no evento.

## Impacto
- **Zero Reads Extras** para markers em eventos novos/atualizados que possuam o campo `organizerAvatarThumbUrl` preenchido.
- Otimização imediata de performance (renderização de markers mais rápida, pois não aguarda I/O de usuários).
- Mantém compatibilidade com eventos antigos (fallback funcional).

## Próximos Passos (Backend)
Para que a otimização surta efeito total, certifique-se de que a Cloud Function de criação/edição de eventos popula o campo `organizerAvatarThumbUrl` (ou `creatorPhotoUrl`) no documento do evento.
