import { DefaultAzureCredential } from "@azure/identity";
import { SecretClient } from "@azure/keyvault-secrets";
import { spawn } from "child_process";
import { CosmosClient } from "@azure/cosmos";
import fetch from "node-fetch";
import * as crypto from "crypto";

/**
 * Anthropic Computer Use Skills for Molten Agent
 * 
 * Free, open-source skills framework using Anthropic's Computer Use
 * No external API costs - all skills run locally in your Azure infrastructure
 * 
 * Skills Available:
 * - bash: Execute shell commands in sandboxed environment
 * - text_editor: Create/edit/delete files
 * - web_search: Search the web using Tavily (existing integration)
 * - microsoft_graph: Calendar, Email, Teams via Microsoft Graph API
 */

export interface Skill {
  id: string;
  name: string;
  description: string;
  parameters: Record<string, any>;
  category: "anthropic" | "azure" | "custom";
  cost: number; // Cost per execution in USD (0 for free skills)
  execute?: (params: any) => Promise<SkillResult>;
}

export interface SkillExecution {
  skillId: string;
  parameters: Record<string, any>;
  userId?: string;
  context?: Record<string, any>;
}

export interface SkillResult {
  success: boolean;
  data?: any;
  error?: string;
  duration?: number;
}

export class SkillsRegistry {
  private skills: Map<string, Skill> = new Map();
  private credential = new DefaultAzureCredential();
  private keyVaultUri: string;
  private cosmosClient?: CosmosClient;
  private pythonPath: string;
  private cachedTavilyKey: string | null = null;
  private cachedGraphToken: { token: string; expiresOn: number } | null = null;

  constructor(config: { keyVaultUri: string; cosmosEndpoint?: string }) {
    this.keyVaultUri = config.keyVaultUri;
    this.pythonPath = process.env.PYTHON_PATH || "python3";
    
    if (config.cosmosEndpoint) {
      this.cosmosClient = new CosmosClient({
        endpoint: config.cosmosEndpoint,
        aadCredentials: this.credential,
      });
    }
  }

  /**
   * Initialize the skills registry
   * Loads free, open-source skills only (no paid APIs)
   */
  async initialize(): Promise<void> {
    // Load all free skills
    this.loadAnthropicSkills();
    this.loadAzureNativeSkills();
    this.loadCustomSkills();

    console.log(`✅ Loaded ${this.skills.size} FREE skills`);
    console.log(`   Anthropic: ${this.getSkillsByCategory("anthropic").length}`);
    console.log(`   Azure: ${this.getSkillsByCategory("azure").length}`);
    console.log(`   Custom: ${this.getSkillsByCategory("custom").length}`);
  }

  /**
   * Load Anthropic Computer Use skills (FREE - runs locally via Python subprocess)
   */
  private loadAnthropicSkills(): void {
    const anthropicSkills: Skill[] = [
      {
        id: "bash",
        name: "Execute Bash Command",
        description: "Run shell commands in a sandboxed environment with timeout protection",
        category: "anthropic",
        cost: 0,
        parameters: {
          command: { type: "string", description: "Shell command to execute" },
          timeout: { type: "number", description: "Timeout in seconds", default: 30 },
          workdir: { type: "string", description: "Working directory", default: "/tmp" },
        },
      },
      {
        id: "text_editor",
        name: "Text Editor",
        description: "Create, view, edit, or delete files with line-based operations",
        category: "anthropic",
        cost: 0,
        parameters: {
          command: { 
            type: "string", 
            enum: ["create", "view", "insert", "replace", "delete"],
            description: "Editor operation" 
          },
          path: { type: "string", description: "File path" },
          content: { type: "string", description: "Content to write/insert", optional: true },
          line_number: { type: "number", description: "Line number for insert/replace", optional: true },
        },
      },
    ];

    for (const skill of anthropicSkills) {
      this.skills.set(skill.id, skill);
    }
  }

  /**
   * Load Azure-native skills (FREE - uses existing Azure services)
   */
  private loadAzureNativeSkills(): void {
    const azureSkills: Skill[] = [
      {
        id: "web-search",
        name: "Web Search",
        description: "Search the web using Tavily API (already integrated)",
        category: "azure",
        cost: 0.01, // ~$0.01 per search
        parameters: {
          query: { type: "string", description: "Search query" },
          max_results: { type: "number", description: "Maximum results", default: 5 },
        },
        execute: async (params) => await this.executeWebSearch(params),
      },
      {
        id: "calendar-create",
        name: "Create Calendar Event",
        description: "Create calendar event via Microsoft Graph API",
        category: "azure",
        cost: 0, // FREE (included with Entra ID)
        parameters: {
          title: { type: "string", description: "Event title" },
          start: { type: "string", description: "Start datetime (ISO 8601)" },
          end: { type: "string", description: "End datetime (ISO 8601)" },
          attendees: { type: "array", items: { type: "string" }, description: "Attendee emails", optional: true },
        },
        execute: async (params) => await this.executeCalendarCreate(params),
      },
      {
        id: "email-send",
        name: "Send Email",
        description: "Send email via Microsoft Graph API",
        category: "azure",
        cost: 0, // FREE
        parameters: {
          to: { type: "string", description: "Recipient email" },
          subject: { type: "string", description: "Email subject" },
          body: { type: "string", description: "Email body (HTML or plain text)" },
        },
        execute: async (params) => await this.executeEmailSend(params),
      },
    ];

    for (const skill of azureSkills) {
      this.skills.set(skill.id, skill);
    }
  }

  /**
   * Load custom skills (extensible)
   */
  private loadCustomSkills(): void {
    // Users can add their own custom skills here
    // Example: GitHub, Azure DevOps, Slack, etc.
  }

  /**
   * Get skills by category
   */
  private getSkillsByCategory(category: string): Skill[] {
    return Array.from(this.skills.values()).filter((s) => s.category === category);
  }

  /**
   * Get all available skills
   */
  getAvailableSkills(): Skill[] {
    return Array.from(this.skills.values());
  }

  /**
   * Get a specific skill by ID
   */
  getSkill(skillId: string): Skill | undefined {
    return this.skills.get(skillId);
  }

  /**
   * Execute a skill with logging to Cosmos DB
   */
  async executeSkill(execution: SkillExecution): Promise<SkillResult> {
    const skill = this.skills.get(execution.skillId);
    
    if (!skill) {
      return {
        success: false,
        error: `Skill not found: ${execution.skillId}`,
      };
    }

    console.log(`🔥 Executing skill: ${skill.name} (category: ${skill.category})`);
    const startTime = Date.now();

    try {
      let result: SkillResult;

      // Route to appropriate executor
      if (skill.category === "anthropic") {
        result = await this.executeAnthropicSkill(execution.skillId, execution.parameters);
      } else if (skill.execute) {
        result = await skill.execute(execution.parameters);
      } else {
        result = {
          success: false,
          error: "Skill has no execute function defined",
        };
      }

      result.duration = Date.now() - startTime;

      // Log to Cosmos DB (if configured)
      if (this.cosmosClient && execution.userId) {
        await this.logSkillExecution(execution, skill, result);
      }

      console.log(`✅ Skill completed: ${skill.name} (${result.duration}ms)`);
      return result;
    } catch (err: any) {
      const result = {
        success: false,
        error: err.message,
        duration: Date.now() - startTime,
      };

      console.error(`❌ Skill failed: ${skill.name} - ${err.message}`);
      return result;
    }
  }

  /**
   * Execute Anthropic Computer Use skill via Python subprocess
   */
  private async executeAnthropicSkill(
    skillId: string,
    parameters: Record<string, any>
  ): Promise<SkillResult> {
    return new Promise((resolve, reject) => {
      // Construct Python command
      const pythonScript = `${__dirname}/anthropic_executor.py`;
      const pythonArgs = [
        pythonScript,
        "--skill", skillId,
        "--params", JSON.stringify(parameters),
      ];

      const pythonProcess = spawn(this.pythonPath, pythonArgs, {
        env: {
          ...process.env,
          PYTHONPATH: __dirname,
        },
      });

      let stdout = "";
      let stderr = "";

      pythonProcess.stdout.on("data", (data) => {
        stdout += data.toString();
      });

      pythonProcess.stderr.on("data", (data) => {
        stderr += data.toString();
      });

      pythonProcess.on("close", (code) => {
        if (code !== 0) {
          resolve({
            success: false,
            error: stderr || `Python process exited with code ${code}`,
          });
        } else {
          try {
            const result = JSON.parse(stdout);
            resolve({
              success: true,
              data: result,
            });
          } catch (err) {
            resolve({
              success: false,
              error: `Failed to parse Python output: ${err}`,
            });
          }
        }
      });

      pythonProcess.on("error", (err) => {
        reject(err);
      });

      // Timeout protection (30 seconds default)
      const timeout = parameters.timeout || 30;
      setTimeout(() => {
        pythonProcess.kill();
        resolve({
          success: false,
          error: `Skill execution timeout after ${timeout} seconds`,
        });
      }, timeout * 1000);
    });
  }

  /**
   * Log skill execution to Cosmos DB for analytics
   */
  private async logSkillExecution(
    execution: SkillExecution,
    skill: Skill,
    result: SkillResult
  ): Promise<void> {
    if (!this.cosmosClient) return;

    try {
      const container = this.cosmosClient
        .database("molten")
        .container("skill-executions");

      await container.items.create({
        id: crypto.randomUUID(),
        userId: execution.userId, // Partition key for user isolation
        skillId: execution.skillId,
        skillName: skill.name,
        skillCategory: skill.category,
        skillCost: skill.cost,
        parameters: execution.parameters,
        success: result.success,
        error: result.error,
        duration: result.duration,
        timestamp: new Date().toISOString(),
      });
    } catch (err) {
      console.error("Failed to log to Cosmos DB:", err);
      // Don't fail the skill execution if logging fails
    }
  }

  /**
   * Get Tavily API key from env var or Key Vault
   */
  private async getTavilyApiKey(): Promise<string | null> {
    if (this.cachedTavilyKey) return this.cachedTavilyKey;

    if (process.env.TAVILY_API_KEY) {
      this.cachedTavilyKey = process.env.TAVILY_API_KEY;
      return this.cachedTavilyKey;
    }

    if (this.keyVaultUri) {
      try {
        const client = new SecretClient(this.keyVaultUri, this.credential);
        const secret = await client.getSecret("tavily-api-key");
        this.cachedTavilyKey = secret.value || null;
        console.log("Tavily API key loaded from Key Vault");
        return this.cachedTavilyKey;
      } catch (err) {
        console.warn("Tavily API key not found in Key Vault");
      }
    }

    return null;
  }

  /**
   * Get Microsoft Graph access token via Managed Identity
   */
  private async getGraphAccessToken(): Promise<string> {
    if (this.cachedGraphToken && this.cachedGraphToken.expiresOn > Date.now() + 300000) {
      return this.cachedGraphToken.token;
    }

    console.log("Getting Microsoft Graph access token...");
    const tokenResponse = await this.credential.getToken("https://graph.microsoft.com/.default");

    this.cachedGraphToken = {
      token: tokenResponse.token,
      expiresOn: tokenResponse.expiresOnTimestamp,
    };

    return this.cachedGraphToken.token;
  }

  /**
   * Web search using Tavily API
   */
  private async executeWebSearch(params: { query: string; max_results?: number }): Promise<SkillResult> {
    const apiKey = await this.getTavilyApiKey();
    if (!apiKey) {
      return {
        success: false,
        error: "Tavily API key not configured. Set TAVILY_API_KEY env var or add tavily-api-key to Key Vault.",
      };
    }

    console.log(`Web search: ${params.query}`);

    try {
      const response = await fetch("https://api.tavily.com/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          api_key: apiKey,
          query: params.query,
          search_depth: "basic",
          max_results: params.max_results || 5,
          include_answer: false,
          include_raw_content: false,
        }),
      });

      if (!response.ok) {
        return {
          success: false,
          error: `Tavily search failed: ${response.status} ${response.statusText}`,
        };
      }

      const data = (await response.json()) as any;
      const results = (data.results || []).map((r: any) => ({
        title: r.title,
        url: r.url,
        content: r.content,
      }));

      console.log(`Found ${results.length} search results`);

      return {
        success: true,
        data: { results, query: params.query },
      };
    } catch (err: any) {
      return {
        success: false,
        error: `Web search error: ${err.message}`,
      };
    }
  }

  /**
   * Create calendar event via Microsoft Graph API
   */
  private async executeCalendarCreate(params: {
    title: string;
    start: string;
    end: string;
    attendees?: string[];
  }): Promise<SkillResult> {
    const senderEmail = process.env.GRAPH_SENDER_EMAIL;
    if (!senderEmail) {
      return {
        success: false,
        error: "GRAPH_SENDER_EMAIL not configured. Set the env var to the user mailbox to manage.",
      };
    }

    try {
      const accessToken = await this.getGraphAccessToken();

      const event: Record<string, any> = {
        subject: params.title,
        start: { dateTime: params.start, timeZone: "UTC" },
        end: { dateTime: params.end, timeZone: "UTC" },
      };

      if (params.attendees && params.attendees.length > 0) {
        event.attendees = params.attendees.map((email) => ({
          emailAddress: { address: email },
          type: "required",
        }));
      }

      const url = `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(senderEmail)}/events`;

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify(event),
      });

      if (!response.ok) {
        const error = await response.text();
        return {
          success: false,
          error: `Graph API error: ${response.status} - ${error}`,
        };
      }

      const created = (await response.json()) as any;
      console.log(`Calendar event created: ${created.id}`);

      return {
        success: true,
        data: {
          id: created.id,
          subject: created.subject,
          start: created.start,
          end: created.end,
          webLink: created.webLink,
        },
      };
    } catch (err: any) {
      return {
        success: false,
        error: `Calendar error: ${err.message}`,
      };
    }
  }

  /**
   * Send email via Microsoft Graph API
   */
  private async executeEmailSend(params: {
    to: string;
    subject: string;
    body: string;
  }): Promise<SkillResult> {
    const senderEmail = process.env.GRAPH_SENDER_EMAIL;
    if (!senderEmail) {
      return {
        success: false,
        error: "GRAPH_SENDER_EMAIL not configured. Set the env var to the sender mailbox.",
      };
    }

    try {
      const accessToken = await this.getGraphAccessToken();

      const mailBody = {
        message: {
          subject: params.subject,
          body: {
            contentType: params.body.includes("<") ? "HTML" : "Text",
            content: params.body,
          },
          toRecipients: [
            { emailAddress: { address: params.to } },
          ],
        },
        saveToSentItems: true,
      };

      const url = `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(senderEmail)}/sendMail`;

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify(mailBody),
      });

      if (!response.ok) {
        const error = await response.text();
        return {
          success: false,
          error: `Graph API error: ${response.status} - ${error}`,
        };
      }

      // sendMail returns 202 Accepted with no body
      console.log(`Email sent to ${params.to}`);

      return {
        success: true,
        data: {
          to: params.to,
          subject: params.subject,
          status: "sent",
        },
      };
    } catch (err: any) {
      return {
        success: false,
        error: `Email error: ${err.message}`,
      };
    }
  }

  /**
   * Format skills for OpenAI function calling
   */
  getSkillsForLLM(): any[] {
    return Array.from(this.skills.values()).map((skill) => ({
      type: "function",
      function: {
        name: skill.id.replace(/-/g, "_"),
        description: `${skill.description} (Cost: $${skill.cost}/execution, Category: ${skill.category})`,
        parameters: {
          type: "object",
          properties: this.convertParametersToJsonSchema(skill.parameters),
          required: this.getRequiredParameters(skill.parameters),
        },
      },
    }));
  }

  /**
   * Convert skill parameters to JSON Schema
   */
  private convertParametersToJsonSchema(parameters: Record<string, any>): Record<string, any> {
    const schema: Record<string, any> = {};

    for (const [key, paramDef] of Object.entries(parameters)) {
      if (typeof paramDef === "object" && paramDef.type) {
        schema[key] = {
          type: paramDef.type,
          description: paramDef.description,
          ...(paramDef.enum && { enum: paramDef.enum }),
          ...(paramDef.default !== undefined && { default: paramDef.default }),
          ...(paramDef.items && { items: paramDef.items }),
        };
      } else {
        // Legacy format: just type string
        schema[key] = { type: "string" };
      }
    }

    return schema;
  }

  /**
   * Get required parameters (those without defaults)
   */
  private getRequiredParameters(parameters: Record<string, any>): string[] {
    return Object.entries(parameters)
      .filter(([_, paramDef]) => {
        if (typeof paramDef === "object") {
          return paramDef.default === undefined && paramDef.optional !== true;
        }
        return true;
      })
      .map(([key, _]) => key);
  }
}

// Singleton instance
let skillsRegistry: SkillsRegistry | null = null;

/**
 * Get or create the skills registry singleton
 */
export async function getSkillsRegistry(): Promise<SkillsRegistry> {
  if (!skillsRegistry) {
    const keyVaultUri = process.env.KEY_VAULT_URI || "";
    const cosmosEndpoint = process.env.COSMOS_ENDPOINT;

    skillsRegistry = new SkillsRegistry({
      keyVaultUri,
      cosmosEndpoint,
    });

    await skillsRegistry.initialize();
  }

  return skillsRegistry;
}

