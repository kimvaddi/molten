import { AzureFunction, Context, HttpRequest } from "@azure/functions";
import { QueueServiceClient } from "@azure/storage-queue";
import * as crypto from "crypto";

/**
 * WhatsApp Business Cloud API webhook handler.
 * GET  → Hub verification challenge
 * POST → Incoming message dispatch to queue
 */
const httpTrigger: AzureFunction = async (
  context: Context,
  req: HttpRequest
): Promise<void> => {
  // GET: WhatsApp webhook verification
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    const verifyToken = process.env.WHATSAPP_VERIFY_TOKEN;

    if (mode === "subscribe" && token === verifyToken) {
      context.log("WhatsApp webhook verified");
      context.res = { status: 200, body: challenge };
    } else {
      context.log.warn("WhatsApp webhook verification failed");
      context.res = { status: 403, body: "Forbidden" };
    }
    return;
  }

  // POST: Incoming message
  try {
    // Verify Meta signature (X-Hub-Signature-256)
    const signature = req.headers["x-hub-signature-256"];
    const appSecret = process.env.WHATSAPP_APP_SECRET;
    if (appSecret && signature) {
      const rawBody = JSON.stringify(req.body);
      const expected =
        "sha256=" +
        crypto
          .createHmac("sha256", appSecret)
          .update(rawBody)
          .digest("hex");
      if (signature !== expected) {
        context.log.warn("WhatsApp signature mismatch");
        context.res = { status: 403, body: "Invalid signature" };
        return;
      }
    }

    const body = req.body;
    const entry = body?.entry?.[0];
    const changes = entry?.changes?.[0];
    const value = changes?.value;

    if (!value?.messages?.[0]) {
      // Status update or non-message event — acknowledge
      context.res = { status: 200, body: "ok" };
      return;
    }

    const message = value.messages[0];
    const contact = value.contacts?.[0];
    const phoneNumberId = value.metadata?.phone_number_id;

    // Only handle text messages for now
    if (message.type !== "text" || !message.text?.body?.trim()) {
      context.res = { status: 200, body: "ok" };
      return;
    }

    const text = message.text.body;

    // Content safety: block obvious prompt injection
    const blockedPatterns = [
      /ignore.*previous.*instructions/i,
      /system.*prompt/i,
      /jailbreak/i,
    ];
    if (blockedPatterns.some((p) => p.test(text))) {
      context.log.warn(`Blocked suspicious WhatsApp input from ${message.from}`);
      context.res = { status: 200, body: "ok" };
      return;
    }

    // Enqueue work item
    const connectionString = process.env.AzureWebJobsStorage!;
    const queueName = process.env.QUEUE_NAME || "molten-work";
    const queueServiceClient =
      QueueServiceClient.fromConnectionString(connectionString);
    const queueClient = queueServiceClient.getQueueClient(queueName);

    const workItem = {
      channel: "whatsapp",
      chatId: message.from, // sender phone number
      userId: message.from,
      username: contact?.profile?.name || message.from,
      phoneNumberId,
      text,
      timestamp: Date.now(),
    };

    await queueClient.sendMessage(
      Buffer.from(JSON.stringify(workItem)).toString("base64")
    );

    context.log(`Enqueued WhatsApp message from ${message.from}`);
    context.res = { status: 200, body: "ok" };
  } catch (error) {
    context.log.error("WhatsApp webhook error:", error);
    context.res = { status: 500, body: "Internal server error" };
  }
};

export default httpTrigger;
