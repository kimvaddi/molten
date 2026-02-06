import { SecretClient } from "@azure/keyvault-secrets";
import { DefaultAzureCredential } from "@azure/identity";

let secretClient: SecretClient | null = null;

function getSecretClient(): SecretClient {
  if (!secretClient) {
    const vaultUri = process.env.KEY_VAULT_URI!;
    secretClient = new SecretClient(vaultUri, new DefaultAzureCredential());
  }
  return secretClient;
}

export async function getSecret(name: string): Promise<string | undefined> {
  try {
    const secret = await getSecretClient().getSecret(name);
    return secret.value;
  } catch (error) {
    console.error(`Failed to get secret ${name}:`, error);
    return undefined;
  }
}

export const config = {
  azureOpenAI: {
    endpoint: process.env.AZURE_OPENAI_ENDPOINT || "",
    deployment: process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini",
    maxTokens: parseInt(process.env.MAX_TOKENS || "256", 10),
  },
  storage: {
    accountName: process.env.STORAGE_ACCOUNT_NAME || "",
    queueName: process.env.QUEUE_NAME || "molten-work",
  },
  integrations: {
    telegram: !!process.env.TELEGRAM_BOT_TOKEN,
    slack: !!process.env.SLACK_BOT_TOKEN,
    discord: !!process.env.DISCORD_BOT_TOKEN,
  },
};
