🌐 PLANO OFICIAL DE IMPLEMENTAÇÃO — Sistema de Notificações Por Raio + Afinidade

Projeto: Partiu
Data: 6 de dezembro de 2025
Objetivo: Notificar usuários relevantes quando uma atividade é criada, esquentando ou atualizada.

1. Problema Atual

- Triggers hoje fazem tudo:

- query geográfica

- cálculo de distância

- business logic

- montagem de texto

- criação da notificação

**Isso gera:**

- alta complexidade

- dificuldade de testes

- inconsistência

- alto consumo de Firestore

- risco de SPAM (notificação irrelevante)

2. Nova Arquitetura em 4 Camadas

Essa arquitetura separa responsabilidades e permite escalonar para Cloud Functions no futuro:

┌───────────────────────────────┐
│ CAMADA 0 — Infra: GeoIndex    │
│  → Busca usuários no raio     │
└───────────────────────────────┘
               ↓
┌───────────────────────────────┐
│ CAMADA 1 — Afinidade          │
│  → Interesses em comum        │
└───────────────────────────────┘
               ↓
┌───────────────────────────────┐
│ CAMADA 2 — Targeting          │
│  → Quem deve receber           │
└───────────────────────────────┘
               ↓
┌───────────────────────────────┐
│ CAMADA 3 — Orchestrator       │
│  → Criação em batch           │
└───────────────────────────────┘
               ↓
┌───────────────────────────────┐
│ CAMADA 4 — Trigger            │
│  → Apenas dispara              │
└───────────────────────────────┘

3. Nova Regra de Negócio Importante
🚫 NÃO notificar todos os usuários no raio.
🎯 SIM notificar apenas:

Usuários dentro do raio de 30km

Que possuem pelo menos um interesse em comum com o criador da atividade

Isso reduz SPAM e aumenta relevância.

4. Camadas em Detalhes
CAMADA 0 — GeoIndexService

Arquivo:
lib/core/services/geo_index_service.dart

Responsável por:

bounding box

queries geográficas

cálculos de distância

paginação para grandes volumes

Retorno:
List<String> de userIds dentro do raio.

CAMADA 1 — UserAffinityService

Arquivo:
lib/features/notifications/services/user_affinity_service.dart

Responsável por:

buscar interesses do criador

buscar interesses de usuários no raio

calcular interseção

ordenar por relevância

Retorno:
Map<userId, List<String>> → afinidade por usuário.

CAMADA 2 — NotificationTargetingService

Arquivo:
lib/features/notifications/services/notification_targeting_service.dart

Responsável por decidir quem recebe a notificação.

Exemplos:

activity_created → geo + afinidade

heating_up → somente participantes

join_request → criador

join_approved → solicitante

CAMADA 3 — NotificationOrchestrator

Arquivo:
lib/features/notifications/services/notification_orchestrator.dart

Responsável por:

criar documentos na coleção Notifications

batch writes de até 500

enriquecer notificações com dados como afinidade, emoji etc.

CAMADA 4 — Trigger

Arquivo:
activity_created_trigger.dart

Trigger agora:

NÃO faz cálculo geográfico

NÃO busca interesses

NÃO cria texto de notificação

NÃO cria documento Firestore

Ele faz apenas:

final targets = await targetingService.getUsersForActivityCreated(activity);
final creator = await userRepo.getUserById(activity.createdBy);

await orchestrator.createActivityCreatedNotifications(
  activity: activity,
  affinityMap: targets,
  creator: creator,
);


Simples, limpo, testável.

5. Fluxo Completo — Atividade Criada
Trigger
  ↓
TargetingService
  ↓
GeoIndexService → lista usuários no raio
  ↓
UserAffinityService → filtra por interesses
  ↓
TargetingService → retorna mapa final userId → interessesEmComum
  ↓
Orchestrator → batch write (500+500 etc)
  ↓
Firestore Notifications

6. Melhorias Técnicas de Performance
Bounding Box (reduz Firestore em até 80%)
Paginação para consulta de milhares de usuários
Batch Writes (até 500 operações por commit)
Logs estruturados para debug
7. Padronização dos Textos das Notificações

Todo trigger deve usar o NotificationTemplateEngine, nunca templates manuais.

Arquivos sugeridos:

lib/features/notifications/templates/notification_templates.dart


A trigger não escreve texto.
Ela chama:

final template = NotificationTemplates.activityCreated(
  creatorName: creator.fullName,
  activityName: activity.name,
  emoji: activity.emoji,
  commonInterests: commonInterests,
);

8. Checklist de Arquitetura
Criar:

✔ GeoIndexService
✔ UserAffinityService
✔ NotificationTargetingService
✔ NotificationOrchestrator
✔ NotificationTemplateEngine (modelo)
✔ trigger minimalista

Atualizar:

✔ ActivityCreatedTrigger
✔ ActivityHeatingUpTrigger
✔ Outros triggers

Garantir:

✔ DI com GetIt
✔ Testes unitários por camada
✔ Logs estruturados

9. Checklist de Deploy

Criar serviços (camadas 0-3)

Alterar triggers

Atualizar DI

Testar atividade criada com 10, 100, 500 usuários simulados

Verificar batch writes

Validar no app:

notificações aparecem

textos padronizados

navegação consistente

10. Resultado Final Esperado
Antes

Muitas notificações irrelevantes

Sistema confuso, difícil de testar

Código duplicado

Trigger enorme e pouco escalável

Depois

👥 Notificações hiper relevantes

📦 Arquitetura modular e testável

🚀 Melhor performance

🔄 Pronto para migrar para Cloud Functions

📐 Código limpo e padronizado

📣 Notificações ricas com afinidade (“vocês combinam em X”)