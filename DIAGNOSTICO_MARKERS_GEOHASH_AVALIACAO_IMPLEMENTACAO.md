# Avaliação da Implementação — Questionário de Diagnóstico (Markers por Geohash)

> **Data:** 3 de fevereiro de 2026

## A) Contexto do problema (pra não caçar fantasma)

- Quando começou? **Indefinido nesta análise** (não há release/migração registrada aqui).
- Acontece em todas as contas ou só algumas? **Indefinido**.
- Acontece em Android e iOS ou só em um? **Indefinido**.
- O problema é “0 eventos encontrados” ou “eventos encontrados mas markers=0”? **Logs recentes indicam “0 eventos encontrados”.**
- Pelo log: quase sempre é “0 eventos encontrados” + às vezes “stale not applied”. **Compatível com o cenário atual.**

## B) Verificação rápida: existe evento no Firestore que deveria aparecer?

- Existe 1 `eventId` que deveria aparecer? **Não informado.**
- Valores/tipos esperados no doc:
  - `geohash`: **string**
  - `latitude` / `longitude`: **double**
  - `status`: **string** (esperado: `active`)
  - `isActive`: **bool** (esperado: `true` quando `status` ausente)
  - `isCanceled`: **bool** (esperado: `false`)
- Evento dentro da tela? **Indefinido.**
- `lat/lng` dentro do range do bounds do log? **Indefinido.**

## C) Diagnóstico do “geohash range” (a parte que mais quebra)

- Implementação usada: **`geohash_helper.dart` no client** (precisão varia por zoom).
- Geohash gerado no client ou backend: **client (Flutter)**.
- Comparação `storedGeohash` vs `computedGeohash`: **não executado aqui**.
- Prefixos no log: **cells prec=4** (ex.: `e0cz`, `dbfp`, `6xfp`).
- Evento real na região começa com prefixo de cell do log? **Indefinido.**

## D) Query no Firestore está “sem where” ou tem where escondido?

- Implementação atual:
  - **Firestore:** `orderBy geohash`, `startAt/endAt`, `limit` **sem `where`**.
  - **Client filters:** `isCanceled=false` e **`status=active` OR `isActive=true`**.
- Filtros **estão no client** (pós-filtro), não no Firestore.
- Desligar `clientFilters`: **não testado aqui**.
- Query mínima (sem filtros) no Firestore: **está ativa na implementação**.

## E) Índices, regras e permissão

- Regras bloqueando leitura? **Sem evidência direta** nos logs analisados.
- `PERMISSION_DENIED` observado? **Não observado** nos trechos disponíveis.
- Índice pendente em `events`? **Indefinido**.
- Multi-where / OR real no Firestore? **Não** (o OR é apenas client-side).
- Índice composto exigido? **Não aplicável** no formato atual.

## F) Bounds/Zoom: o mapa está pedindo uma área absurda?

- Caso `boundsKey=-90...90` e `zoom=3.0`: **possível** em zoom baixo.
- Zoom mínimo permitido pra carregar eventos: **não existe “guard” de bloqueio** (apenas `largeViewport=true`).
- Sampling pode buscar muitas cells: **sim**, especialmente em zoom baixo.
- Mesmo assim, se existissem eventos ativos no mundo, **deveria retornar algo**.

## G) Stale / concorrência (quando tem evento mas não aplica)

- Logs de “eventos encontrados” mas `markers=0`: **não confirmados aqui**.
- `Network fetch STALE - cached but NOT applied`: **aparece em cenários de corrida**.
- `activeChanged=true` pode vir de:
  - mudança do usuário,
  - `setExpandedBoundsKey`,
  - prefetch/coverage recalculando.
- Debounce atual no `cameraIdle`: **600ms**.
- Cancelamento real de query: **não** (usa seq e descarta stale).

## H) Do dado até o marker (pipeline de render)

- Pipeline existe e usa `ClusterService` + `applyMarkers`.
- Possíveis filtros de marker que zeram:
  - evento sem lat/lng válido,
  - evento expirado ou inválido para render,
  - categoria/condição de UI específica.
- Sem evidência de falha nessa etapa nos logs recentes (o zero vem do fetch).

---

# Checklist de resposta (preenchido com a análise atual)

- Existe 1 `eventId` que deveria aparecer? **Não informado.**
- Campos do evento (`geohash / lat / lng / status / isActive / isCanceled`): **não informado**.
- `storedGeohash` começa com `computedGeohash`? **Não verificado**.
- Filtros `status/isActive/isCanceled`: **aplicados no client**.
- Você já viu “X eventos encontrados” e `markers=0`? **Não confirmado**.

---

## Observação importante do log atual (compatível com a implementação)

A query está com:
- `where: (none)`
- `orderBy geohash`

Se mesmo assim `returned=0` em cells do mundo inteiro (zoom baixo), as causas mais prováveis são:

1) **Coleção `events` vazia** no projeto/ambiente que o app está apontando (staging vs prod)
2) **Campo `geohash` ausente / nome diferente / tipo errado** nos docs
3) **Regras bloqueando leitura** e o erro está sendo suprimido em algum catch (menos provável)

---

## Observação adicional (conflito `status` x `isActive`)

A implementação atual considera:
- Se `status` **existe e é não vazio**, **ele tem precedência** e precisa ser `active`.
- Se `status` **não existe ou é vazio**, exige `isActive == true`.

Se os documentos estiverem com `status="inactive"` e `isActive=false`, **eles serão corretamente excluídos**. Se eles deveriam aparecer, os dados precisam refletir `status=active` (ou `isActive=true` quando `status` não estiver presente).

---

# Diagnóstico 2.0 — Por que markers por geohash não aparecem

## 1) Prova de existência do dado (sem isso, tudo vira achismo)

### 1.1 EventId recém-criado

- Você consegue me passar um `eventId` que você acabou de criar (agora) e que deveria aparecer no mapa?

### 1.2 Campos do documento (log/print)

Cole no log/print os campos desse doc:

- `geohash` (valor + tipo)
- `latitude` / `longitude` (valor + tipo)
- `status` (valor + tipo)
- `isActive` (valor + tipo)
- `isCanceled` (valor + tipo)
- `createdAt` (se existir)

✅ **Objetivo:** confirmar que existe pelo menos 1 evento “válido” para a query trazer.

## 2) Prova de ambiente certo (quando “busca o mundo inteiro e não vem nada”)

Seu log mostra query no mundo inteiro (bounds -90..90) e retorna 0. Isso é muito suspeito.

### 2.1 Log no startup (no app)

Logue estes 3 itens no startup:

- `Firebase.app().options.projectId`
- `Firebase.app().options.apiKey` (pode truncar)
- `Firebase.app().options.storageBucket`

### 2.2 Pergunta direta

Esse `projectId` é o mesmo que você está olhando no console onde “tem eventos”?

✅ **Conclusão rápida:**

- Se o `projectId` não bater: você está lendo staging/dev vazio.
- Se bater: segue pro passo 3.

## 3) Prova de permissão (sem erro explícito dá pra estar “engolindo” exceptions)

Você só pode afirmar que não há `PERMISSION_DENIED` se o erro for logado.

### 3.1 Log explícito no `try/catch` da query

Exemplo sugerido:

```dart
try {
  final snap = await query.get();
  debugPrint('✅ [events] fetched=${snap.docs.length}');
} on FirebaseException catch (e) {
  debugPrint('❌ [events] FirebaseException code=${e.code} msg=${e.message}');
  rethrow;
} catch (e, st) {
  debugPrint('❌ [events] unknown error=$e\n$st');
  rethrow;
}
```

✅ **Conclusão:**

- Se aparecer `permission-denied`: é regra.
- Se não: segue.