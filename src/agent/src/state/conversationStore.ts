import { TableClient, AzureNamedKeyCredential } from "@azure/data-tables";
import { DefaultAzureCredential } from "@azure/identity";

interface ConversationRow {
  partitionKey: string;
  rowKey: string;
  role: string;
  content: string;
  timestamp: number;
}

const TABLE_NAME = "conversations";
const MAX_HISTORY = 20;
const TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

let tableClient: TableClient | null = null;

function getTableClient(): TableClient {
  if (tableClient) return tableClient;

  const storageAccountName = process.env.STORAGE_ACCOUNT_NAME;
  if (!storageAccountName) {
    throw new Error("STORAGE_ACCOUNT_NAME not set");
  }

  const url = `https://${storageAccountName}.table.core.windows.net`;
  tableClient = new TableClient(url, TABLE_NAME, new DefaultAzureCredential());
  return tableClient;
}

/**
 * Load recent conversation history for a session.
 * Returns last MAX_HISTORY messages as ChatMessage-compatible objects.
 */
export async function loadConversation(
  sessionId: string
): Promise<Array<{ role: "user" | "assistant"; content: string }>> {
  try {
    const client = getTableClient();
    const cutoff = Date.now() - TTL_MS;
    const rows: ConversationRow[] = [];

    const entities = client.listEntities<ConversationRow>({
      queryOptions: {
        filter: `PartitionKey eq '${sessionId}' and timestamp gt ${cutoff}`,
      },
    });

    for await (const entity of entities) {
      rows.push(entity as ConversationRow);
    }

    // Sort by rowKey (timestamp-based) and take last N
    rows.sort((a, b) => a.rowKey.localeCompare(b.rowKey));
    const recent = rows.slice(-MAX_HISTORY);

    return recent.map((r) => ({
      role: r.role as "user" | "assistant",
      content: r.content,
    }));
  } catch (err) {
    console.warn("Failed to load conversation history:", err);
    return [];
  }
}

/**
 * Append a message to conversation history.
 */
export async function appendMessage(
  sessionId: string,
  role: string,
  content: string
): Promise<void> {
  try {
    const client = getTableClient();
    const now = Date.now();

    await client.createEntity({
      partitionKey: sessionId,
      rowKey: `${now}-${Math.random().toString(36).slice(2, 8)}`,
      role,
      content: content.slice(0, 4000), // Cap stored content
      timestamp: now,
    });
  } catch (err) {
    console.warn("Failed to append conversation message:", err);
  }
}
