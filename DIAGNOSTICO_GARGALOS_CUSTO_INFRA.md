# Diagnóstico Rápido de Gargalos de Custo (Infra)

Data: 28 de janeiro de 2026

## Revisão rápida das páginas (onde há maior consumo de imagens)

Principais pontos onde o app consome mídia (network images):
- **Feed de eventos / Event Photo Feed**: cards e carrosséis com `CachedNetworkImage` + thumbnails.
- **Perfil de usuários**: header (PageView de fotos), grid de fotos e galeria.
- **Chat**: bolhas com mídia, lightbox e previews de resposta.
- **Mapa**: markers com avatar gerados a partir de imagens (cache de bitmap).
- **Media Viewer**: visualização fullscreen de imagens.

Observação: há uso predominante de `CachedNetworkImage` e cache managers dedicados (avatar, chat/mídia). Existem pontos pontuais com `NetworkImage` em comentários do feed, que podem escapar do cache em disco.

---

## ☁️ BLOCO 1 — Cloud Storage (mídia + tráfego)

**Onde os usuários mais veem imagens?**

- [x] Feed de eventos
- [x] Perfil de usuários
- [x] Chat (envio de fotos)
- [x] Mapa (thumbs de eventos)

**As imagens são:**

- [ ] Upload direto do celular sem compressão
- [x] Redimensionadas antes de salvar
- [ ] Comprimidas agressivamente
- [ ] Não sei

**Quando a tela abre, as imagens:**

- [ ] Sempre baixam de novo
- [ ] Usam cache local
- [x] Usam cache com TTL
- [ ] Não sei

**Um mesmo usuário vê a mesma imagem quantas vezes por sessão?**

- [ ] 1x
- [ ] 2–3x
- [x] muitas vezes (scroll, mapa, refresh)

**Você gera múltiplos tamanhos da mesma imagem?**

- [ ] Não (sempre full)
- [x] Sim (thumb + média + original)
- [ ] Não sei

---

## Notas objetivas

- **Compressão/redimensionamento**: há serviço dedicado de compressão antes do upload, com tamanhos reduzidos.
- **Thumbnails**: no Event Photo Feed existe upload de **thumb** separado.
- **Cache**: uso de `flutter_cache_manager` com TTL (avatar, mídia de chat e mídia geral).
- **Possível melhoria**: substituir `NetworkImage` em comentários do feed por `CachedNetworkImageProvider` para evitar re-downloads.
