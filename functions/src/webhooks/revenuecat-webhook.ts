import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {sendPush} from "../services/pushDispatcher";
// import * as crypto from "crypto";
// Unused for now as we rely on Bearer token

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const firestore = admin.firestore();

interface RevenueCatEvent {
  type: string;
  app_user_id: string;
  original_app_user_id: string;
  product_id: string;
  period_type: string;
  purchased_at_ms: number;
  expiration_at_ms: number | null;
  environment: "SANDBOX" | "PRODUCTION";
  entitlement_id: string | null;
  entitlement_ids: string[];
  presented_offering_id: string | null;
  transaction_id: string;
  original_transaction_id: string;
  is_family_share: boolean;
  country_code: string;
  app_id: string;
  aliases: string[];
  store: "APP_STORE" | "MAC_APP_STORE" | "PLAY_STORE" | "PROMOTIONAL" |
    "STRIPE" | "AMAZON";
  price: number;
  currency: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  subscriber_attributes: Record<string, any>;
  takehome_percentage: number;
  offer_code: string | null;
  is_trial_conversion: boolean;
  cancel_reason: string | null;
  new_product_id: string | null;
  grace_period_expiration_at_ms: number | null;
  auto_resume_at_ms: number | null;
}

interface RevenueCatWebhookPayload {
  api_version: string;
  event: RevenueCatEvent;
}

/**
 * Remove undefined values from object (Firestore doesn't accept undefined)
 * @param {Record<string, unknown>} obj Object to clean
 * @return {Record<string, unknown>} Cleaned object
 */
function removeUndefinedFields(obj: Record<string, unknown>):
  Record<string, unknown> {
  const cleaned: Record<string, unknown> = {};
  for (const key in obj) {
    if (obj[key] !== undefined) {
      cleaned[key] = obj[key];
    }
  }
  return cleaned;
}

/**
 * Webhook do RevenueCat
 *
 * Setup no RevenueCat Dashboard:
 * 1. Project Settings → Integrations → Webhooks
 * 2. URL: https://us-central1-YOUR_PROJECT.cloudfunctions.net/revenueCatWebhook
 * 3. Authorization: Bearer YOUR_SECRET
 * 4. Events: INITIAL_PURCHASE, RENEWAL, EXPIRATION, CANCELLATION
 *
 * Secret no Firebase:
 * firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
 */

export const revenueCatWebhook = functions
  .runWith({secrets: ["REVENUECAT_WEBHOOK_SECRET"]})
  .https.onRequest(async (req, res) => {
    // CORS headers for preflight requests
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(200).send("OK");
      return;
    }

    if (req.method !== "POST") {
      console.error("❌ [RevenueCat Webhook] Method not allowed:", req.method);
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      console.log("📥 [RevenueCat Webhook] Received request");
      // console.log('Headers:', JSON.stringify(req.headers, null, 2));
      // console.log('Body:', JSON.stringify(req.body, null, 2));

      // 1. Validate Authorization Header
      const expectedSecret = process.env.REVENUECAT_WEBHOOK_SECRET;

      if (!expectedSecret) {
        console.error(
          "❌ [RevenueCat Webhook] Server misconfigured - missing secret"
        );
        res.status(500).send("Server misconfigured");
        return;
      }

      const authHeader = req.headers.authorization?.trim();

      const bearerMatch = authHeader?.match(/^Bearer\s+(.+)$/i);
      const bearerToken = bearerMatch?.[1];

      const isAuthorized = Boolean(authHeader) && (
        authHeader === expectedSecret ||
        bearerToken === expectedSecret
      );

      if (!isAuthorized) {
        console.error(
          "❌ [RevenueCat Webhook] Unauthorized - Invalid auth header"
        );
        res.status(401).send("Unauthorized");
        return;
      }
      console.log("✅ [RevenueCat Webhook] Authorization validated");

      // 🔍 Debug: Log request details to detect duplicates
      const requestId = req.headers["x-request-id"] || "unknown";
      const userAgent = req.headers["user-agent"] || "unknown";
      console.log("🔍 [RevenueCat Webhook] Request metadata:", {
        requestId,
        userAgent,
        contentLength: req.headers["content-length"],
        timestamp: new Date().toISOString(),
      });

      // 2. Validate Webhook Signature (if shared secret is configured)
      // Note: In Partiu we are using Bearer token validation above,
      // but we can add signature check if needed.
      // For now, we rely on the Bearer token which is standard for RevenueCat.

      // 3. Parse webhook payload
      // O payload do RevenueCat vem dentro de um objeto 'event'
      const payload = req.body as RevenueCatWebhookPayload;
      // Fallback caso venha direto (teste manual)
      const event = payload.event || req.body;
      const userId = event.app_user_id;

      if (!event) {
        console.error(
          "❌ [RevenueCat Webhook] Invalid event data - no event object"
        );
        res.status(400).send("Invalid event data");
        return;
      }

      // Log do tipo de evento recebido
      console.log(
        `🎯 [RevenueCat Webhook] Processing event type: ${event.type}`
      );

      // Eventos especiais que não têm app_user_id (TRANSFER, etc)
      const specialEvents = ["TRANSFER", "TEST"];

      if (!userId && !specialEvents.includes(event.type)) {
        console.error(
          "❌ [RevenueCat Webhook] Invalid event data - missing app_user_id"
        );
        res.status(400).send("Invalid event data - missing app_user_id");
        return;
      }

      // 🚫 Rejeita usuários anônimos do RevenueCat
      if (userId && userId.startsWith("$RCAnonymousID:")) {
        console.warn(`⚠️ Webhook com usuário anônimo: ${userId}`);
        console.warn(
          "💡 Usuário precisa fazer login com Firebase antes de comprar"
        );
        res.status(400).send(
          "Anonymous users not supported - login required"
        );
        return;
      }

      // Skip eventos especiais que não afetam assinaturas
      if (specialEvents.includes(event.type)) {
        console.log(
          `⏭️ [RevenueCat Webhook] Skipping ${
            event.type
          } event (não afeta subscription status)`
        );
        res.status(200).send("OK - Event ignored");
        return;
      }

      console.log(
        `📝 [RevenueCat Webhook] Processing ${event.type} for user: ${userId}`
      );

      // Log detalhado dos entitlements e offerings
      console.log("🎫 [RevenueCat Webhook] Entitlements check:", {
        entitlement_id: event.entitlement_id,
        entitlement_ids: event.entitlement_ids,
        entitlement_ids_length: event.entitlement_ids?.length || 0,
        has_entitlement_id: event.entitlement_id !== null,
        has_entitlement_ids: event.entitlement_ids &&
          event.entitlement_ids.length > 0,
      });

      console.log("🎁 [RevenueCat Webhook] Offerings check:", {
        presented_offering_id: event.presented_offering_id,
        has_presented_offering: event.presented_offering_id !== null,
      });

      console.log("📦 [RevenueCat Webhook] Product details:", {
        product_id: event.product_id,
        period_type: event.period_type,
        store: event.store,
        environment: event.environment,
      });

      // 4. Process the event
      await processRevenueCatEvent(event);

      console.log("✅ [RevenueCat Webhook] Event processed successfully");
      res.status(200).send("OK");
      return;
    } catch (error) {
      console.error("❌ [RevenueCat Webhook] Error processing webhook:", error);
      // Return 500 for unexpected errors so RevenueCat retries
      res.status(500).send("Internal Server Error");
    }
  });

/**
 * Process RevenueCat event and update Firestore
 * @param {RevenueCatEvent} event RevenueCat event
 * @return {Promise<void>} Promise
 */
async function processRevenueCatEvent(event: RevenueCatEvent): Promise<void> {
  const userId = event.app_user_id;
  const eventType = event.type;

  // ✅ REMOVIDO: ProcessedWebhookEvents - desnecessária
  // 🎯 Idempotência natural via Firestore merge: true
  // 💡 userId como doc ID + merge: true = sem duplicação

  console.log(
    `📝 [RevenueCat Webhook] Processing ${eventType} for user ${userId}`
  );

  // 🔥 FIX: Separar assinaturas de pagamentos únicos
  if (eventType === "NON_RENEWING_PURCHASE") {
    // Processar como pagamento único na coleção PaymentStatuses
    await processNonRenewingPurchase(event);
    return;
  }

  // Processar como assinatura na coleção SubscriptionStatus
  await processSubscriptionEvent(event);
}

/**
 * Process non-renewing (one-time) purchases -> PaymentStatuses collection
 * ✅ NEW: Also updates PendingApplications with transaction_id
 * for consumable product tracking
 * @param {RevenueCatEvent} event RevenueCat event
 * @return {Promise<void>} Promise
 */
async function processNonRenewingPurchase(
  event: RevenueCatEvent
): Promise<void> {
  const userId = event.app_user_id;

  console.log(`💰 [NON_RENEWING_PURCHASE] Processing for user ${userId}`);
  console.log(
    "💰 [NON_RENEWING_PURCHASE] transaction_id: " + event.transaction_id
  );
  console.log(
    "💰 [NON_RENEWING_PURCHASE] product_id: " + event.product_id
  );

  // 1️⃣ Salvar em PaymentStatuses (histórico)
  const paymentDataRaw = {
    user_id: userId,
    product_id: event.product_id,
    store: event.store.toLowerCase(),
    environment: event.environment.toLowerCase(),

    // Transaction details
    transaction_id: event.transaction_id,
    original_transaction_id: event.original_transaction_id,

    // Purchase details
    purchased_at: event.purchased_at_ms ?
      admin.firestore.Timestamp.fromMillis(event.purchased_at_ms) :
      null,
    price_usd: event.price,
    currency: event.currency,
    country_code: event.country_code,

    // Status
    status: "paid", // Non-renewing purchases are immediately paid
    payment_type: "one_time",

    // Event metadata
    last_event_type: event.type,
    last_event_at: admin.firestore.FieldValue.serverTimestamp(),
    webhook_received_at: admin.firestore.FieldValue.serverTimestamp(),

    // Additional fields
    is_family_share: event.is_family_share,
    offer_code: event.offer_code || null, // Force null instead of undefined

    // Raw event for debugging
    raw_event: event,
  };

  const paymentData = removeUndefinedFields(paymentDataRaw);
  const paymentRef = firestore.collection("PaymentStatuses")
    .doc(event.transaction_id);
  await paymentRef.set(paymentData, {merge: true});

  console.log(
    "✅ [NON_RENEWING_PURCHASE] Saved to PaymentStatuses: " +
    event.transaction_id
  );

  // 2️⃣ ✅ NOVO: Buscar PendingApplication via subscriber_attributes
  const pendingAttr = event.subscriber_attributes?.["pending_application_id"];

  // ⚠️ RevenueCat pode enviar como string direta ou objeto { value: "..." }
  const pendingAppId = typeof pendingAttr === "string" ?
    pendingAttr :
    pendingAttr?.value;

  if (!pendingAppId) {
    console.warn(
      "⚠️ [NON_RENEWING_PURCHASE] No pending_application_id"
    );
    console.warn(
      "⚠️ [NON_RENEWING_PURCHASE] Cannot link purchase to application"
    );
    return;
  }

  console.log(
    `🔍 [NON_RENEWING_PURCHASE] Found pending_application_id: ${
      pendingAppId
    }`
  );

  // 3️⃣ ✅ Buscar PendingApplication
  const pendingRef = firestore.collection("PendingApplications")
    .doc(pendingAppId);
  const pendingDoc = await pendingRef.get();

  if (!pendingDoc.exists) {
    console.error(
      "❌ [NON_RENEWING_PURCHASE] PendingApplication NOT FOUND: " + pendingAppId
    );
    return;
  }

  console.log(
    `✅ [NON_RENEWING_PURCHASE] Found PendingApplication: ${pendingAppId}`
  );

  // 4️⃣ ✅ Validar transaction_id único (previne re-consumo)
  const existingTxQuery = await firestore
    .collection("PendingApplications")
    .where("transaction_id", "==", event.transaction_id)
    .where("used", "==", true)
    .limit(1)
    .get();

  if (!existingTxQuery.empty) {
    console.error(
      `❌ [NON_RENEWING_PURCHASE] transaction_id ${
        event.transaction_id
      } ALREADY CONSUMED`
    );
    console.error(
      `❌ [NON_RENEWING_PURCHASE] Used in: ${existingTxQuery.docs[0].id}`
    );
    return;
  }

  console.log(
    "✅ [NON_RENEWING_PURCHASE] transaction_id is unique and not consumed"
  );

  // 5️⃣ ✅ Atualizar PendingApplication com transaction_id
  await pendingRef.update({
    transaction_id: event.transaction_id,
    payment_verified: true,
    verified_at: admin.firestore.FieldValue.serverTimestamp(),
    webhook_event_type: event.type,
    webhook_received_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(
    `✅ [NON_RENEWING_PURCHASE] Updated PendingApplication ${pendingAppId}`
  );
  console.log(
    "✅ [NON_RENEWING_PURCHASE] Payment verified and ready to consume"
  );

  // Don't update user VIP status for one-time payments
  // One-time payments don't affect subscription status
}

/**
 * Process subscription events -> SubscriptionStatus collection
 * @param {RevenueCatEvent} event RevenueCat event
 * @return {Promise<void>} Promise
 */
async function processSubscriptionEvent(event: RevenueCatEvent): Promise<void> {
  const userId = event.app_user_id;
  const eventType = event.type;

  console.log(
    `🔄 [RevenueCat Webhook] Processing subscription event: ${
      eventType
    } for user ${userId}`
  );
  console.log("📊 [RevenueCat Webhook] Event details:", {
    product_id: event.product_id,
    entitlement_id: event.entitlement_id,
    entitlement_ids: event.entitlement_ids,
    store: event.store,
    environment: event.environment,
    expiration_at_ms: event.expiration_at_ms,
  });

  // Determine if subscription is currently active based on event type
  const isActive = determineActiveStatus(eventType, event);
  console.log(`✅ [RevenueCat Webhook] Computed isActive: ${isActive}`);

  // ✅ FIX: Accept any entitlement from the event
  // O Partiu usa "assinaturas" como entitlement ID no RevenueCat
  const hasAnyEntitlement = (
    (event.entitlement_ids && event.entitlement_ids.length > 0) ||
    event.entitlement_id !== null
  );

  // Get the primary entitlement ID (first in array or single value)
  const primaryEntitlement = event.entitlement_ids?.[0] ||
    event.entitlement_id ||
    null;

  console.log(
    "🔍 [RevenueCat Webhook] Entitlement verification for user",
    userId
  );
  console.log("📋 [RevenueCat Webhook] Entitlement data:", {
    event_entitlement_id: event.entitlement_id,
    event_entitlement_ids: event.entitlement_ids,
    entitlement_ids_array_length: event.entitlement_ids?.length || 0,
    primary_entitlement: primaryEntitlement,
    has_any_entitlement: hasAnyEntitlement,
    is_active_from_event: isActive,
    computed_is_active: isActive && hasAnyEntitlement,
  });
  console.log("🎁 [RevenueCat Webhook] Offering info:", {
    presented_offering_id: event.presented_offering_id,
  });

  // ✅ FIX: Consider active if event determines active AND has any entitlement
  const finalIsActive = isActive && hasAnyEntitlement;

  console.log(
    `💾 [RevenueCat Webhook] Processing subscription with isActive: ${
      finalIsActive
    }`
  );
  console.log("💾 [RevenueCat Webhook] Subscription data to save:", {
    userId: userId,
    isActive: finalIsActive,
    entitlementId: primaryEntitlement,
    entitlementIds: event.entitlement_ids || [],
    productId: event.product_id,
    store: event.store?.toLowerCase(),
    environment: event.environment?.toLowerCase(),
    lastEventType: eventType,
  });

  // ✅ Update Users collection with VIP/Verified status only
  // (no subscription metadata)
  try {
    const userRef = firestore.collection("Users").doc(userId);
    const userDoc = await userRef.get();

    if (userDoc.exists) {
      // ✅ FIX: Manter consistência entre campos VIP
      // Se não está ativo, vipExpiresAt deve ser null
      const vipExpiresAtValue = finalIsActive && event.expiration_at_ms ?
        admin.firestore.Timestamp.fromMillis(event.expiration_at_ms) :
        null;

      await userRef.update({
        // VIP status
        user_is_vip: finalIsActive,
        user_level: finalIsActive ? "vip" : "free",
        vip_priority: finalIsActive ? 1 : 2,

        // Legacy fields for compatibility
        // ✅ FIX: vipExpiresAt só é setado se finalIsActive = true
        vipExpiresAt: vipExpiresAtValue,
        vipProductId: finalIsActive ? (event.product_id || null) : null,
        vipUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(
        `✅ [RevenueCat Webhook] Updated user status for ${userId}:`, {
          user_is_vip: finalIsActive,
          user_level: finalIsActive ? "vip" : "free",
          vipExpiresAt: vipExpiresAtValue ? "set" : "null",
        }
      );
    } else {
      console.warn(
        `⚠️ [RevenueCat Webhook] User document not found for ${userId}`
      );
    }
  } catch (error) {
    console.error(
      `❌ [RevenueCat Webhook] Could not update user status: ${error}`
    );
    throw error; // Fail the webhook if we can't update user
  }

  // 📊 Update SubscriptionStatus collection (SINGLE SOURCE OF TRUTH)
  // Consolidates data from SubscriptionStatus, Subscriptions,
  // and SubscriptionEvents
  try {
    const subscriptionStatusRef = firestore.collection("SubscriptionStatus")
      .doc(userId);

    // ✅ Calcular expiração consistente com Users collection
    const expirationTimestamp = finalIsActive && event.expiration_at_ms ?
      admin.firestore.Timestamp.fromMillis(event.expiration_at_ms) :
      null;

    const subscriptionStatusDataRaw = {
      // Core identification
      user_id: userId,
      userId: userId, // Compatibility

      // Status - CONSISTENTE com Users collection
      status: finalIsActive ? "active" : "inactive",
      isActive: finalIsActive,

      // Entitlements
      entitlement_id: primaryEntitlement,
      entitlementId: primaryEntitlement,
      entitlement_ids: event.entitlement_ids || [],

      // Product info
      product_id: finalIsActive ? event.product_id : null,
      productId: finalIsActive ? event.product_id : null,
      period_type: event.period_type,
      periodType: event.period_type,

      // Store/Platform
      store: event.store?.toLowerCase() || null,
      environment: event.environment?.toLowerCase() || null,
      platform: event.store === "APP_STORE" ? "ios" :
        (event.store === "PLAY_STORE" ? "android" : "unknown"),

      // Timestamps - CONSISTENTE: null quando inativo
      expiration_at: expirationTimestamp,
      expiresAt: expirationTimestamp,
      purchased_at: event.purchased_at_ms ?
        admin.firestore.Timestamp.fromMillis(event.purchased_at_ms) :
        null,
      purchasedAt: event.purchased_at_ms ?
        admin.firestore.Timestamp.fromMillis(event.purchased_at_ms) :
        null,
      grace_period_expires_at: event.grace_period_expiration_at_ms ?
        admin.firestore.Timestamp.fromMillis(
          event.grace_period_expiration_at_ms
        ) :
        null,
      gracePeriodExpiresAt: event.grace_period_expiration_at_ms ?
        admin.firestore.Timestamp.fromMillis(
          event.grace_period_expiration_at_ms
        ) :
        null,

      // Event tracking
      last_event_type: eventType,
      lastEventType: eventType,
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      last_processed_at: admin.firestore.FieldValue.serverTimestamp(),
      webhook_received_count: admin.firestore.FieldValue.increment(1),

      // Transaction details
      transaction_id: event.transaction_id,
      transactionId: event.transaction_id,
      original_transaction_id: event.original_transaction_id,
      originalTransactionId: event.original_transaction_id,
      original_app_user_id: event.original_app_user_id,

      // Revenue details
      price_usd: event.price,
      priceUsd: event.price,
      currency: event.currency,
      country_code: event.country_code,
      countryCode: event.country_code,

      // Status details
      will_renew: finalIsActive &&
        !["CANCELLATION", "EXPIRATION"].includes(eventType),
      willRenew: finalIsActive &&
        !["CANCELLATION", "EXPIRATION"].includes(eventType),
      is_trial_conversion: event.is_trial_conversion,
      isTrialConversion: event.is_trial_conversion,
      is_family_share: event.is_family_share,
      isFamilyShare: event.is_family_share,
      cancel_reason: event.cancel_reason || null,
      cancelReason: event.cancel_reason || null,
      offer_code: event.offer_code || null,
      offerCode: event.offer_code || null,
      presented_offering_id: event.presented_offering_id,

      // Source
      source: "webhook",

      // Raw event (only in SANDBOX for debugging)
      raw_event: event.environment === "SANDBOX" ? event : null,
    };

    const subscriptionStatusData = removeUndefinedFields(
      subscriptionStatusDataRaw as Record<string, unknown>
    );

    // Create/update subscription status document with all relevant data
    await subscriptionStatusRef.set(subscriptionStatusData, {merge: true});

    console.log(
      "✅ [RevenueCat Webhook] Updated SubscriptionStatus for " + userId
    );
    console.log("✅ [RevenueCat Webhook] Subscription data saved:", {
      user_id: userId,
      status: finalIsActive ? "active" : "inactive",
      product_id: event.product_id,
      store: event.store?.toLowerCase(),
      entitlement_id: primaryEntitlement,
      has_expiration: event.expiration_at_ms !== null,
      webhook_count: "incremented",
    });
  } catch (error) {
    console.warn(
      `⚠️ [RevenueCat Webhook] Could not update SubscriptionStatus: ${error}`
    );
    // Don't fail the webhook for this
  }

  // Send notification to user (optional)
  if (shouldNotifyUser()) {
    await sendUserNotification(userId, eventType, finalIsActive);
  }
}

/**
 * Determine if subscription should be considered active based on event type
 * @param {string} eventType Type of the event
 * @param {RevenueCatEvent} event RevenueCat event
 * @return {boolean} True if active
 */
function determineActiveStatus(
  eventType: string,
  event: RevenueCatEvent
): boolean {
  const now = Date.now();
  const expirationMs = event.expiration_at_ms;

  switch (eventType) {
  case "INITIAL_PURCHASE":
  case "RENEWAL":
  case "PRODUCT_CHANGE":
  case "UNCANCELLATION":
    // Active if not expired
    return !expirationMs || expirationMs > now;

  case "CANCELLATION":
    // Still active until expiration
    return !expirationMs || expirationMs > now;

  case "BILLING_ISSUE": {
    // Check grace period
    const gracePeriodMs = event.grace_period_expiration_at_ms;
    return !gracePeriodMs || gracePeriodMs > now;
  }

  case "EXPIRATION":
    return false;

  default:
    console.warn(`⚠️ Unknown event type: ${eventType}`);
    // Conservative approach: check expiration
    return !expirationMs || expirationMs > now;
  }
}


/**
 * Check if user should be notified about subscription events
 * @return {boolean} True if user should be notified
 */
function shouldNotifyUser(): boolean {
  // ❌ Push de assinatura DESATIVADO - webhook só atualiza Firestore
  return false;
}

/**
 * Send push notification to user about subscription event
 * @param {string} userId User ID
 * @param {string} eventType Type of the event
 * @param {boolean} isActive Whether subscription is active
 * @return {Promise<void>} Promise
 */
async function sendUserNotification(
  userId: string,
  eventType: string,
  isActive: boolean
): Promise<void> {
  try {
    // Only send notifications for specific events
    const notifiableEvents = [
      "INITIAL_PURCHASE",
      // "RENEWAL", // DESATIVADO
      "BILLING_ISSUE",
      "EXPIRATION",
      "CANCELLATION",
    ];

    if (!notifiableEvents.includes(eventType)) {
      return;
    }

    // Template: systemAlert - mapear eventos RevenueCat para mensagens
    const APP_NAME = "Boora";
    let alertTitle = APP_NAME;
    let alertBody = "Você tem uma nova atualização";

    switch (eventType) {
    case "INITIAL_PURCHASE":
      alertTitle = "Bem-vindo ao Premium! 🎉";
      alertBody = "Sua assinatura foi ativada com sucesso";
      break;
    case "RENEWAL":
      alertTitle = "Assinatura renovada ✅";
      alertBody = "Sua assinatura foi renovada com sucesso";
      break;
    case "BILLING_ISSUE":
      alertTitle = "Problema com pagamento ⚠️";
      alertBody = "Verifique seus dados de pagamento";
      break;
    case "EXPIRATION":
      alertTitle = "Assinatura expirada";
      alertBody = "Sua assinatura Premium expirou";
      break;
    case "CANCELLATION":
      alertTitle = "Assinatura cancelada";
      alertBody = "Sua assinatura Premium foi cancelada";
      break;
    }

    await sendPush({
      userId: userId,
      event: "system_alert",
      origin: "revenuecatWebhook",
      notification: {
        title: alertTitle,
        body: alertBody,
      },
      data: {
        n_type: "system_alert",
        relatedId: eventType,
        n_related_id: eventType,
        event_type: eventType,
        is_active: isActive.toString(),
      },
    });

    console.log(
      `✅ [RevenueCat Webhook] Push enviado via dispatcher para ${userId}`
    );
  } catch (error) {
    console.error(
      `❌ [RevenueCat Webhook] Erro ao enviar push: ${error}`
    );
  }
}

