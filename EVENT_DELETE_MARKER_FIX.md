# Correção de Remoção de Marker após Deleção de Evento

## Problema
Quando um evento era deletado através do `EventCard`, o marker permanecia no mapa. Isso ocorria porque o `EventCardController` tentava acessar o `MapViewModel` via singleton (`MapViewModel.instance`), que poderia ser nulo ou uma instância diferente da usada pela `GoogleMapView`.

## Solução Implementada

1.  **Injeção de Dependência no `EventCardController`**:
    *   Adicionado o parâmetro opcional `MapViewModel? mapViewModel` no construtor.
    *   Dependência armazenada internamente como `_mapViewModel`.

2.  **Atualização do `EventCardPresenter`**:
    *   Ao criar o `EventCardController` dentro de `onMarkerTap`, agora passamos explicitamente a instância `viewModel` que o presenter já possui. Isso garante que estamos manipulando o mesmo ViewModel que o Mapa está observando.

3.  **Fallback Robusto no `deleteEvent`**:
    *   O método `deleteEvent` agora tenta usar `_mapViewModel` (injetado) e faz fallback para `MapViewModel.instance` (singleton).
    *   Adicionados logs para confirmar se a remoção foi chamada.

## Arquivos Alterados
*   `lib/features/home/presentation/widgets/event_card/event_card_controller.dart`
*   `lib/features/home/presentation/widgets/map_controllers/event_card_presenter.dart`

## Resultado Esperado
Ao deletar um evento, o comando `removeEvent(eventId)` será enviado para a instância correta do `MapViewModel`, que notificará o `MapRenderController`, removendo o marker do mapa instantaneamente.
