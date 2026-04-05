import { QueueClient } from "@azure/storage-queue";
import { DefaultAzureCredential } from "@azure/identity";
import { callModel, callModelWithTools, SYSTEM_PROMPT, ChatMessage } from "./llm/azureOpenAI";
import { sendTelegramMessage } from "./integrations/telegram";
import { sendSlackMessage } from "./integrations/slack";
import { sendDiscordMessage } from "./integrations/discord";
import { sendWhatsAppMessage } from "./integrations/whatsapp";
import { checkSafety } from "./llm/safety";
import { initOpenClaw, getOpenClawClient, OpenClawGatewayClient } from "./openclaw";
import { getSkillsRegistry, SkillsRegistry } from "./skills/skillsRegistry";
import { loadConversation, appendMessage } from "./state/conversationStore";
import { setReady } from "./index";

interface WorkItem {
  channel: "telegram" | "slack" | "discord" | "whatsapp";
  chatId: number | string;
  userId?: number | string;
  username?: string;
  text: string;
  timestamp: number;
}

const MAX_TOOL_ROUNDS = 5;
const MAX_DEQUEUE_COUNT = 3;

// Exponential backoff: 2s → 4s → 8s → 16s → 30s (cap)
const POLL_MIN_MS = 2000;
const POLL_MAX_MS = 30000;
let currentPollInterval = POLL_MIN_MS;

// Graceful shutdown
let shuttingDown = false;

// OpenClaw client instance (initialized once)
let openClawClient: OpenClawGatewayClient | null = null;

// Skills registry instance (initialized once)
let skillsRegistry: SkillsRegistry | null = null;

/**
 * Process a message through OpenClaw Gateway or Azure OpenAI with function-calling
 */
async function processMessage(item: WorkItem): Promise<string> {
  const sessionId = `${item.channel}-${item.chatId}`;

  // Try OpenClaw first if enabled and connected
  if (openClawClient?.isConnected()) {
    try {
      console.log(`Routing to OpenClaw Gateway for ${sessionId}`);
      
      const response = await openClawClient.sendAgentMessage(item.text, {
        channel: item.channel,
        userId: String(item.userId || item.chatId),
        sessionId,
      });

      if (response.status === "completed" && response.message) {
        console.log(`OpenClaw response: ${response.usage?.totalTokens || 0} tokens`);
        return response.message;
      }
      
      console.warn("OpenClaw returned no message, falling back to Azure OpenAI");
    } catch (err) {
      console.error("OpenClaw error, falling back to Azure OpenAI:", err);
    }
  }

  // Azure OpenAI with function-calling loop
  console.log(`Using Azure OpenAI with skills for ${sessionId}`);

  // Get skills as OpenAI tool definitions
  const registry = skillsRegistry || await getSkillsRegistry();
  const tools = registry.getSkillsForLLM();

  // Load conversation history from Table Storage
  const history = await loadConversation(sessionId);

  const messages: ChatMessage[] = [
    { role: "system" as const, content: SYSTEM_PROMPT },
    ...history,
    { role: "user" as const, content: item.text },
  ];

  // Persist user message
  await appendMessage(sessionId, "user", item.text);

  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const choice = await callModelWithTools(messages, tools);

    if (choice.message.tool_calls && choice.message.tool_calls.length > 0) {
      // Add the assistant's tool_calls message to the conversation
      messages.push({
        role: "assistant",
        content: choice.message.content,
        tool_calls: choice.message.tool_calls,
      });

      // Execute each requested tool
      for (const toolCall of choice.message.tool_calls) {
        let args: Record<string, any>;
        try {
          args = JSON.parse(toolCall.function.arguments);
        } catch {
          args = {};
        }

        // Convert function name back to skill ID (web_search → web-search)
        const skillId = toolCall.function.name.replace(/_/g, "-");
        console.log(`Tool call [${round + 1}/${MAX_TOOL_ROUNDS}]: ${skillId} args=${JSON.stringify(args)}`);

        const result = await registry.executeSkill({
          skillId,
          parameters: args,
          userId: String(item.userId || item.chatId),
        });

        // Feed tool result back to the conversation
        messages.push({
          role: "tool",
          content: JSON.stringify(result.success ? result.data : { error: result.error }),
          tool_call_id: toolCall.id,
        });
      }
    } else {
      // Final text response — no more tool calls
      const reply = choice.message.content || "I couldn't generate a response.";
      await appendMessage(sessionId, "assistant", reply);
      return reply;
    }
  }

  // Hit max rounds — get a final text response without tools
  console.warn(`Reached max tool rounds (${MAX_TOOL_ROUNDS}), forcing final response`);
  const finalChoice = await callModelWithTools(messages);
  const finalReply = finalChoice.message.content || "I couldn't generate a response.";
  await appendMessage(sessionId, "assistant", finalReply);
  return finalReply;
}

/**
 * Send response back to the appropriate channel
 */
async function sendResponse(item: WorkItem, response: string): Promise<void> {
  switch (item.channel) {
    case "telegram":
      await sendTelegramMessage(item.chatId as number, response);
      break;
    case "slack":
      await sendSlackMessage(item.chatId as string, response);
      break;
    case "discord":
      await sendDiscordMessage(item.chatId as string, response);
      break;
    case "whatsapp":
      await sendWhatsAppMessage(item.chatId as string, response);
      break;
    default:
      console.warn(`Unknown channel: ${item.channel}`);
  }
}

export async function consumeQueue(): Promise<void> {
  const storageAccountName = process.env.STORAGE_ACCOUNT_NAME;
  const queueName = process.env.QUEUE_NAME || "molten-work";

  if (!storageAccountName) {
    console.warn("STORAGE_ACCOUNT_NAME not set");
    return;
  }

  // Initialize OpenClaw if enabled
  try {
    openClawClient = await initOpenClaw();
    if (openClawClient) {
      console.log("OpenClaw Gateway integration enabled");
    }
  } catch (err) {
    console.warn("OpenClaw initialization failed, using Azure OpenAI only:", err);
  }

  // Initialize Skills Registry
  try {
    skillsRegistry = await getSkillsRegistry();
    console.log("Skills registry initialized");
  } catch (err) {
    console.warn("Skills registry initialization failed:", err);
  }

  // Mark the agent as ready for traffic
  setReady();

  const credential = new DefaultAzureCredential();
  const queueUrl = `https://${storageAccountName}.queue.core.windows.net/${queueName}`;
  const poisonQueueUrl = `https://${storageAccountName}.queue.core.windows.net/${queueName}-poison`;
  const queueClient = new QueueClient(queueUrl, credential);
  const poisonQueueClient = new QueueClient(poisonQueueUrl, credential);

  // Graceful shutdown handlers
  const shutdown = () => {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log("Received shutdown signal, draining current message...");
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);

  console.log(`Queue worker started, polling ${queueName}`);

  while (!shuttingDown) {
    try {
      const messages = await queueClient.receiveMessages({
        numberOfMessages: 16,
        visibilityTimeout: 30,
      });

      if (messages.receivedMessageItems.length > 0) {
        // Reset backoff when messages found
        currentPollInterval = POLL_MIN_MS;
      } else {
        // Exponential backoff when idle
        currentPollInterval = Math.min(currentPollInterval * 2, POLL_MAX_MS);
      }

      for (const message of messages.receivedMessageItems) {
        if (shuttingDown) break;

        let item: WorkItem | null = null;
        try {
          // Dead-letter after MAX_DEQUEUE_COUNT attempts
          if (message.dequeueCount > MAX_DEQUEUE_COUNT) {
            console.warn(`Message ${message.messageId} exceeded ${MAX_DEQUEUE_COUNT} retries, moving to poison queue`);
            await poisonQueueClient.sendMessage(message.messageText);
            await queueClient.deleteMessage(message.messageId, message.popReceipt);
            continue;
          }

          const payload = Buffer.from(message.messageText, "base64").toString("utf8");
          item = JSON.parse(payload);

          console.log(`Processing ${item!.channel} message from ${item!.chatId} (attempt ${message.dequeueCount})`);

          // Safety check (always applied, regardless of backend)
          const safetyResult = await checkSafety(item!.text);
          if (!safetyResult.safe) {
            console.warn(`Blocked: ${safetyResult.reason}`);
            await queueClient.deleteMessage(message.messageId, message.popReceipt);
            continue;
          }

          // Process through OpenClaw or Azure OpenAI
          const response = await processMessage(item!);

          // Send response back to channel
          await sendResponse(item!, response);

          // Only delete on success
          await queueClient.deleteMessage(message.messageId, message.popReceipt);
        } catch (err: any) {
          console.error(`Error processing message ${message.messageId}:`, err);
          // Send error reply so user knows something went wrong
          if (item) {
            try {
              await sendResponse(item, "Sorry, I encountered an error processing your message. Please try again.");
            } catch (sendErr) {
              console.error("Failed to send error reply:", sendErr);
            }
          }
          // Do NOT delete — let visibility timeout expire for automatic retry
        }
      }
    } catch (err) {
      console.error("Poll error:", err);
    }

    await new Promise((r) => setTimeout(r, currentPollInterval));
  }

  console.log("Queue worker shut down gracefully");
  process.exit(0);
}
