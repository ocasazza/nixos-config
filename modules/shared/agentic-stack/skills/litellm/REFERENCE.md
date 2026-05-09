# LiteLLM API Reference

This document provides a detailed reference for the LiteLLM Proxy management API.

## Authentication

All admin requests require the `LITELLM_MASTER_KEY` passed as a Bearer token in the `Authorization` header.

```bash
-H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

## Endpoints

### User Management

- `POST /user/new`: Create a new user.
  - Body: `{"user_id": string, "user_alias": string, "max_budget": float, "budget_duration": string, "team_id": string}`
- `POST /user/update`: Update user details.
- `POST /user/delete`: Delete a user.
- `GET /user/info`: Get info for a specific user.

### Team Management

- `POST /team/new`: Create a new team.
  - Body: `{"team_alias": string, "organization_id": string, "max_budget": float, "budget_duration": string}`
- `POST /team/update`: Update team details.
- `POST /team/delete`: Delete a team.

### Key Management

- `POST /key/generate`: Generate a new virtual key.
  - Body: `{"user_id": string, "team_id": string, "models": list, "duration": string, "max_budget": float}`
- `POST /key/update`: Update an existing key.
- `POST /key/delete`: Revoke a key.

### Model Management

- `POST /model/new`: Add a new model to the proxy.
  - Body: `{"model_name": string, "litellm_params": {"model": string, "api_key": string, "api_base": string}}`
- `POST /model/update`: Update model parameters.
- `POST /model/delete`: Remove a model from the proxy.

### MCP Server Management

- `POST /mcp/new`: Add an MCP server.
- `POST /mcp/delete`: Remove an MCP server.

### Usage & Budgeting

- `GET /usage`: View global usage statistics.
- `GET /usage/user`: View usage for a specific user.
- `GET /usage/team`: View usage for a specific team.
