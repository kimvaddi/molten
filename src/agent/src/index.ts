// Polyfill globalThis.crypto for Azure SDK (@typespec/ts-http-runtime)
// Must be before any Azure SDK imports
import { webcrypto } from "node:crypto";
if (typeof globalThis.crypto === "undefined") {
  (globalThis as any).crypto = webcrypto;
}

import express from "express";
import { consumeQueue } from "./queue-worker";
import { QueueServiceClient } from "@azure/storage-queue";
import { DefaultAzureCredential } from "@azure/identity";

const app = express();
const PORT = process.env.PORT || 8080;

app.use(express.json());

// Health check endpoint (used by Container Apps)
app.get("/healthz", (_req, res) => res.status(200).send("ok"));
app.get("/ready", (_req, res) => res.status(200).send("ready"));

// ============ WEBHOOK ENDPOINTS ============
// These replace Azure Functions (blocked by enterprise quota)

// Telegram webhook
app.post("/webhook/telegram", async (req, res) => {
  try {
    const body = req.body;

    if (!body?.message?.chat?.id) {
      return res.status(400).send("Invalid request");
    }

    const chatId = body.message.chat.id;
    const text = body.message.text ?? "";

    if (!text.trim()) {
      return res.status(200).send("ok");
    }

    // Block prompt injection
    const blocked = [/ignore.*previous.*instructions/i, /system.*prompt/i, /jailbreak/i];
    if (blocked.some((p) => p.test(text))) {
      console.warn(`Blocked suspicious input from chat ${chatId}`);
      return res.status(200).send("ok");
    }

    // Enqueue work
    await enqueueWork({
      channel: "telegram",
      chatId,
      userId: body.message.from?.id,
      username: body.message.from?.username,
      text,
      timestamp: Date.now(),
    });

    console.log(`Enqueued work for Telegram chat ${chatId}`);
    res.status(200).send("ok");
  } catch (error) {
    console.error("Telegram webhook error:", error);
    res.status(500).send("error");
  }
});

// Slack webhook
app.post("/webhook/slack", async (req, res) => {
  try {
    const body = req.body;

    // Slack URL verification challenge
    if (body.type === "url_verification" && body.challenge) {
      return res.status(200).send(body.challenge);
    }

    if (body.type === "event_callback" && body.event?.type === "message") {
      const event = body.event;
      if (event.text?.trim()) {
        await enqueueWork({
          channel: "slack",
          chatId: event.channel,
          userId: event.user,
          text: event.text,
          timestamp: Date.now(),
        });
        console.log(`Enqueued work for Slack channel ${event.channel}`);
      }
    }

    res.status(200).send("ok");
  } catch (error) {
    console.error("Slack webhook error:", error);
    res.status(500).send("error");
  }
});

// Admin status endpoint
app.get("/admin/status", (_req, res) => {
  res.json({
    status: "healthy",
    version: "1.0.0",
    model: process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini",
    timestamp: new Date().toISOString(),
  });
});

// Control UI
app.get("/", (_req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html><head><title>Moltbot Agent</title></head>
    <body style="font-family:sans-serif;max-width:600px;margin:50px auto;">
      <h1>Moltbot Agent</h1>
      <p>Status: Running</p>
      <p>Model: ${process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini"}</p>
      <h2>Webhook Endpoints</h2>
      <ul>
        <li>POST /webhook/telegram</li>
        <li>POST /webhook/slack</li>
      </ul>
    </body></html>
  `);
});

// ============ QUEUE HELPER ============
async function enqueueWork(workItem: Record<string, unknown>): Promise<void> {
  const storageAccountName = process.env.STORAGE_ACCOUNT_NAME;
  const queueName = process.env.QUEUE_NAME || "molten-work";

  if (!storageAccountName) {
    console.error("STORAGE_ACCOUNT_NAME not set");
    return;
  }

  const credential = new DefaultAzureCredential();
  const queueUrl = `https://${storageAccountName}.queue.core.windows.net/${queueName}`;
  const queueClient = new (await import("@azure/storage-queue")).QueueClient(
    queueUrl,
    credential
  );

  await queueClient.sendMessage(
    Buffer.from(JSON.stringify(workItem)).toString("base64")
  );
}

// Start queue worker and server
console.log("Starting Moltbot agent...");
consumeQueue().catch((err) => {
  console.error("Queue worker failed:", err);
  process.exit(1);
});

app.listen(PORT, () => console.log(`Agent listening on port ${PORT}`));
