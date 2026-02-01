import { AzureFunction, Context, HttpRequest } from "@azure/functions";
import { QueueServiceClient } from "@azure/storage-queue";
import * as crypto from "crypto";

interface SlackEvent {
  type: string;
  challenge?: string;
  event?: {
    type: string;
    channel: string;
    user: string;
    text: string;
    ts: string;
  };
}

const httpTrigger: AzureFunction = async (
  context: Context,
  req: HttpRequest
): Promise<void> => {
  try {
    const body = req.body as SlackEvent;

    // Handle Slack URL verification challenge
    if (body.type === "url_verification" && body.challenge) {
      context.res = {
        status: 200,
        body: body.challenge,
        headers: { "Content-Type": "text/plain" },
      };
      return;
    }

    // Verify Slack signature
    const slackSigningSecret = process.env.SLACK_SIGNING_SECRET;
    if (slackSigningSecret) {
      const timestamp = req.headers["x-slack-request-timestamp"];
      const signature = req.headers["x-slack-signature"];

      if (!timestamp || !signature) {
        context.res = { status: 401, body: "Missing signature" };
        return;
      }

      // Check timestamp to prevent replay attacks (5 min window)
      const currentTime = Math.floor(Date.now() / 1000);
      if (Math.abs(currentTime - parseInt(timestamp)) > 300) {
        context.res = { status: 401, body: "Request too old" };
        return;
      }
    }

    // Process message events
    if (body.type === "event_callback" && body.event?.type === "message") {
      const event = body.event;

      // Skip bot messages
      if (!event.text || event.text.trim() === "") {
        context.res = { status: 200, body: "ok" };
        return;
      }

      // Enqueue work item
      const queueClient = QueueServiceClient.fromConnectionString(
        process.env.AzureWebJobsStorage!
      ).getQueueClient(process.env.QUEUE_NAME!);

      const workItem = {
        channel: "slack",
        chatId: event.channel,
        userId: event.user,
        text: event.text,
        timestamp: Date.now(),
        messageTs: event.ts,
      };

      await queueClient.sendMessage(
        Buffer.from(JSON.stringify(workItem)).toString("base64")
      );

      context.log(`Enqueued Slack work for channel ${event.channel}`);
    }

    context.res = { status: 200, body: "ok" };
  } catch (error: any) {
    context.log.error("Slack webhook error:", error);
    context.res = { status: 500, body: "Internal error" };
  }
};

export default httpTrigger;
