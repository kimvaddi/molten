import { QueueClient } from "@azure/storage-queue";
import { DefaultAzureCredential } from "@azure/identity";
import { callModel } from "./llm/azureOpenAI";
import { sendTelegramMessage } from "./integrations/telegram";
import { checkSafety } from "./llm/safety";

interface WorkItem {
  channel: "telegram" | "slack" | "discord";
  chatId: number | string;
  userId?: number | string;
  username?: string;
  text: string;
  timestamp: number;
}

const POLL_INTERVAL_MS = 2000;

export async function consumeQueue(): Promise<void> {
  const storageAccountName = process.env.STORAGE_ACCOUNT_NAME;
  const queueName = process.env.QUEUE_NAME || "moltbot-work";

  if (!storageAccountName) {
    console.warn("STORAGE_ACCOUNT_NAME not set");
    return;
  }

  const credential = new DefaultAzureCredential();
  const queueUrl = `https://${storageAccountName}.queue.core.windows.net/${queueName}`;
  const queueClient = new QueueClient(queueUrl, credential);

  console.log(`Queue worker started, polling ${queueName}`);

  while (true) {
    try {
      const response = await queueClient.receiveMessages({
        numberOfMessages: 16,
        visibilityTimeout: 30,
      });

      for (const message of response.receivedMessageItems) {
        try {
          const payload = Buffer.from(message.messageText, "base64").toString("utf8");
          const item: WorkItem = JSON.parse(payload);

          console.log(`Processing ${item.channel} message from ${item.chatId}`);

          const safetyResult = await checkSafety(item.text);
          if (!safetyResult.safe) {
            console.warn(`Blocked: ${safetyResult.reason}`);
            await queueClient.deleteMessage(message.messageId, message.popReceipt);
            continue;
          }

          const response = await callModel(item.text);

          if (item.channel === "telegram") {
            await sendTelegramMessage(item.chatId as number, response);
          }

          await queueClient.deleteMessage(message.messageId, message.popReceipt);
        } catch (err) {
          console.error("Error processing:", err);
        }
      }
    } catch (err) {
      console.error("Poll error:", err);
    }

    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
}
