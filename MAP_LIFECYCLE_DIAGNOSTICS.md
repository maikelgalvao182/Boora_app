# Diagnóstico de Ciclo de Vida do Mapa

Adicionados logs "🧨" e "🧠" críticos para validar se a tela do mapa está realmente sendo recriada ou se está em modo *KeepAlive*.

## Novos Logs Adicionados

1.  **GoogleMapView.initState**:
    *   `🧨 [GoogleMapView] initState - vou registrar services`
    *   Confirma se o widget está sendo construído do zero.

2.  **MapNavigationHandler.registerMapServices**:
    *   `🧨 [MapNavigationHandler] registerMapServices EXECUTOU`
    *   `🧠 [MapNavigationHandler] Service hash=...`
    *   Confirma se o registro no Singleton está acontecendo e se a instância do Singleton é a mesma usada pelo `AppNotifications`.

## Como Analisar

*   **Cenário A (Mapa não existe ou é recriado):**
    *   Você deve ver os logs `🧨` assim que o app abrir ou navegarmos para a aba do mapa via notificação com `refresh`.
    *   Se não aparecerem, o Flutter não está reconstruindo a Widget Tree (provavelmente devido a `KeepAlive` ou `IndexedStack`).
    *   Neste caso, a nossa implementação de `tryConsumePending()` (feita no passo anterior) é a salvação, pois ela funciona mesmo sem rebuild.

*   **Cenário B (Mapa Keep Alive):**
    *   Os logs `🧨` **NÃO** aparecerão ao navegar via notificação.
    *   Porém, o log `🧪 [MapNavigationService] tryConsumePending...` (do passo anterior) DEVE aparecer e ter sucesso.

Com esses logs, saberemos exatamente o que está acontecendo "por baixo do capô".
