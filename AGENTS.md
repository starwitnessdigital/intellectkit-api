# IntellectKit API — Agent Integration Guide

IntellectKit is a REST API for extracting structured data from the web, designed to be called
directly by AI agents as tools. One API key, clean typed JSON, predictable schemas.

## Quick start

```
Base URL:  https://api.intellectkit.dev
Auth:      X-API-Key: ik_your_key_here
Spec:      GET /v1/openapi
```

Demo keys (for testing):
- `ik_free_demo_key_123` — 100 req/day
- `ik_starter_demo_key_456` — 1,000 req/day
- `ik_pro_demo_key_789` — 10,000 req/day

---

## Claude Code integration

Add IntellectKit as a tool in any Claude conversation by describing the endpoints in your system prompt:

```
You have access to the IntellectKit API for web data extraction.
To extract article content from a URL: GET https://api.intellectkit.dev/v1/extract/article?url=<url>
To validate an email address: GET https://api.intellectkit.dev/v1/tools/validate-email?email=<email>
Always include the header: X-API-Key: ik_your_key_here
```

Or use the MCP server (see below) for native Claude Code tool integration.

---

## MCP server

The easiest way to give any Claude instance access to IntellectKit is via the MCP server:

```bash
# Install globally
npm install -g @intellectkit/mcp-server

# Or run directly
npx @intellectkit/mcp-server
```

Add to your Claude Code config (`~/.claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "intellectkit": {
      "command": "npx",
      "args": ["@intellectkit/mcp-server"],
      "env": {
        "INTELLECTKIT_API_KEY": "ik_your_key_here"
      }
    }
  }
}
```

Once connected, Claude will have these tools available:
- `extract_article` — Extract article content from a URL
- `extract_product` — Extract product data from an e-commerce page
- `extract_metadata` — Extract Open Graph, Twitter cards, JSON-LD metadata
- `extract_links` — Extract and classify all links on a page
- `extract_text` — Get clean readable text from any URL
- `validate_email` — Validate an email address format
- `dns_lookup` — Look up DNS records for a domain

---

## OpenAI function calling schemas

Add these to your `tools` array in the ChatCompletion API request:

### extract_article

```json
{
  "type": "function",
  "function": {
    "name": "extract_article",
    "description": "Extract structured article content from a web page URL. Returns title, author, publish date, clean body text, images, word count, reading time estimate, and a short summary. Use the summary field for quick relevance checks before processing the full body.",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL of the article to extract. Must start with http:// or https://"
        }
      },
      "required": ["url"]
    }
  }
}
```

### extract_product

```json
{
  "type": "function",
  "function": {
    "name": "extract_product",
    "description": "Extract structured product data from an e-commerce page. Returns name, price, currency, description, brand, availability status, rating, review count, and product images. Works best on individual product detail pages.",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL of the product page to extract from"
        }
      },
      "required": ["url"]
    }
  }
}
```

### extract_metadata

```json
{
  "type": "function",
  "function": {
    "name": "extract_metadata",
    "description": "Extract page metadata including Open Graph tags, Twitter card tags, JSON-LD structured data, canonical URL, language, and favicon from any web page. JSON-LD often contains rich structured data (Organization, Article, Product) that is useful for further reasoning.",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL of the page to extract metadata from"
        }
      },
      "required": ["url"]
    }
  }
}
```

### extract_links

```json
{
  "type": "function",
  "function": {
    "name": "extract_links",
    "description": "Extract all hyperlinks from a web page with anchor text and internal/external classification. Fragment-only links, javascript:, mailto:, and tel: links are excluded. Useful for site structure analysis and discovering related content.",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL of the page to extract links from"
        }
      },
      "required": ["url"]
    }
  }
}
```

### extract_text

```json
{
  "type": "function",
  "function": {
    "name": "extract_text",
    "description": "Extract clean readable text from a web page with navigation, ads, headers, footers, and other UI chrome stripped. Returns word count so you can estimate token usage before including in context. Best endpoint for feeding page content directly to an LLM.",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL of the page to extract text from"
        }
      },
      "required": ["url"]
    }
  }
}
```

### validate_email

```json
{
  "type": "function",
  "function": {
    "name": "validate_email",
    "description": "Validate an email address format using RFC 5321 rules. Returns isValid boolean and a specific reason when invalid. Use the reason field to give users actionable feedback rather than a generic error.",
    "parameters": {
      "type": "object",
      "properties": {
        "email": {
          "type": "string",
          "description": "The email address to validate"
        }
      },
      "required": ["email"]
    }
  }
}
```

### dns_lookup

```json
{
  "type": "function",
  "function": {
    "name": "dns_lookup",
    "description": "Look up DNS records (A, MX, TXT, NS, CNAME) for any domain. Useful for verifying domain ownership, finding email providers from MX records, checking SPF/DKIM configuration from TXT records, or resolving a domain to its IP address.",
    "parameters": {
      "type": "object",
      "properties": {
        "domain": {
          "type": "string",
          "description": "The domain name to look up (e.g. example.com — not a full URL)"
        }
      },
      "required": ["domain"]
    }
  }
}
```

---

## Anthropic tool_use schemas

Add these to your `tools` array in the Messages API request:

```python
import anthropic

client = anthropic.Anthropic(api_key="your-anthropic-key")

INTELLECTKIT_TOOLS = [
    {
        "name": "extract_article",
        "description": "Extract structured article content from a web page URL. Returns title, author, publish date, clean body text, images, word count, reading time, and a short summary.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {
                    "type": "string",
                    "description": "The URL of the article to extract"
                }
            },
            "required": ["url"]
        }
    },
    {
        "name": "extract_text",
        "description": "Extract clean readable text from any web page with navigation and ads stripped. Returns word count for token estimation.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "The URL to extract text from"}
            },
            "required": ["url"]
        }
    },
    {
        "name": "validate_email",
        "description": "Validate an email address. Returns isValid boolean and reason when invalid.",
        "input_schema": {
            "type": "object",
            "properties": {
                "email": {"type": "string", "description": "Email address to validate"}
            },
            "required": ["email"]
        }
    },
    {
        "name": "dns_lookup",
        "description": "Look up DNS records (A, MX, TXT, NS, CNAME) for a domain.",
        "input_schema": {
            "type": "object",
            "properties": {
                "domain": {"type": "string", "description": "Domain to look up (e.g. example.com)"}
            },
            "required": ["domain"]
        }
    }
]

INTELLECTKIT_BASE = "https://api.intellectkit.dev"
INTELLECTKIT_KEY = "ik_your_key_here"

def call_intellectkit(tool_name: str, tool_input: dict) -> str:
    """Execute an IntellectKit tool call and return the JSON result as a string."""
    import requests
    endpoint_map = {
        "extract_article":  "/v1/extract/article",
        "extract_product":  "/v1/extract/product",
        "extract_metadata": "/v1/extract/metadata",
        "extract_links":    "/v1/extract/links",
        "extract_text":     "/v1/extract/text",
        "validate_email":   "/v1/tools/validate-email",
        "dns_lookup":       "/v1/tools/dns",
    }
    path = endpoint_map[tool_name]
    param_key = "email" if tool_name == "validate_email" else ("domain" if tool_name == "dns_lookup" else "url")
    resp = requests.get(
        INTELLECTKIT_BASE + path,
        params={param_key: tool_input[param_key]},
        headers={"X-API-Key": INTELLECTKIT_KEY},
        timeout=15,
    )
    return resp.text
```

---

## Tool call execution pattern

```python
import json

def run_agent_loop(user_message: str) -> str:
    messages = [{"role": "user", "content": user_message}]

    while True:
        response = client.messages.create(
            model="claude-opus-4-6",
            max_tokens=4096,
            tools=INTELLECTKIT_TOOLS,
            messages=messages,
        )

        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    result = call_intellectkit(block.name, block.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    })
            messages.append({"role": "assistant", "content": response.content})
            messages.append({"role": "user", "content": tool_results})
        else:
            return next(b.text for b in response.content if hasattr(b, "text"))
```

---

## Example prompts that trigger these tools

These are natural language requests that an agent with IntellectKit tools will handle by
calling the appropriate endpoint:

**Article extraction:**
- "Summarize this article: https://..."
- "Who wrote the piece at [URL] and when was it published?"
- "What are the key points from this blog post?"
- "Extract the article at [URL] and tell me the reading time"

**Product data:**
- "What's the price of this product: https://..."
- "Is this item in stock? [product URL]"
- "Compare the ratings of these two products"
- "What brand makes this? [URL]"

**Metadata:**
- "What does this website say about itself in its meta tags?"
- "Does [URL] have JSON-LD structured data?"
- "What's the canonical URL for this page?"

**Links:**
- "What external sites does this page link to?"
- "How many internal links are on this page?"
- "What is the link structure of [URL]?"

**Text extraction:**
- "Read the content at [URL] and answer: ..."
- "Summarize the main content of this page (ignore the nav and ads)"
- "What does [URL] say about [topic]?"

**Email validation:**
- "Is this email address valid: user@domain.com?"
- "Check if [email] is properly formatted before I add it to the database"
- "Validate these email addresses: [list]"

**DNS lookup:**
- "Who hosts email for example.com?"
- "What are the DNS records for [domain]?"
- "Look up the A record for [domain]"
- "Check the MX records to see what email provider [company] uses"

---

## Error handling for agents

All errors return JSON with a `reason` field that agents can relay directly:

```json
{"error": "Bad Request", "reason": "url parameter must start with http:// or https://"}
{"error": "Unauthorized", "reason": "Missing X-API-Key header"}
{"error": "Too Many Requests", "reason": "Daily limit of 100 requests exceeded. Resets at midnight UTC."}
{"error": "Bad Gateway", "reason": "Could not fetch target URL: connection refused"}
```

HTTP status codes:
- `200` — Success (always check `isValid` field for email validation)
- `400` — Bad request (missing or invalid parameter)
- `401` — Invalid or missing API key
`429` — Rate limit exceeded
- `502` — Could not fetch the target URL

---

## Why IntellectKit?

| Feature | IntellectKit | DIY scraping |
|---------|-------------|--------------|
| One API key | ✓ | Multiple tools/proxies |
| Typed JSON responses | ✓ | Parse HTML yourself |
| Agent-optimized descriptions | ✓ | Write them yourself |
| Null-safe schemas | ✓ | Handle missing fields |
| No browser dependency | ✓ | Playwright/Puppeteer |
| Built-in rate limiting | ✓ | Implement yourself |
| Email + DNS utilities | ✓ | Separate services |
