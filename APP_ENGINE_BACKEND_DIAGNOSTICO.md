# Diagnóstico de Consumo — App Engine (backend sempre ligado)

Data: 28 de janeiro de 2026

## Evidências rápidas no repo
- Há código em functions/ (Firebase Functions), indicando uso de backend serverless.
- Não há configuração explícita de App Engine no workspace.

---

## 🚀 BLOCO 3 — App Engine (backend sempre ligado)

**Seu backend:**

- [ ] Fica rodando 24/7
- [ ] Escala automaticamente
- [x] Só ativa quando recebe request
- [ ] Não sei

**Você tem:**

- [ ] Jobs em loop
- [ ] Workers rodando sempre
- [ ] Processos agendados frequentes
- [x] Nada disso

**Muitas rotas fazem:**

- [ ] Consultas pesadas
- [ ] Processamento de imagem
- [ ] Agregações grandes
- [x] Apenas leitura simples

**Parte do backend poderia ser:**

- [ ] Cloud Functions sob demanda
- [ ] Serverless
- [x] Já é tudo serverless
- [ ] Não sei

---

## Notas objetivas
- O projeto aparenta operar majoritariamente via Firebase Functions (serverless). Caso existam serviços externos não versionados no repo, revisar esses itens.
