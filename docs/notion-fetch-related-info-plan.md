# Notion fetch related-info plan

## Goal
- Extend related-info lookup from "show matching Notion page links" to "fetch matching page content and show a short content snippet".

## Scope
- Keep existing Notion MCP OAuth/search flow.
- Add `notion-fetch` after `notion-search` for the top search results.
- Fill `RelatedDoc.snippet` with fetched page text when available.
- Do not add LLM summarization or a local semantic index in this iteration.

## Verification
- Unit tests for fetch-content parsing and snippet cleanup.
- `./scripts/dev.sh build`
- `./scripts/dev.sh test`

## Progress
- [x] Inspect current search and display model.
- [x] Add fetch tool call and parsing.
- [x] Add tests.
- [x] Build and test.
