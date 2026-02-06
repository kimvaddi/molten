/**
 * OpenClaw Gateway WebSocket Client
 * Connects MoltBot to OpenClaw Gateway for skills and agent execution
 * 
 * Protocol: https://docs.openclaw.ai/concepts/architecture
 */

import WebSocket from "ws";
import { v4 as uuidv4 } from "uuid";
import {
  GatewayMessage,
  RequestMessage,
  ResponseMessage,
  EventMessage,
  ConnectParams,
  ConnectResponse,
  AgentRequest,
  AgentResponse,
  AgentStreamEvent,
  OpenClawConfig,
} from "./types";

type EventHandler = (event: EventMessage) => void;
type ResponseHandler = (response: ResponseMessage) => void;

export class OpenClawGatewayClient {
  private ws: WebSocket | null = null;
  private config: OpenClawConfig;
  private connected = false;
  private reconnecting = false;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 2000;

  private pendingRequests = new Map<string, ResponseHandler>();
  private eventHandlers = new Map<string, Set<EventHandler>>();

  constructor(config: OpenClawConfig) {
    this.config = config;
  }

  /**
   * Connect to OpenClaw Gateway
   */
  async connect(): Promise<void> {
    if (!this.config.enabled) {
      console.log("OpenClaw integration disabled");
      return;
    }

    const CONNECTION_TIMEOUT_MS = 10000; // 10 second timeout

    return new Promise((resolve, reject) => {
      let settled = false;

      const timeout = setTimeout(() => {
        if (!settled) {
          settled = true;
          console.warn(`OpenClaw Gateway connection timed out after ${CONNECTION_TIMEOUT_MS}ms`);
          if (this.ws) {
            this.ws.terminate();
            this.ws = null;
          }
          reject(new Error("OpenClaw connection timed out"));
        }
      }, CONNECTION_TIMEOUT_MS);

      try {
        console.log(`Connecting to OpenClaw Gateway at ${this.config.gatewayUrl}...`);
        
        this.ws = new WebSocket(this.config.gatewayUrl);

        this.ws.on("open", async () => {
          console.log("WebSocket connected, sending handshake...");
          try {
            await this.handshake();
            this.connected = true;
            this.reconnectAttempts = 0;
            console.log("OpenClaw Gateway connected successfully");
            if (!settled) {
              settled = true;
              clearTimeout(timeout);
              resolve();
            }
          } catch (err) {
            if (!settled) {
              settled = true;
              clearTimeout(timeout);
              reject(err);
            }
          }
        });

        this.ws.on("message", (data: WebSocket.Data) => {
          this.handleMessage(data.toString());
        });

        this.ws.on("close", (code, reason) => {
          console.log(`Gateway connection closed: ${code} - ${reason}`);
          this.connected = false;
          if (!settled) {
            settled = true;
            clearTimeout(timeout);
            reject(new Error(`Connection closed: ${code}`));
          } else {
            this.handleDisconnect();
          }
        });

        this.ws.on("error", (error) => {
          console.error("Gateway WebSocket error:", error);
          if (!settled) {
            settled = true;
            clearTimeout(timeout);
            reject(error);
          }
        });
      } catch (err) {
        if (!settled) {
          settled = true;
          clearTimeout(timeout);
          reject(err);
        }
      }
    });
  }

  /**
   * Disconnect from Gateway
   */
  disconnect(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.connected = false;
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.connected;
  }

  /**
   * Send agent request and get response
   */
  async sendAgentMessage(
    message: string,
    options: Partial<AgentRequest> = {}
  ): Promise<AgentResponse> {
    const request: AgentRequest = {
      message,
      idempotencyKey: uuidv4(),
      model: this.config.model,
      thinking: this.config.thinking,
      ...options,
    };

    const response = await this.sendRequest<AgentResponse>("agent", request as unknown as Record<string, unknown>);
    return response;
  }

  /**
   * Send agent request with streaming callback
   */
  async sendAgentMessageStreaming(
    message: string,
    onStream: (event: AgentStreamEvent) => void,
    options: Partial<AgentRequest> = {}
  ): Promise<AgentResponse> {
    const request: AgentRequest = {
      message,
      idempotencyKey: uuidv4(),
      model: this.config.model,
      thinking: this.config.thinking,
      ...options,
    };

    // Subscribe to agent events for this request
    const runId = uuidv4();
    const unsubscribe = this.on("agent", (event) => {
      const payload = event.payload as AgentStreamEvent;
      if (payload.runId === runId) {
        onStream(payload);
      }
    });

    try {
      const response = await this.sendRequest<AgentResponse>("agent", {
        ...request,
        runId,
      });
      return response;
    } finally {
      unsubscribe();
    }
  }

  /**
   * Get gateway health status
   */
  async getHealth(): Promise<{ status: string; version: string }> {
    return this.sendRequest("health", {});
  }

  /**
   * Get session status
   */
  async getStatus(sessionId?: string): Promise<unknown> {
    return this.sendRequest("status", { sessionId });
  }

  /**
   * Reset a session
   */
  async resetSession(sessionId: string): Promise<void> {
    await this.sendRequest("session.reset", { sessionId });
  }

  /**
   * Subscribe to Gateway events
   */
  on(event: string, handler: EventHandler): () => void {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event)!.add(handler);

    // Return unsubscribe function
    return () => {
      this.eventHandlers.get(event)?.delete(handler);
    };
  }

  /**
   * Send a request and wait for response
   */
  private async sendRequest<T>(
    method: string,
    params: Record<string, unknown>
  ): Promise<T> {
    if (!this.connected || !this.ws) {
      throw new Error("Not connected to OpenClaw Gateway");
    }

    return new Promise((resolve, reject) => {
      const id = uuidv4();
      const timeout = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new Error(`Request ${method} timed out`));
      }, 30000);

      this.pendingRequests.set(id, (response) => {
        clearTimeout(timeout);
        this.pendingRequests.delete(id);

        if (response.ok) {
          resolve(response.payload as T);
        } else {
          reject(new Error(response.error?.message || "Request failed"));
        }
      });

      const message: RequestMessage = {
        type: "req",
        id,
        method,
        params,
      };

      this.ws!.send(JSON.stringify(message));
    });
  }

  /**
   * Perform handshake with Gateway
   */
  private async handshake(): Promise<void> {
    const connectParams: ConnectParams = {
      version: "1.0.0",
      deviceId: this.config.deviceId,
      deviceName: this.config.deviceName,
      role: "client",
      auth: this.config.token ? { token: this.config.token } : undefined,
    };

    const response = await this.sendRequest<ConnectResponse>("connect", connectParams as unknown as Record<string, unknown>);
    
    if (!response.ok) {
      throw new Error(response.error?.message || "Handshake failed");
    }

    console.log("Handshake successful:", response.payload);
  }

  /**
   * Handle incoming WebSocket message
   */
  private handleMessage(data: string): void {
    try {
      const message: GatewayMessage = JSON.parse(data);

      switch (message.type) {
        case "res":
          this.handleResponse(message);
          break;
        case "event":
          this.handleEvent(message);
          break;
        default:
          console.warn("Unknown message type:", message);
      }
    } catch (err) {
      console.error("Failed to parse Gateway message:", err);
    }
  }

  /**
   * Handle response message
   */
  private handleResponse(response: ResponseMessage): void {
    const handler = this.pendingRequests.get(response.id);
    if (handler) {
      handler(response);
    } else {
      console.warn("No handler for response:", response.id);
    }
  }

  /**
   * Handle event message
   */
  private handleEvent(event: EventMessage): void {
    const handlers = this.eventHandlers.get(event.event);
    if (handlers) {
      handlers.forEach((handler) => {
        try {
          handler(event);
        } catch (err) {
          console.error("Event handler error:", err);
        }
      });
    }
  }

  /**
   * Handle disconnect and attempt reconnection
   */
  private handleDisconnect(): void {
    if (this.reconnecting || !this.config.enabled) {
      return;
    }

    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error("Max reconnection attempts reached");
      return;
    }

    this.reconnecting = true;
    this.reconnectAttempts++;
    
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
    console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})...`);

    setTimeout(async () => {
      this.reconnecting = false;
      try {
        await this.connect();
      } catch (err) {
        console.error("Reconnection failed:", err);
      }
    }, delay);
  }
}

// Singleton instance
let gatewayClient: OpenClawGatewayClient | null = null;

/**
 * Get or create OpenClaw Gateway client
 */
export function getOpenClawClient(config?: OpenClawConfig): OpenClawGatewayClient | null {
  if (!config?.enabled) {
    return null;
  }

  if (!gatewayClient) {
    gatewayClient = new OpenClawGatewayClient(config);
  }

  return gatewayClient;
}

/**
 * Initialize OpenClaw integration
 */
export async function initOpenClaw(): Promise<OpenClawGatewayClient | null> {
  const config = getOpenClawConfigFromEnv();
  
  if (!config.enabled) {
    console.log("OpenClaw integration not configured (set OPENCLAW_ENABLED=true)");
    return null;
  }

  const client = getOpenClawClient(config);
  if (client) {
    await client.connect();
  }
  
  return client;
}

/**
 * Get OpenClaw config from environment
 */
function getOpenClawConfigFromEnv(): OpenClawConfig {
  // OPENCLAW_GATEWAY_URL is set automatically by Terraform
  // pointing to the Azure Container App running the OpenClaw Gateway
  const gatewayUrl = process.env.OPENCLAW_GATEWAY_URL || "ws://127.0.0.1:18789";

  return {
    enabled: process.env.OPENCLAW_ENABLED === "true",
    gatewayUrl,
    token: process.env.OPENCLAW_GATEWAY_TOKEN,
    deviceId: process.env.OPENCLAW_DEVICE_ID || `moltbot-${process.env.HOSTNAME || "azure"}`,
    deviceName: process.env.OPENCLAW_DEVICE_NAME || "MoltBot Azure Agent",
    model: process.env.OPENCLAW_MODEL || "anthropic/claude-sonnet-4-20250514",
    thinking: (process.env.OPENCLAW_THINKING as OpenClawConfig["thinking"]) || "low",
  };
}
