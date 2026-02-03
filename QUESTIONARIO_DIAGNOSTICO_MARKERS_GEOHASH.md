# Questionário de Diagnóstico — Markers por Geohash não carregam na UI

> **Data:** 3 de fevereiro de 2026

## A) Contexto do problema (pra não caçar fantasma)

1. Quando começou? (após qual release / migração / mudança em schema?)
2. Acontece em todas as contas ou só algumas (ex: VIP vs free / cidades específicas)?
3. Acontece em Android e iOS ou só em um?
4. O problema é “0 eventos encontrados” ou “eventos encontrados mas markers=0”?
5. Pelo seu log: quase sempre é “0 eventos encontrados” + às vezes “stale not applied”. Confirma?

## B) Verificação rápida: existe evento no Firestore que deveria aparecer?

6. Você consegue apontar 1 `eventId` que deveria aparecer na área testada?
7. No documento desse evento, quais são os valores e tipos (print do console serve):
   - `geohash` (string?)
   - `latitude` / `longitude` (double?)
   - `status` (string? quais valores possíveis?)
   - `isActive` (bool?)
   - `isCanceled` (bool? ou pode ser null/ausente?)
8. Esse evento está dentro da tela mesmo?
9. `lat`/`lng` do evento estão dentro do range do bounds que aparece no log?

## C) Diagnóstico do “geohash range” (a parte que mais quebra)

10. O seu geohash é gerado por qual lib/implementação? (ex: dart_geohash, geohash, custom)
11. O geohash do documento foi gerado:
    - no client (Flutter) ou no backend (Cloud Functions/Nest)?
12. Você consegue rodar (no client) um log comparando:
    - `storedGeohash` (do doc)
    - `computedGeohash = encode(lat, lng, precision: 6)`
    E responder: o stored começa com o computed (prefix match)?
13. No seu log aparecem cells tipo `e0cz`, `dbfp`, `6xfp` (prec=4).
14. Um evento real na região tem geohash começando com algum desses prefixos? Ex: `6xfp....` (sim/não)
15. Se a resposta for “não”, o problema é geohash errado/incompatível ou lat/lng errados.

## D) A query no Firestore está realmente “sem where” ou tem where escondido?

16. No log aparece:
    - `where: (none)`
    - `clientFilters: isCanceled=false, status=active OR isActive=true`

17. Esses filtros são:
    - (a) aplicados no Firestore (where)
    - ou (b) aplicados só no client (pós-filtro)?
18. Se você desligar temporariamente os clientFilters (só pra teste), aparece algum evento? (Sim/Não)
19. Você já testou uma query mínima no Firestore:
    - apenas `orderBy geohash + startAt/endAt cell + limit`
    - e viu se retorna qualquer doc?

## E) Índices, regras e permissão

20. As regras do Firestore podem estar bloqueando leitura de `events`?
21. Você vê `PERMISSION_DENIED` em algum momento? (mesmo que raro)
22. No console do Firebase, em “Indexes”, existe algum índice pendente/criando relacionado a `events`?
23. Você usa multi-where / OR query em algum ponto real? (ex: `status==active` OR `isActive==true`)
24. Se sim: você criou o índice composto que o Firestore exige?
25. No seu log aparece `status=active OR isActive=true` — se isso estiver indo pro Firestore, pode exigir index e falhar (mas normalmente logaria erro).

## F) Bounds/Zoom: o mapa está pedindo uma área absurda?

26. Você viu esse caso: `boundsKey=-90...90` e `zoom=3.0` (planeta inteiro)
27. Qual é o zoom mínimo permitido pra carregar eventos?
28. Existe um “guard” do tipo: “se viewport muito grande, não busca/ignora”? (hoje você só marca `largeViewport=true`)
29. O sampling está pegando cells do mundo inteiro… você espera mesmo buscar assim?
30. Mesmo assim, se existissem eventos ativos no mundo, era pra retornar algo — mas isso ajuda a detectar bug de bounds.

## G) Stale / concorrência (quando tem evento mas não aplica)

31. Você já viu log: `MapDiscoveryService: X eventos encontrados` mas UI continua `markers=0`?
32. Se sim, qual log aparece logo depois?
    - `Network fetch STALE - cached but NOT applied`
33. O `activeChanged=true` acontece por:
    - (a) usuário mexendo no mapa
    - (b) `setExpandedBoundsKey` disparando sozinho
    - (c) prefetch/coverage recalculando e mudando `activeKey`
34. Você tem debounce no `cameraIdle`? Qual valor?
35. Você tem “cancelamento” real da query anterior (ex: abort token), ou só ignora pelo seq?

## H) Do dado até o marker (pipeline de render)

36. Em algum momento você tem:
    - `events > 0` e `ClusterService Fluster construído: N eventos`
37. Se sim, `applyMarkers nextCount=N` acontece?
38. O GoogleMap `markers=` bate com o que saiu do `applyMarkers`?
39. Existe algum filtro na fase de marker que pode zerar?
    - Ex: “evento sem ícone”, “evento sem lat/lng”, “evento expirado”, “categoria filtrada”, etc.

---

# Checklist de resposta (pra você preencher rápido)

Responda neste formato (pode ser curto):

- Existe 1 `eventId` que deveria aparecer? (sim/não)
- Campos desse evento: `geohash / lat / lng / status / isActive / isCanceled` (print ou valores)
- `storedGeohash` começa com `computedGeohash`? (sim/não)
- Os filtros `status/isActive/isCanceled` estão no Firestore ou no client?
- Você já viu “X eventos encontrados” e `markers=0`? (sim/não)

---

## Observação importante do seu log atual

Você está rodando query com:

- `where: (none)`
- `orderBy geohash`
- e mesmo assim `returned=0` em cells do mundo todo (até zoom 3 com bounds globais)

Isso aponta forte para um destes 3:

1. Coleção `events` vazia no projeto/ambiente que o app está apontando (staging vs prod)
2. Campo `geohash` ausente / nome diferente / tipo errado nos docs
3. Regras bloqueando leitura e você está suprimindo o erro em algum catch (menos provável, mas acontece)
