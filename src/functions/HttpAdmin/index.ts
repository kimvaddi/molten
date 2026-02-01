import { AzureFunction, Context, HttpRequest } from "@azure/functions";
import { BlobServiceClient } from "@azure/storage-blob";

const httpTrigger: AzureFunction = async (
  context: Context,
  req: HttpRequest
): Promise<void> => {
  const action = context.bindingData.action || "status";

  try {
    switch (action) {
      case "status":
        context.res = {
          status: 200,
          body: {
            status: "healthy",
            version: "1.0.0",
            timestamp: new Date().toISOString(),
          },
          headers: { "Content-Type": "application/json" },
        };
        break;

      case "config":
        if (req.method === "GET") {
          // Return current config (sanitized)
          context.res = {
            status: 200,
            body: {
              model: process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini",
              maxTokens: 256,
              cacheEnabled: true,
              integrations: {
                telegram: !!process.env.TELEGRAM_BOT_TOKEN,
                slack: !!process.env.SLACK_BOT_TOKEN,
                discord: !!process.env.DISCORD_BOT_TOKEN,
              },
            },
            headers: { "Content-Type": "application/json" },
          };
        } else {
          context.res = { status: 405, body: "Method not allowed" };
        }
        break;

      case "health":
        // Deep health check
        const checks: Record<string, boolean> = {};

        // Check storage connection
        try {
          const blobService = BlobServiceClient.fromConnectionString(
            process.env.AzureWebJobsStorage!
          );
          await blobService.getProperties();
          checks.storage = true;
        } catch {
          checks.storage = false;
        }

        const allHealthy = Object.values(checks).every((v) => v);

        context.res = {
          status: allHealthy ? 200 : 503,
          body: { healthy: allHealthy, checks },
          headers: { "Content-Type": "application/json" },
        };
        break;

      default:
        context.res = { status: 404, body: "Unknown action" };
    }
  } catch (error: any) {
    context.log.error("Admin API error:", error);
    context.res = {
      status: 500,
      body: { error: "Internal server error" },
      headers: { "Content-Type": "application/json" },
    };
  }
};

export default httpTrigger;
