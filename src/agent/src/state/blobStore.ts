import { BlobServiceClient } from "@azure/storage-blob";
import { DefaultAzureCredential } from "@azure/identity";

let blobClient: BlobServiceClient | null = null;

function getClient(): BlobServiceClient {
  if (!blobClient) {
    const accountName = process.env.STORAGE_ACCOUNT_NAME!;
    const credential = new DefaultAzureCredential();
    blobClient = new BlobServiceClient(
      `https://${accountName}.blob.core.windows.net`,
      credential
    );
  }
  return blobClient;
}

export async function saveSession(
  userId: string,
  data: Record<string, unknown>
): Promise<void> {
  const container = getClient().getContainerClient("molten-configs");
  const blob = container.getBlockBlobClient(`sessions/${userId}.json`);
  await blob.upload(JSON.stringify(data), JSON.stringify(data).length, {
    blobHTTPHeaders: { blobContentType: "application/json" },
  });
}

export async function loadSession(
  userId: string
): Promise<Record<string, unknown> | null> {
  try {
    const container = getClient().getContainerClient("molten-configs");
    const blob = container.getBlockBlobClient(`sessions/${userId}.json`);
    const response = await blob.download();
    const text = await streamToString(response.readableStreamBody!);
    return JSON.parse(text);
  } catch {
    return null;
  }
}

async function streamToString(stream: NodeJS.ReadableStream): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}
