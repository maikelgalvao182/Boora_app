# Formulário de Diagnóstico — ProfileScreen (Flutter + Firestore)

## 0) Contexto rápido

**Qual banco você usa na ProfileScreen?**
- [x] Firestore
- [ ] Supabase
- [ ] REST próprio
- [ ] Outro: _______

**A ProfileScreen é:**
- [ ] do próprio usuário
- [ ] de qualquer usuário (view pública)
- [x] os dois (com UI diferente)

**A tela é montada com:**
- [ ] StreamBuilder (real time)
- [x] FutureBuilder (1x) + cache persistente
- [ ] Riverpod/Provider/Bloc com fetch manual
- [x] mistura (Future + cache + alguns streams pontuais)

**Em média, a ProfileScreen abre:**
- [ ] raramente (1-2x por sessão)
- [ ] médio (5-10x por sessão)
- [x] muito (usuários visitam vários perfis) *(estimado, não há métrica no código)*

---

## 1) Mapa da tela: quais blocos fazem fetch?

| Seção | Fonte | Tipo de chamada | Quantos docs? | Frequência |
|---|---|---|---|---|
| Avatar + nome | Users (ProfileController) + cache Hive | get + cache | 1 doc | abertura + revalidate manual |
| Galeria | Users.userGallery (URLs) + imagens (CDN/Storage via URL) | leitura de doc + download de imagens | 1 doc + N imagens | abre + navegação no slider |
| Sessões de texto (bio, info básica, interesses, idiomas) | Users (perfil estático) | get + cache | 1 doc | abertura + revalidate |
| Reviews (texto) | Reviews collection | stream query (limit 10) | 10 (UI) | abre + realtime |
| Reviews (extra, não usado na UI) | — | — | — | **removido** (stream duplicado cancelado) |
| Avatares/nome de quem fez review | ReviewModel (denormalizado) + Users (UserStore) | cache + stream por reviewer | N reviewers | sempre quando seção renderiza |
| Outros (message_button) | Users (UserStore) | stream | 1 doc | abre + realtime |
| Outros (review stats) | users_stats (fallback Users) | stream de 1 doc | 1 doc | realtime barato (sem ler N reviews) |
| Outros (followersCount) | users_status | stream | 1 doc | realtime |
| Visita de perfil | ProfileVisitsService | write | 1 doc | 1x por abertura (com cooldown) |

**✅ Pergunta-chave: tem alguma seção que você carrega “só por garantia” mesmo sem o usuário rolar até lá?**
- [ ] Sim
- [x] Não — removido stream duplicado de reviews; perfil agora é Future + cache

---

## 2) Diagnóstico de “recarregamento invisível”

**Quando você navega e volta pra ProfileScreen, ela refaz tudo?**
- [x] Só algumas seções *(mantém estado em tabs com keep-alive; em rota nova recria e refaz)*
- [ ] Sim, sempre
- [ ] Não (mantém estado/cache)

**Você tem AutomaticKeepAliveClientMixin (ou equivalente) pra segurar estado em tabs/scroll?**
- [x] Sim
- [ ] Não
- [ ] Não sei

**Seus providers/streams são autoDispose?**
- [ ] Sim
- [x] Não *(UserStore mantém listeners globais; streams do controller são manuais)*
- [ ] Não sei

**Alguma lógica roda no build() (tipo ref.watch + fetch que dispara de novo)?**
- [ ] Sim
- [x] Não
- [ ] Não sei

**Você tem múltiplos listeners para o mesmo dado (ex: userDoc observado em 2-3 lugares)?**
- [ ] Sim
- [x] Não *(perfil estático via cache + leitura única; streams só em users_status e message_button)*
- [ ] Não sei

---

## 3) Avatar + dados principais (userDoc)

**O userDoc é real time (stream) por necessidade?**
- [ ] Sim, precisa atualizar na hora (status online, etc.)
- [x] Não, pode ser eventual *(perfil estático foi migrado para Future + cache Hive)*
- [ ] Não sei

**Quais campos realmente mudam com frequência na Profile?**
- [x] foto
- [x] nome/username
- [x] bio
- [x] contadores (seguidores, reviews, etc.)
- [x] status online
- [x] outros: message_button, overallRating/totalReviews

✅ **Regra prática:** se só muda “de vez em quando”, não use stream — use cache + revalidate.

---

## 4) Galeria de imagens (photos)

**A galeria carrega:**
- [x] todas as imagens de uma vez *(slider com lista completa)*
- [ ] paginação (limit + startAfter)
- [ ] só thumbnails e abre full depois

**As URLs vêm de:**
- [x] Firestore já com URL pronta (userGallery / photoUrl)
- [ ] Storage (pega downloadURL na hora)
- [ ] CDN/proxy

**Você faz prefetch de imagens com cache?**
- [x] Sim (cached_network_image + cache manager)
- [ ] Não

**As imagens são a maior fonte de “requests” (Storage/egress), mesmo sem Firestore reads?**
- [x] Sim *(provável, pela galeria e avatars)*
- [ ] Não
- [ ] Não sei (precisa medir)

---

## 5) Reviews (texto) + “avatar de quem avaliou”

**Reviews vêm de:**
- [x] reviews collection com authorId
- [ ] subcollection users/{id}/reviews
- [ ] outra modelagem

**Para mostrar avatar/nome de quem fez review, hoje você:**
- [x] já guarda authorName e authorPhoto dentro do review (denormalizado)
- [x] usa cache em memória pra não repetir (UserStore)
- [x] busca userDoc em casos onde precisa de dados extras (nome/cidade/estado) *(potencial N+1)*
- [ ] não sei

**Quantos reviews você carrega no primeiro paint?**
- [ ] 5
- [x] 10 *(limit padrão do watchUserReviews)*
- [ ] 20+
- [ ] todos

✅ **Se marcou N+1 aqui, já achamos um corte gigante:**
- denormalizar authorName/authorAvatarThumb no review (já existe parcialmente)
- ou criar “snapshot de autor” e atualizar via Cloud Function

---

## 6) Cache atual (o que já existe)

**Hoje você tem:**
- [x] cache em memória (UserStore)
- [x] Hive (persistente) — ProfileStaticCacheService
- [ ] SharedPreferences
- [ ] SQLite/Isar
- [ ] nada

**Seu cache tem TTL?**
- [x] Sim (imagens: cache persistente; ex.: avatar cache 90 dias)
- [ ] Não
- [ ] Não sei

**Você usa “stale-while-revalidate”?**
- [x] Sim *(Hive cache → render imediato + revalidate em background)*
- [ ] Não

**Você tem “in-flight dedup”?**
- [x] Sim, para userId no UserStore (1 stream por usuário)
- [ ] Não

---

## 7) Estratégias de redução (marque o que faz sentido)

**Avatar + header**
- [x] trocar stream por future + cache (campos estáveis)
- [x] dividir doc: “volatile” (online/status) separado do “profile”
- [x] manter em memória por sessão
- [x] persistir em Hive com TTL (ex: 24h)

**Galeria**
- [x] paginação agressiva (ex: 12 por vez)
- [x] cache das URLs
- [x] thumbnails primeiro
- [x] pré-carregar apenas quando entrar no viewport

**Reviews + avatares de reviewers**
- [x] denormalizar authorName/authorAvatar no review (completar campos faltantes)
- [x] carregar apenas 5-10 reviews e paginar
- [x] batch/bulk fetch (quando suportado) + cache por ID
- [x] **stats agora vêm de users_stats (1 doc) e não leem N reviews**

---

## 8) Medição

**Você já instrumentou reads por tela?**
- [ ] Sim
- [x] Não

**Você consegue registrar por abertura da ProfileScreen:**
- quantos .get() / quantos streams
- quantos docs lidos
- quantos bytes/imagens carregadas
- tempo até first paint

- [ ] Sim
- [x] Não

✅ Se não tiver, cria um “contador de reads por sessão da tela” e pronto.
