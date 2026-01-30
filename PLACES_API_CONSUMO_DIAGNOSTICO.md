# Diagnóstico de Consumo — Places API (mapa e locais)

Data: 28 de janeiro de 2026

## Evidências rápidas no código
- Location picker usa Google Places via `PlaceService` (autocomplete, detalhes, nearby e reverse geocode).
- Chamadas disparam em:
  - abertura inicial do mapa (carrega reverse geocode + nearby),
  - movimento do mapa (camera idle → reverse geocode),
  - busca manual (autocomplete) e seleção (place details).
- Fotos do Places **desativadas** (Photos API retorna vazio e UI usa placeholders locais).

---

## 📍 BLOCO 2 — Places API (mapa e locais)

**Você usa Places para:**

- [x] Buscar locais próximos
- [x] Autocomplete de endereço
- [ ] Fotos de estabelecimentos
- [x] Detalhes completos de local
- [ ] Tudo acima

**Essas chamadas acontecem:**

- [x] Toda vez que a tela abre
- [x] Toda vez que o mapa move
- [ ] Em scroll/lista
- [x] Só quando o usuário pesquisa manualmente

**Você salva os dados retornados?**

- [ ] Não, sempre consulta de novo
- [x] Cache em memória
- [ ] Cache persistente (banco/local)

**Fotos do Places:**

- [ ] Carregam sempre que aparecem
- [ ] Ficam salvas localmente
- [ ] Têm limite de chamadas
- [x] Não sei

**Um mesmo local é consultado quantas vezes por usuário?**

- [ ] 1 vez
- [x] Algumas vezes
- [ ] Muitas vezes (loop invisível)

---

## Notas objetivas
- **Autocomplete**: ocorre conforme o usuário digita na busca.
- **Place details**: ocorre quando o usuário seleciona uma sugestão.
- **Nearby + reverse geocode**: ocorre na abertura inicial e em movimentações do mapa.
- **Fotos**: atualmente desativadas para evitar custo (sem chamadas para Photos API).
