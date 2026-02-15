/**
 * 🚩 Feature Flags — leitura de flags do Firestore (Ops/runtime_flags)
 *
 * Usa cache em memória com TTL curto para evitar leituras frequentes.
 */

import * as admin from "firebase-admin";

const FLAGS_DOC = "Ops/runtime_flags";
const CACHE_TTL_MS = 60 * 1000; // 1 minuto

let cachedFlags: Record<string, unknown> | null = null;
let cacheExpiresAt = 0;

async function loadFlags(): Promise<Record<string, unknown>> {
  const now = Date.now();
  if (cachedFlags && now < cacheExpiresAt) {
    return cachedFlags;
  }

  try {
    const doc = await admin.firestore().doc(FLAGS_DOC).get();
    cachedFlags = doc.exists ? (doc.data() as Record<string, unknown>) : {};
  } catch (error) {
    console.error("⚠️ [featureFlags] Erro ao ler flags:", error);
    // Em caso de erro, retorna cache antigo ou vazio
    if (!cachedFlags) cachedFlags = {};
  }

  cacheExpiresAt = now + CACHE_TTL_MS;
  return cachedFlags;
}

/**
 * Retorna o valor booleano de uma feature flag.
 * @param {string} flagName Nome da flag no documento Ops/runtime_flags
 * @param {boolean} defaultValue Valor padrão se a flag não existir
 * @return {Promise<boolean>} Valor da flag
 */
export async function getBooleanFeatureFlag(
  flagName: string,
  defaultValue: boolean
): Promise<boolean> {
  const flags = await loadFlags();
  const value = flags[flagName];
  if (typeof value === "boolean") return value;
  return defaultValue;
}
