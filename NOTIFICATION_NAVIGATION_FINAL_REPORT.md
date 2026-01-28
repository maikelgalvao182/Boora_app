# Relatório Final de Refatoração de Navegação via Notificação

Este documento sumariza a solução completa implementada para garantir que a navegação para eventos via notificação seja robusta, confiável e independente de ciclos de vida de widgets instáveis.

## 1. Problema Original
*   Notificações com payload `activityId` não navegavam se o deep link falhasse.
*   Navegar via `context.go('/home?tab=0')` não garantia que o mapa (Google Maps) fosse montado ou recriado, especialmente com `KeepAlive` ou `IndexedStack`.
*   O evento ficava "preso" na fila (`pendingEventId`) porque o mapa nunca solicitava o consumo (nunca chamava `registerMapHandler` novamente).

## 2. Solução Implementada: Arquitetura em Camadas

A solução adota o padrão "Coordinator", similar ao usado no fluxo de criação de eventos (`DiscoverTab`).

### A. Parser de Notificação (`PushNotificationManager.dart`) ✅
*   **Correção:** Adicionado fallback para `data['activityId']` na extração do ID.
*   **Resultado:** Mesmo que o deep link falhe ou venha vazio, o ID correto do evento é extraído do payload.

### B. Intenção e Coordenação (`HomeNavigationCoordinator.dart`) ✅
*   **Novo Componente:** Criado `HomeNavigationCoordinator` (Singleton).
*   **Função:** Centraliza a lógica de "Quero abrir o evento X".
*   **Fluxo:**
    1.  Define a pendência no `MapNavigationService`.
    2.  Solicita a troca de aba via `HomeTabCoordinator`.
    3.  Inicia um *polling* de segurança (curto) para garantir consumo.

### C. Controle de Abas (`HomeTabCoordinator.dart`) ✅
*   **Novo Componente:** `HomeTabCoordinator` (ChangeNotifier).
*   **Função:** Permite trocar a aba da `HomeScreen` programaticamente sem depender de rotas/URLs.
*   **Integração:** `HomeScreenRefactored` escuta este coordinator e atualiza seu `IndexedStack` instantaneamente.

### D. Consumo Ativo (`DiscoverTab.dart`) ✅
*   **Lógica:** O `DiscoverTab` (que contém o mapa) agora é "ativo".
*   **Gatilho:** Ao perceber que se tornou a aba visível (via listener do `HomeTabCoordinator`) ou ao ser montado (`initState`), ele chama:
    ```dart
    MapNavigationService.instance.tryConsumePending();
    ```
*   **Resultado:** O mapa "puxa" o evento para si assim que está pronto.

### E. Serviço de Navegação (`MapNavigationService.dart`) ✅
*   **Melhoria:** Implementado `tryConsumePending()`.
*   **Lógica:** Se (Handler existe) E (Evento Pendente existe) -> Executa imediatamente.
*   **Fila Inteligente:** O método `queueEvent` agora tenta agendar um consumo imediato (500ms) se já houver um handler registrado (cobrindo o caso de abas em memória).

## 3. Fluxo Final de Execução

1.  **Clique na Notificação**
2.  `PushNotificationManager` extrai `activityId`.
3.  `AppNotifications` limpa modais (`popUntil root`) e chama `HomeNavigationCoordinator`.
4.  `HomeNavigationCoordinator` enfileira evento e pede troca de aba.
5.  `HomeScreenRefactored` troca para Tab 0 (Mapa).
6.  `DiscoverTab` acorda, vê que é a aba ativa e chama `tryConsumePending()`.
7.  `MapNavigationService` executa a animação de câmera e abre o card do evento.

## Conclusão
O sistema agora é resiliente a:
*   Falta de Deep Links.
*   Mapas que não recriam (`KeepAlive`).
*   Mapas que demoram a carregar.
*   Navegação concorrente.
