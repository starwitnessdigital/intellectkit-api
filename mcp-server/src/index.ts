#!/usr/bin/env node
/**
 * IntellectKit MCP Server
 * Wraps IntellectKit API endpoints as MCP tools for Claude and other AI agents.
 *
 * Usage:
 *   INTELLECTKIT_API_KEY=ik_your_key npx @intellectkit/mcp-server
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";

// ── Configuration ─────────────────────────────────────────────────────────────

const BASE_URL = process.env.INTELLECTKIT_BASE_URL ?? "https://api.intellectkit.dev";
const API_KEY = process.env.INTELLECTKIT_API_KEY;

if (!API_KEY) {
  console.error(
    "Error: INTELLECTKIT_API_KEY environment variable is required.\n" +
    "Get a key at https://api.intellectkit.dev\n" +
    "Demo key for testing: ik_free_demo_key_123"
  );
  process.exit(1);
}

// ── Tool definitions ──────────────────────────────────────────────────────────

const TOOLS: Tool[] = [
  {
    name: "extract_article",
    description:
      "Extract structured article content from a web page URL. " +
      "Returns title, author, publish date, clean body text (with nav/ads stripped), " +
      "images, word count, estimated reading time in minutes, and a short summary (~300 chars). " +
      "Use the summary field for quick relevance checks before processing the full bodyText. " +
      "Best for: news articles, blog posts, long-form content pages.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The full URL of the article to extract. Must start with http:// or https://",
        },
      },
      required: ["url"],
    },
  },
  {
    name: "extract_product",
    description:
      "Extract structured product data from an e-commerce page. " +
      "Returns name, price, currency, description, brand, availability (InStock/OutOfStock), " +
      "rating value, review count, and product images. " +
      "Uses Schema.org structured data, Open Graph tags, and heuristic fallbacks. " +
      "Best for: individual product detail pages — category/listing pages return partial data.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The full URL of the product page to extract from",
        },
      },
      required: ["url"],
    },
  },
  {
    name: "extract_metadata",
    description:
      "Extract page metadata from any web page. " +
      "Returns Open Graph tags (og:title, og:description, og:image, etc.), " +
      "Twitter card tags, JSON-LD structured data (Organization, Article, Product, BreadcrumbList), " +
      "canonical URL, page language, and favicon URL. " +
      "JSON-LD fields often contain rich machine-readable data useful for further reasoning. " +
      "Best for: understanding what a page is about without fetching its full content.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The full URL of the page to extract metadata from",
        },
      },
      required: ["url"],
    },
  },
  {
    name: "extract_links",
    description:
      "Extract all hyperlinks from a web page with anchor text and classification. " +
      "Each link includes: href (absolute URL), text (anchor text), rel attribute, " +
      "and isExternal (true if the link points to a different domain). " +
      "Filters out fragment-only links (#), javascript:, mailto:, and tel: links. " +
      "Returns total count, internal count, and external count as summary fields. " +
      "Best for: site structure analysis, discovering related content, link auditing.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The full URL of the page to extract links from",
        },
      },
      required: ["url"],
    },
  },
  {
    name: "extract_text",
    description:
      "Extract clean readable text from any web page with UI noise removed. " +
      "Strips navigation, headers, footers, sidebars, ads, cookie banners, popups, and other chrome. " +
      "Returns the readable prose text, word count, and character count. " +
      "Word count helps estimate token usage before including content in an LLM context window. " +
      "Best for: feeding page content directly to an LLM — most token-efficient extraction endpoint.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The full URL of the page to extract text from",
        },
      },
      required: ["url"],
    },
  },
  {
    name: "validate_email",
    description:
      "Validate an email address format using RFC 5321 rules. " +
      "Checks: presence of @ symbol, non-empty local part, valid domain format, " +
      "local part max 64 chars, total max 254 chars, and regex pattern. " +
      "Returns isValid boolean, and when invalid, a specific reason field explaining the problem. " +
      "Use the reason field to give users actionable feedback, not just 'invalid email'.",
    inputSchema: {
      type: "object",
      properties: {
        email: {
          type: "string",
          description: "The email address to validate",
        },
      },
      required: ["email"],
    },
  },
  {
    name: "dns_lookup",
    description:
      "Look up DNS records for any domain. " +
      "Queries A (IP address), MX (mail servers), TXT (SPF, DKIM, verification tokens), " +
      "NS (nameservers), and CNAME (aliases) records. " +
      "Use MX records to identify the email provider for a domain. " +
      "Use TXT records to verify domain ownership or find SPF/DKIM configuration. " +
      "Use A records to resolve a domain to its IP address.",
    inputSchema: {
      type: "object",
      properties: {
        domain: {
          type: "string",
          description:
            "The domain name to look up. Provide just the domain (e.g. example.com), " +
            "not a full URL. Subdomains are supported (e.g. mail.example.com).",
        },
      },
      required: ["domain"],
    },
  },
];

// ── HTTP helper ───────────────────────────────────────────────────────────────

async function callIntellectKit(
  path: string,
  params: Record<string, string>
): Promise<string> {
  const url = new URL(BASE_URL + path);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url.toString(), {
    headers: {
      "X-API-Key": API_KEY!,
      Accept: "application/json",
    },
  });

  const text = await response.text();

  if (!response.ok) {
    // Return the error JSON as-is so the agent can read the reason field
    return text;
  }

  return text;
}

// ── Tool routing ──────────────────────────────────────────────────────────────

type ToolInput = Record<string, string>;

async function dispatchTool(name: string, input: ToolInput): Promise<string> {
  switch (name) {
    case "extract_article":
      return callIntellectKit("/v1/extract/article", { url: input.url });
    case "extract_product":
      return callIntellectKit("/v1/extract/product", { url: input.url });
    case "extract_metadata":
      return callIntellectKit("/v1/extract/metadata", { url: input.url });
    case "extract_links":
      return callIntellectKit("/v1/extract/links", { url: input.url });
    case "extract_text":
      return callIntellectKit("/v1/extract/text", { url: input.url });
    case "validate_email":
      return callIntellectKit("/v1/tools/validate-email", { email: input.email });
    case "dns_lookup":
      return callIntellectKit("/v1/tools/dns", { domain: input.domain });
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// ── Server setup ──────────────────────────────────────────────────────────────

const server = new Server(
  { name: "intellectkit", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    const result = await dispatchTool(name, (args ?? {}) as ToolInput);
    return {
      content: [{ type: "text", text: result }],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text", text: `Error calling IntellectKit: ${message}` }],
      isError: true,
    };
  }
});

// ── Entry point ───────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
