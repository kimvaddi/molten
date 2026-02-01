import { AzureFunction, Context, HttpRequest } from "@azure/functions";
import { QueueServiceClient } from "@azure/storage-queue";

interface TelegramMessage {
  message?: {
    chat: { id: number };
    from?: { id: number; username?: string };
    text?: string;
    date: number;
  };
}

const httpTrigger: AzureFunction = async (
  context: Context,
  req: HttpRequest
): Promise<void> => {
  try {
    const body = req.body as TelegramMessage;

    // Validate request
    if (!body?.message?.chat?.id) {
      context.res = { status: 400, body: "Invalid request" };
      return;
    }

    const chatId = body.message.chat.id;
    const text = body.message.text ?? "";

    // Skip empty messages
    if (!text.trim()) {
      context.res = { status: 200, body: "ok" };
      return;
    }

    // Content safety: block obvious prompt injection attempts
    const blockedPatterns = [
      /ignore.*previous.*instructions/i,
      /system.*prompt/i,
      /jailbreak/i,
    ];

    if (blockedPatterns.some((p) => p.test(text))) {
      context.log.warn(`Blocked suspicious input from chat ${chatId}`);
      context.res = { status: 200, body: "ok" };
      return;
    }

    // Enqueue work item
    const queueClient = QueueServiceClient.fromConnectionString(
      process.env.AzureWebJobsStorage!
    ).getQueueClient(process.env.QUEUE_NAME!);

    const workItem = {
      channel: "telegram",
      chatId,
      userId: body.message.from?.id,
      username: body.message.from?.username,
      text,
      timestamp: Date.now(),
      messageDate: body.message.date,
    };

    await queueClient.sendMessage(
      Buffer.from(JSON.stringify(workItem)).toString("base64")
    );

    context.log(`Enqueued work for chat ${chatId}`);
    context.res = { status: 200, body: "ok" };
  } catch (error: any) {
    context.log.error("Webhook error:", error);
    context.res = { status: 500, body: "Internal error" };
  }
};

export default httpTrigger;
