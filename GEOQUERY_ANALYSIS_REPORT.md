# Diagnóstico Completo — Places API & Geocoding (Resultados Finais)

## Resumo Executivo
Implementamos uma arquitetura de "Geocoding Inteligente" e otimizamos o `PlacePicker` para seguir os padrões da indústria de eficiência de custo.

**Principais Vitórias:**
1.  **Geocoding Gratuito:** Substituímos a API paga do Google Web Service pela API nativa (iOS/Android) para Geocoding Reverso.
2.  **Nearby Search Sob Demanda:** Eliminamos a "torneira aberta" de buscas automáticas; agora só busca se o usuário clicar.
3.  **Cache Persistente:** Adicionamos cache de 30 dias para endereços.

## 🛡️ Auditoria de "Escape Hatches" (Vazamentos)
Realizamos uma varredura completa no código para garantir que **100% das chamadas** passem pelo `SmartGeocodingService`.

*   [x] `lib/plugins/locationpicker/widgets/place_picker.dart`: **Migrado**.
*   [x] `lib/features/location/data/repositories/location_repository.dart`: **Migrado**.
*   [x] `lib/core/services/location_background_updater.dart`: **Migrado** (estava usando plugin direto sem cache).
*   [x] `lib/features/home/presentation/screens/location_picker/place_service.dart`: **MIGRADO**. (Este era o vilão silencioso que usava `http.get` direto no Google API).

**Veredito:** O "custo de Reverse Geocoding" agora é virtualmente **ZERO** do ponto de vista de faturamento Google.

---

## 0) Inventário de APIs

**0.1) APIs em uso:**
*   [x] (A) Places Autocomplete: Usado na barra de busca do Picker (Otimizado com debounce de 500ms).
*   [x] (B) Place Details: Usado ao selecionar sugestão. **Otimizado** com `fields=geometry,name` (Custo reduzido).
*   [x] (C) Nearby Search: Usado no Picker (agora sob demanda).
*   [x] (D) Geocoding API (Reverse): Eliminado o uso da versão paga.
*   [ ] (E) Directions / Distance Matrix
*   [ ] (F) Places Photos (Desativado)

**0.2) Gatilhos de Chamada:**
*   (A) Abertura do mapa: **Sim** (tracking de localização em background).
*   (B) cameraIdle / movimento: **Otimizado** (Cache Local + Delay).
*   (C) Busca manual: **Sim** (Autocomplete).
*   (D) Seleção de resultado: **Sim** (Place Details).

---

## 1) Reverse Geocode (Geocoding API) — ✅ BLINDADO

**Diagnóstico Anterior:** Vício em chamadas repetitivas via Web API ($$).
**Situação Atual:**
*   **1.1 Gatilho:** Ao mover o pino (`moveToLocation`) e em background (`MapViewModel`).
*   **1.2 Frequência:** Debounce Lógico de **8 segundos** implementado no `SmartGeocodingService`.
*   **1.3 Distância Mínima:** **300 metros** obrigatórios para nova atualização.
*   **1.4 Micro-movimentos:** Ignorados pelo filtro de Distância e Tempo.
*   **1.5 Cache:** **Sim, Persistente (Hive)** com TTL de 30 dias.
*   **Fonte de Dados:** Trocado de Google Web API ($) para **Plataforma Nativa (Grátis)**.

---

## 2) Nearby / Search (Places) — ✅ RESOLVIDO

**Diagnóstico Anterior:** Chamava automaticamente ao mover o mapa "torneira aberta".
**Situação Atual:**
*   **2.1 Gatilho:** **(C) Ação do usuário** ("Buscar nesta área").
*   **2.2 Raio:** Limitado a 150m.
*   **2.3 Paginação:** Não consome páginas extras automaticamente.
*   **2.4 Cache:** Não necessário pois as chamadas agora são raras e intencionais.

---

## 3) Autocomplete — ✅ SUPER OTIMIZADO

**Situação Atual:**
*   **3.1 Frequência:** Debounce de **500ms** garantido no `LocationPickerController`.
*   **3.2 Regra de Ouro:** Chamadas bloqueadas para queries com menos de **3 caracteres**.
*   **3.3 Session Token:** **Sim**, garantindo agrupamento de busca.
*   **3.4 Cache:** **Implementado (60s)**. Buscas repetidas (backspace/redo) ou rápidas não tocam a API.
*   **3.5 Relevância:** País restrito (`components=country:..`) para evitar resultados internacionais irrelevantes.

---

## 4) Place Details — ✅ MAXIMIZADO

**Diagnóstico Atual:**
*   **4.1 Fields Mask:** **ATIVADO E REFINADO**.
    *   `PlaceService`: `fields=name,formatted_address,geometry,place_id`. (Removido `address_components` desnecessários).
    *   `PlacePicker`: `fields=geometry,name`.
    *   **Economia:** Redução de payload e processamento. Mantido no SKU Basic, mas com menor latência e overhead.
    *   **Dados Obtidos:** Apenas coordenadas, nome e endereço formatado. Dados estruturados (city/state) são obtidos via `SmartGeocoding` (Grátis) se necessário.

---

## Próximos Passos (Monitoramento)

1.  **Observar Custos:** Verificar o console do Google Cloud nos próximos 2-3 dias. A curva de custo de Geocoding deve achatar para perto de zero. Places API deve cair significativamente.
2.  **Monitorar Logs:** Observar logs com a tag `[SmartGeo]` para garantir que o cache está registrando "HIT".
