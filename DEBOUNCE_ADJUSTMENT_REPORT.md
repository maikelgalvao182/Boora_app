# Relatório de Ajuste: Aumento do Debounce de Mapa

## Problema
O debounce de **200ms** era demasiado agressivo para o serviço de mapas. Ao realizar pequenos ajustes de câmera (ex: usuário tentando centralizar uma rua ou fazer zoom-pinch), o app disparava múltiplas queries desnecessárias, pois 200ms é menor que o tempo de hesitação médio do usuário.

## Ajustes Realizados

Foi aumentado o debounce e limiares em pontos estratégicos para garantir que queries só ocorram quando o usuário realmente terminou de interagir com o mapa.

### 1. `MapDiscoveryService.dart` (Query Service)
- **Alteração:** `debounceTime` aumentado de **200ms** para **600ms**.
- **Impacto:** O serviço agora espera mais de meio segundo de inatividade antes de efetivamente bater no Firestore. Isso cancela a maioria das queries intermediárias de um pan/zoom longo.

### 2. `GoogleMapView.dart` (UI Controller)
- **Alteração:** `_cameraIdleDebounceDuration` aumentado de **200ms** para **600ms**.
- **Impacto:** Garante sincronia com o Service e evita processamento lógico de UI (como cálculos de bounds) antes da hora.

### 3. `MapRenderController.dart` (Cluster Renderer)
- **Alteração:** `_renderDebounceDuration` aumentado de **80ms** para **150ms**.
- **Impacto:** Como o rebuild visual dos clusters e bitmaps é pesado (CPU), dar uma folga maior evita travamentos (jank) enquanto novas queries estão sendo preparadas.

## Recomendações Adicionais
O `MapBoundsController` já possui lógica de "Contenção de Bounds" (`isBoundsContained`). Com o aumento do debounce, essa lógica torna-se ainda mais eficiente, pois o "novo bounds" a ser testado será o final de uma interação, e não um passo intermediário.
