export interface WorkItem {
  channel: "telegram" | "slack" | "discord";
  chatId: number | string;
  userId?: number | string;
  username?: string;
  text: string;
  timestamp: number;
  messageTs?: string;
  messageDate?: number;
}

export interface LLMResponse {
  content: string;
  promptTokens: number;
  completionTokens: number;
  cached: boolean;
}

export interface SafetyResult {
  safe: boolean;
  reason?: string;
  category?: string;
}

export interface ConversationContext {
  userId: string;
  conversationId: string;
  messages: Array<{
    role: "user" | "assistant";
    content: string;
    timestamp: number;
  }>;
}

export interface IntegrationConfig {
  enabled: boolean;
  token?: string;
  webhookUrl?: string;
}

export interface AppConfig {
  azureOpenAI: {
    endpoint: string;
    deployment: string;
    maxTokens: number;
  };
  storage: {
    accountName: string;
    queueName: string;
  };
  integrations: {
    telegram: IntegrationConfig;
    slack: IntegrationConfig;
    discord: IntegrationConfig;
  };
}
