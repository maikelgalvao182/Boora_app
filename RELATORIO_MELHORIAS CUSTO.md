# Relatório de melhorias — Event Card e Find People

Data: 28 de janeiro de 2026

## Event Card (Mapa)

**Melhorias aplicadas**
- O card do evento passou a abrir usando apenas os dados já carregados pelo mapa.
- Ao tocar no marcador, o card evita reconsultas automáticas durante a abertura.
- O nome/identidade do organizador não é buscado de forma reativa ao abrir o card vindo do mapa.
- O mapa passou a consumir um conjunto de dados de eventos mais enxuto, focado no que é exibido no card.

**O que isso reduz no banco**
- Elimina leituras extras por toque em marcadores.
- Reduz consultas repetidas ao abrir vários eventos na mesma sessão.
- Evita chamadas indiretas por atualização de dados enquanto o card está aberto.
- Diminui o volume de dados transferidos por query do mapa.

---

## Find People

**Melhorias aplicadas**
- A tela não refaz a busca automaticamente ao retornar, respeitando um tempo de validade.
- A atualização só ocorre quando o usuário solicita manualmente ou quando o conteúdo está “antigo”.
- A lista passou a consumir dados de perfil mais enxutos, adequados apenas para preview.
- Foi adicionada medição simples de uso para acompanhar volume de consultas por sessão.

**O que isso reduz no banco**
- Corta reconsultas duplicadas ao navegar para perfil e voltar.
- Diminui picos de leitura em sessões longas com abre/fecha de tela.
- Mantém a experiência responsiva sem aumentar custo.
- Reduz o tráfego de dados por item listado.
- Dá visibilidade do que mais consome leitura, facilitando cortes futuros.
