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
- `ip_info` — IP geolocation: country, city, ISP, AS number, lat/lon
- `ssl_info` — SSL certificate details and days until expiry
- `url_info` — Parse URL components and follow redirect chain
- `hash_text` — Hash text with md5, sha1, sha256, or sha512
- `encode_text` — Encode text as base64, URL-encoded, or HTML entities
- `decode_text` — Decode base64, URL-encoded, or HTML entity text
- `json_validate` — Validate JSON and summarize its structure

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

### ip_info

```json
{
  "type": "function",
  "function": {
    "name": "ip_info",
    "description": "Get geolocation and network data for an IP address. Returns country, region, city, ISP, organization, AS number, timezone, and lat/lon coordinates.",
    "parameters": {
      "type": "object",
      "properties": {
        "ip": {
          "type": "string",
          "description": "IPv4 or IPv6 address to look up (e.g. 8.8.8.8)"
        }
      },
      "required": ["ip"]
    }
  }
}
```

### ssl_info

```json
{
  "type": "function",
  "function": {
    "name": "ssl_info",
    "description": "Retrieve SSL/TLS certificate details for a domain. Returns issuer, subject, validity dates, days until expiry, serial number, and signature algorithm. A negative daysUntilExpiry means the certificate is already expired.",
    "parameters": {
      "type": "object",
      "properties": {
        "domain": {
          "type": "string",
          "description": "Domain to check (e.g. example.com — no https:// prefix)"
        }
      },
      "required": ["domain"]
    }
  }
}
```

### url_info

```json
{
  "type": "function",
  "function": {
    "name": "url_info",
    "description": "Parse a URL into its components and follow any redirects. Returns scheme, domain, subdomain, path, query parameters as a key/value map, fragment, isHttps flag, and the full redirect chain with status codes.",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL to analyze (must start with http:// or https://)"
        }
      },
      "required": ["url"]
    }
  }
}
```

### hash_text

```json
{
  "type": "function",
  "function": {
    "name": "hash_text",
    "description": "Hash text using a common algorithm. Supported: md5, sha1, sha256 (default), sha512. Useful for generating checksums, cache keys, or verifying content integrity.",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {
          "type": "string",
          "description": "Text to hash"
        },
        "algorithm": {
          "type": "string",
          "enum": ["md5", "sha1", "sha256", "sha512"],
          "description": "Hash algorithm (default: sha256)"
        }
      },
      "required": ["text"]
    }
  }
}
```

### encode_text

```json
{
  "type": "function",
  "function": {
    "name": "encode_text",
    "description": "Encode text to base64, URL percent-encoding, or HTML entities. Useful for preparing values for transmission in URLs, HTML, or binary protocols.",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {
          "type": "string",
          "description": "Text to encode"
        },
        "format": {
          "type": "string",
          "enum": ["base64", "url", "html"],
          "description": "Encoding format (default: base64)"
        }
      },
      "required": ["text"]
    }
  }
}
```

### decode_text

```json
{
  "type": "function",
  "function": {
    "name": "decode_text",
    "description": "Decode base64, URL percent-encoded, or HTML entity text back to plaintext. Useful for reading webhook payloads, JWT components, or escaped HTML.",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {
          "type": "string",
          "description": "Text to decode"
        },
        "format": {
          "type": "string",
          "enum": ["base64", "url", "html"],
          "description": "Decoding format (default: base64)"
        }
      },
      "required": ["text"]
    }
  }
}
```

### json_validate

```json
{
  "type": "function",
  "function": {
    "name": "json_validate",
    "description": "Validate a JSON string and return a structure summary. Returns valid boolean, error message if invalid, and a summary of the top-level type, keys, array length, and nesting depth. Send the JSON as the request body.",
    "parameters": {
      "type": "object",
      "properties": {
        "json": {
          "type": "string",
          "description": "The JSON string to validate (sent as raw request body)"
        }
      },
      "required": ["json"]
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
    },
    {
        "name": "ip_info",
        "description": "Get geolocation and network data for an IP address. Returns country, city, ISP, AS number, timezone, lat/lon.",
        "input_schema": {
            "type": "object",
            "properties": {
                "ip": {"type": "string", "description": "IPv4 or IPv6 address (e.g. 8.8.8.8)"}
            },
            "required": ["ip"]
        }
    },
    {
        "name": "ssl_info",
        "description": "Get SSL certificate details for a domain: issuer, validity dates, days until expiry.",
        "input_schema": {
            "type": "object",
            "properties": {
                "domain": {"type": "string", "description": "Domain to check (e.g. example.com)"}
            },
            "required": ["domain"]
        }
    },
    {
        "name": "url_info",
        "description": "Parse a URL and follow its redirect chain. Returns components and each redirect hop.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "URL to analyze"}
            },
            "required": ["url"]
        }
    },
    {
        "name": "hash_text",
        "description": "Hash text with md5, sha1, sha256, or sha512.",
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to hash"},
                "algorithm": {"type": "string", "enum": ["md5", "sha1", "sha256", "sha512"], "description": "Algorithm (default: sha256)"}
            },
            "required": ["text"]
        }
    },
    {
        "name": "encode_text",
        "description": "Encode text as base64, URL percent-encoding, or HTML entities.",
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to encode"},
                "format": {"type": "string", "enum": ["base64", "url", "html"], "description": "Format (default: base64)"}
            },
            "required": ["text"]
        }
    },
    {
        "name": "decode_text",
        "description": "Decode base64, URL percent-encoded, or HTML entity text.",
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to decode"},
                "format": {"type": "string", "enum": ["base64", "url", "html"], "description": "Format (default: base64)"}
            },
            "required": ["text"]
        }
    },
    {
        "name": "json_validate",
        "description": "Validate JSON and return structure summary (type, keys, depth, array length).",
        "input_schema": {
            "type": "object",
            "properties": {
                "json": {"type": "string", "description": "JSON string to validate (sent as request body)"}
            },
            "required": ["json"]
        }
    }
]

INTELLECTKIT_BASE = "https://api.intellectkit.dev"
INTELLECTKIT_KEY = "ik_your_key_here"

def call_intellectkit(tool_name: str, tool_input: dict) -> str:
    """Execute an IntellectKit tool call and return the JSON result as a string."""
    import requests
    endpoint_map = {
        "extract_article":  ("/v1/extract/article",  "get"),
        "extract_product":  ("/v1/extract/product",  "get"),
        "extract_metadata": ("/v1/extract/metadata", "get"),
        "extract_links":    ("/v1/extract/links",    "get"),
        "extract_text":     ("/v1/extract/text",     "get"),
        "validate_email":   ("/v1/tools/validate-email", "get"),
        "dns_lookup":       ("/v1/tools/dns",         "get"),
        "ip_info":          ("/v1/tools/ip-info",     "get"),
        "ssl_info":         ("/v1/tools/ssl",         "get"),
        "url_info":         ("/v1/tools/url-info",    "get"),
        "hash_text":        ("/v1/tools/hash",        "get"),
        "encode_text":      ("/v1/tools/encode",      "get"),
        "decode_text":      ("/v1/tools/decode",      "get"),
        "json_validate":    ("/v1/tools/json-validate", "post"),
    }
    param_map = {
        "validate_email": "email",
        "dns_lookup": "domain",
        "ip_info": "ip",
        "ssl_info": "domain",
        "url_info": "url",
        "hash_text": "text",
        "encode_text": "text",
        "decode_text": "text",
    }
    path, method = endpoint_map[tool_name]
    headers = {"X-API-Key": INTELLECTKIT_KEY}

    if method == "post":
        resp = requests.post(
            INTELLECTKIT_BASE + path,
            data=tool_input.get("json", ""),
            headers={**headers, "Content-Type": "application/json"},
            timeout=15,
        )
    else:
        param_key = param_map.get(tool_name, "url")
        params = {param_key: tool_input[param_key]}
        if tool_name == "hash_text" and "algorithm" in tool_input:
            params["algorithm"] = tool_input["algorithm"]
        if tool_name in ("encode_text", "decode_text") and "format" in tool_input:
            params["format"] = tool_input["format"]
        resp = requests.get(
            INTELLECTKIT_BASE + path,
            params=params,
            headers=headers,
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

**IP geolocation:**
- "Where is this IP address located: 8.8.8.8?"
- "Which country is this IP from?"
- "What ISP or AS number owns this IP?"

**SSL certificate:**
- "Is the SSL certificate for example.com still valid?"
- "When does the certificate for [domain] expire?"
- "Check the SSL cert on [domain] — who issued it?"

**URL analysis:**
- "Where does this short link redirect to?"
- "Parse the query parameters out of this URL"
- "Does this URL use HTTPS? Does it redirect?"

**Hashing:**
- "Hash this string with SHA-256: hello world"
- "Generate an MD5 checksum for [text]"
- "What is the SHA-512 hash of [value]?"

**Encoding/decoding:**
- "Base64-encode this text: [text]"
- "Decode this base64 string: [string]"
- "URL-encode this value before adding it to a query string"
- "Decode these HTML entities: &lt;b&gt;Hello&lt;/b&gt;"

**JSON validation:**
- "Is this JSON valid? [paste JSON]"
- "What are the top-level keys in this JSON payload?"
- "How deeply nested is this JSON structure?"

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
| IP geolocation | ✓ | Third-party accounts |
| SSL cert inspection | ✓ | openssl shell commands |
| URL parsing + redirects | ✓ | Custom code |
| Hashing (md5/sha*) | ✓ | Language-specific libs |
| Base64/URL/HTML encode | ✓ | Language-specific libs |
| JSON validation | ✓ | Language-specific libs |
