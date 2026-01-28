# Correção Robusta de Navegação e Consumo de Pendências

## Problema
Simplesmente enfileirar (`queueEvent`) e navegar (`go`) não garante que o evento será consumido pelo mapa, especialmente se:
1.  A aba do mapa não for reconstruída (devido ao `AutomaticKeepAliveClientMixin`), o que impede a chamada do `initState` e, consequentemente, do `registerMapServices`.
2.  O `registerMapServices` for chamado *antes* da navegação ser concluída e *antes* do evento ser enfileirado (race condition).
3.  O handler se desregistrar indevidamente (corrigido anteriormente).

## Solução Implementada

1.  **MapNavigationService**:
    *   Adicionado getter `hasPendingNavigation` para verificação externa.
    *   Criado método `tryConsumePending()`:
        *   Verifica passivamente se há Handler + Pendência.
        *   Se houver, executa imediatamente e limpa a pendência.
        *   Evita efeitos colaterais (não força setar pendência, apenas consome se existir).
    *   Atualizado `queueEvent` para tentar um consumo agendado (500ms) se já houver handler, cobrindo o caso da aba já estar montada.

2.  **AppNotifications**:
    *   Implementado mecanismo de **Polling (Retry)** após a navegação.
    *   Executa um loop de 8 tentativas (total ~2s) chamando `MapNavigationService.instance.tryConsumePending()`.
    *   Isso garante que, assim que o mapa estiver disponível (seja por reconstrução ou porque já estava lá), o evento será disparado.

## Fluxo Resultante
1.  Clique na Notificação -> `AppNotifications`.
2.  Queue Event -> `MapNavigationService`.
3.  Navigate -> `GoRouter`.
4.  **Polling Loop (Background)**:
    *   Tenta consumir... falha (mapa ainda carregando?)
    *   Tenta consumir... falha
    *   Mapa fica pronto -> Handler registrado.
    *   Tenta consumir... **SUCESSO!**
    *   Loop interrompido.

Isso elimina a dependência de ciclos de vida de widget perfeitos e torna a navegação resiliente a atrasos de UI.
