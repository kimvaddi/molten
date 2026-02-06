/**
 * OpenClaw Integration Module
 * 
 * This module provides integration with OpenClaw Gateway for enhanced
 * AI agent capabilities including skills, multi-channel support, and
 * advanced session management.
 * 
 * Usage:
 *   import { initOpenClaw, getOpenClawClient } from "./openclaw";
 *   
 *   // Initialize at startup
 *   await initOpenClaw();
 *   
 *   // Send messages through OpenClaw
 *   const client = getOpenClawClient();
 *   const response = await client.sendAgentMessage("Hello!");
 * 
 * Environment variables:
 *   OPENCLAW_ENABLED=true           - Enable OpenClaw integration
 *   OPENCLAW_GATEWAY_URL=ws://...   - Gateway WebSocket URL
 *   OPENCLAW_GATEWAY_TOKEN=xxx      - Optional auth token
 *   OPENCLAW_MODEL=anthropic/...    - Model to use
 *   OPENCLAW_THINKING=low           - Thinking level (off|minimal|low|medium|high)
 */

export * from "./types";
export * from "./gateway-client";
