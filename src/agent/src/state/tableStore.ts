// Table storage for conversation metadata
// Using Azure Table Storage for lightweight key-value lookups

import { TableClient, AzureNamedKeyCredential } from "@azure/data-tables";
import { DefaultAzureCredential } from "@azure/identity";

let tableClient: TableClient | null = null;

function getClient(): TableClient {
  if (!tableClient) {
    const accountName = process.env.STORAGE_ACCOUNT_NAME!;
    const credential = new DefaultAzureCredential();
    tableClient = new TableClient(
      `https://${accountName}.table.core.windows.net`,
      "conversations",
      credential
    );
  }
  return tableClient;
}

export interface ConversationMeta {
  partitionKey: string; // userId
  rowKey: string; // conversationId
  startedAt: Date;
  lastMessageAt: Date;
  messageCount: number;
  channel: string;
}

export async function upsertConversation(
  meta: ConversationMeta
): Promise<void> {
  await getClient().upsertEntity(meta, "Merge");
}

export async function getConversation(
  userId: string,
  conversationId: string
): Promise<ConversationMeta | null> {
  try {
    const entity = await getClient().getEntity<ConversationMeta>(
      userId,
      conversationId
    );
    return entity;
  } catch {
    return null;
  }
}
