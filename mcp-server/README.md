# @intellectkit/mcp-server

MCP server that wraps [IntellectKit API](https://api.intellectkit.dev) endpoints as tools
for Claude and other AI agents that support the Model Context Protocol.

## Tools provided

| Tool | Description |
|------|-------------|
| `extract_article` | Extract article content (title, author, date, body, summary) |
| `extract_product` | Extract product data (name, price, currency, brand, rating) |
| `extract_metadata` | Extract Open Graph, Twitter cards, JSON-LD metadata |
| `extract_links` | Extract and classify all links (internal/external) |
| `extract_text` | Get clean readable text with nav/ads stripped |
| `validate_email` | Validate email format with specific failure reason |
| `dns_lookup` | Look up A, MX, TXT, NS, CNAME DNS records |

## Installation

```bash
# Run directly (no install required)
npx @intellectkit/mcp-server

# Or install globally
npm install -g @intellectkit/mcp-server
intellectkit-mcp
```

## Configuration

Set your API key via environment variable:

```bash
export INTELLECTKIT_API_KEY=ik_your_key_here
```

Demo keys for testing:
- `ik_free_demo_key_123` — 100 req/day
- `ik_starter_demo_key_456` — 1,000 req/day

Get a production key at [api.intellectkit.dev](https://api.intellectkit.dev).

## Claude Code / Claude Desktop setup

Add to `~/.claude/claude_desktop_config.json`:

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

Then restart Claude. The tools will appear automatically.

## Custom base URL

Override the API base URL for local development:

```bash
INTELLECTKIT_BASE_URL=http://localhost:8080 INTELLECTKIT_API_KEY=ik_free_demo_key_123 npx @intellectkit/mcp-server
```

## Local development

```bash
git clone https://github.com/intellectkit/mcp-server
cd mcp-server
npm install
INTELLECTKIT_API_KEY=ik_free_demo_key_123 npm run dev
```

## License

MIT
