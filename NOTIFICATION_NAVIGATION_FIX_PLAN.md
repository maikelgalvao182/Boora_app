# Correção de Navegação via Notificação

## Problemas Identificados

1.  **Bug A: ID de Atividade Faltando**
    *   No `PushNotificationManager`, a extração de `nRelatedId` não contemplava o campo `activityId`, que é usado no payload de criação de atividade.
    *   Havia um erro de digitação `activityrsationId`.
    *   **Correção:** Adicionado `data['activityId']` na cadeia de fallbacks e removido o typo.

2.  **Bug B: Handler se Desregistrando Prematuramente**
    *   No `MapNavigationHandler.registerMapServices`, havia uma linha suspeita: `_registered = false;` logo antes de chamar `_handleEventNavigation`.
    *   Isso não causa diretamente o problema de "não consumir", mas invalida a flag de controle interno indevidamente.
    *   **Análise mais profunda:** O usuário relatou que o log "Handler REGISTRADO" nunca aparece. Isso indica que `GoogleMapView` não está sendo reconstruído (devido ao `KeepAlive` do TabView) e, portanto, `initState` -> `registerMapServices` não é chamado novamente.
    *   Como o `MapNavigationService.queueEvent` apenas define uma variável pendente (sem notificar handlers existentes), e o `GoogleMapView` existente não "pergunta" novamente se há pendências quando o usuário retorna à aba, o evento fica preso no limbo.

## Solução para o Bug B (Próximos Passos Recomendados)

Para resolver o problema do "Keep Alive" impedindo o consumo do evento pendente, precisamos garantir que o `MapNavigationService` tente entregar o evento IMEDIATAMENTE se já houver um handler registrado, mesmo no método `queueEvent`.

Atualmente:
```dart
  void queueEvent(...) {
    _pendingEventId = eventId;
    // ... e só. Fica esperando um novo registerMapHandler
  }
```

Correção Proposta no `MapNavigationService`:
```dart
  void queueEvent(String eventId, {bool showConfetti = false}) {
    _pendingEventId = eventId;
    _pendingConfetti = showConfetti;
    
    // Tenta entregar imediatamente se o handler já estiver vivo
    // (Caso o mapa esteja apenas oculto/KeepAlive, mas funcional)
    if (_mapHandler != null) {
       debugPrint('🚀 [Service] queueEvent com Handler VIVO. Tentando entregar...');
       // ... lógica de entrega
    }
  }
```

Isso cobriria o cenário onde o tab 0 não é reconstruído (apenas focado novamente).
