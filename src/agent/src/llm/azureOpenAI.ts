import fetch from "node-fetch";
import { DefaultAzureCredential } from "@azure/identity";
import { SecretClient } from "@azure/keyvault-secrets";

export interface ChatMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_call_id?: string;
  tool_calls?: ToolCall[];
  name?: string;
}

export interface ToolCall {
  id: string;
  type: "function";
  function: {
    name: string;
    arguments: string;
  };
}

export interface ChatCompletionChoice {
  message: {
    role: string;
    content: string | null;
    tool_calls?: ToolCall[];
  };
  finish_reason: string;
}

interface ModelContext {
  userId?: string;
  username?: string;
}

interface TavilyResult {
  title: string;
  url: string;
  content: string;
}

// Cache for responses
const responseCache = new Map<string, { response: string; timestamp: number }>();
const CACHE_TTL_MS = 5 * 60 * 1000;

// Cache for secrets and token
let cachedEndpoint: string | null = null;
let cachedTavilyKey: string | null = null;
let cachedToken: { token: string; expiresOn: number } | null = null;
const credential = new DefaultAzureCredential();

async function getEndpoint(): Promise<string> {
  if (cachedEndpoint) return cachedEndpoint;

  const keyVaultUri = process.env.KEY_VAULT_URI;
  
  if (!keyVaultUri) {
    cachedEndpoint = process.env.AZURE_OPENAI_ENDPOINT || "";
    return cachedEndpoint;
  }

  console.log("Fetching endpoint from Key Vault...");
  const client = new SecretClient(keyVaultUri, credential);
  const endpointSecret = await client.getSecret("azure-openai-endpoint");
  cachedEndpoint = endpointSecret.value || "";
  console.log("Endpoint loaded from Key Vault");
  return cachedEndpoint;
}

async function getTavilyKey(): Promise<string | null> {
  if (cachedTavilyKey) return cachedTavilyKey;

  // Try env var first
  if (process.env.TAVILY_API_KEY) {
    cachedTavilyKey = process.env.TAVILY_API_KEY;
    return cachedTavilyKey;
  }

  // Try Key Vault
  const keyVaultUri = process.env.KEY_VAULT_URI;
  if (keyVaultUri) {
    try {
      const client = new SecretClient(keyVaultUri, credential);
      const secret = await client.getSecret("tavily-api-key");
      cachedTavilyKey = secret.value || null;
      console.log("Tavily API key loaded from Key Vault");
      return cachedTavilyKey;
    } catch (err) {
      console.warn("Tavily API key not found in Key Vault");
    }
  }

  return null;
}

async function getAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresOn > Date.now() + 300000) {
    return cachedToken.token;
  }

  console.log("Getting Azure OpenAI access token via Managed Identity...");
  const tokenResponse = await credential.getToken("https://cognitiveservices.azure.com/.default");
  
  cachedToken = {
    token: tokenResponse.token,
    expiresOn: tokenResponse.expiresOnTimestamp,
  };
  
  console.log("Access token obtained");
  return cachedToken.token;
}

// Detect if query needs web search
function needsWebSearch(query: string): boolean {
  const searchTriggers = [
    /what is the latest/i,
    /current news/i,
    /recent/i,
    /today/i,
    /2024|2025|2026/i,
    /search for/i,
    /look up/i,
    /find out/i,
    /who is/i,
    /what happened/i,
    /price of/i,
    /weather/i,
    /stock/i,
    /score/i,
  ];
  return searchTriggers.some((pattern) => pattern.test(query));
}

// Search the web using Tavily
async function searchWeb(query: string): Promise<TavilyResult[]> {
  const apiKey = await getTavilyKey();
  if (!apiKey) {
    console.log("Tavily API key not configured, skipping search");
    return [];
  }

  console.log(`Searching web for: ${query}`);
  
  try {
    const response = await fetch("https://api.tavily.com/search", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        api_key: apiKey,
        query,
        search_depth: "basic",
        max_results: 5,
        include_answer: false,
        include_raw_content: false,
      }),
    });

    if (!response.ok) {
      console.error(`Tavily search failed: ${response.status}`);
      return [];
    }

    const data = (await response.json()) as any;
    console.log(`Found ${data.results?.length || 0} search results`);
    
    return (data.results || []).map((r: any) => ({
      title: r.title,
      url: r.url,
      content: r.content,
    }));
  } catch (err) {
    console.error("Tavily search error:", err);
    return [];
  }
}

export const SYSTEM_PROMPT = `You are Molten, a personal AI assistant built on Azure.

ABOUT YOU:
- You are Molten, created as an Azure-based personal AI agent
- You help with tasks, answer questions, and assist users via Telegram, Slack, and Discord
- You were forged from Cloudflare's Moltworker project but run on Azure infrastructure
- You have access to tools for web search, file editing, command execution, email, and calendar management

TOOL USAGE:
- Use web_search to find current information, news, or facts you are unsure about
- Use bash to run shell commands when computation or system interaction is needed
- Use text_editor to create or modify files
- Use calendar_create and email_send for productivity tasks when asked
- Always explain what you did when using tools

SAFETY RULES:
- Never execute harmful or destructive commands
- Never share sensitive information or credentials
- Be concise but friendly
- When using search results, cite your sources`;

export async function callModel(
  userText: string,
  context: ModelContext = {}
): Promise<string> {
  const endpoint = await getEndpoint();
  const accessToken = await getAccessToken();
  const deployment = process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini";

  if (!endpoint) {
    throw new Error("Azure OpenAI endpoint not configured");
  }

  // Check cache
  const cacheKey = hashString(userText.toLowerCase().trim());
  const cached = responseCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
    console.log("Cache hit");
    return cached.response;
  }

  // Search web if query needs it
  let searchContext = "";
  if (needsWebSearch(userText)) {
    const results = await searchWeb(userText);
    if (results.length > 0) {
      searchContext = "\n\nWEB SEARCH RESULTS:\n" + results
        .map((r, i) => `[${i + 1}] ${r.title}\n${r.content}\nSource: ${r.url}`)
        .join("\n\n");
    }
  }

  const messages: ChatMessage[] = [
    { role: "system", content: SYSTEM_PROMPT + searchContext },
    { role: "user", content: userText },
  ];

  const body = {
    messages,
    max_tokens: 512, // Increased for search-based responses
    temperature: 0.3,
  };

  const url = `${endpoint}openai/deployments/${deployment}/chat/completions?api-version=2024-10-01-preview`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${accessToken}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Azure OpenAI error: ${response.status} - ${error}`);
  }

  const data = (await response.json()) as any;
  const content = data?.choices?.[0]?.message?.content ?? "I couldn't generate a response.";

  responseCache.set(cacheKey, { response: content, timestamp: Date.now() });

  if (data.usage) {
    console.log(`Tokens: prompt=${data.usage.prompt_tokens}, completion=${data.usage.completion_tokens}`);
  }

  return content;
}

/**
 * Call Azure OpenAI with tool/function-calling support.
 * Returns the full choice object so the caller can inspect tool_calls.
 * Includes retry with backoff for 429 rate-limit errors.
 */
const MAX_RETRIES = 3;

export async function callModelWithTools(
  messages: ChatMessage[],
  tools?: any[],
): Promise<ChatCompletionChoice> {
  const endpoint = await getEndpoint();
  const deployment = process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini";

  if (!endpoint) {
    throw new Error("Azure OpenAI endpoint not configured");
  }

  const body: Record<string, any> = {
    messages,
    max_tokens: 1024,
    temperature: 0.3,
  };

  if (tools && tools.length > 0) {
    body.tools = tools;
    body.tool_choice = "auto";
  }

  const url = `${endpoint}openai/deployments/${deployment}/chat/completions?api-version=2024-10-01-preview`;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    const accessToken = await getAccessToken();

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify(body),
    });

    if (response.status === 429 && attempt < MAX_RETRIES) {
      // Parse retry-after header or use exponential backoff
      const retryAfter = response.headers.get("retry-after");
      const waitSec = retryAfter ? Math.min(parseInt(retryAfter, 10), 60) : Math.pow(2, attempt + 1) * 5;
      console.warn(`Rate limited (429), retrying in ${waitSec}s (attempt ${attempt + 1}/${MAX_RETRIES})`);
      await new Promise((r) => setTimeout(r, waitSec * 1000));
      continue;
    }

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Azure OpenAI error: ${response.status} - ${error}`);
    }

    const data = (await response.json()) as any;

    if (data.usage) {
      console.log(`Tokens: prompt=${data.usage.prompt_tokens}, completion=${data.usage.completion_tokens}`);
    }

    return data.choices[0];
  }

  throw new Error("Azure OpenAI: max retries exceeded for rate limiting");
}

function hashString(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = (hash << 5) - hash + str.charCodeAt(i);
    hash = hash & hash;
  }
  return hash.toString(36);
}