---
name: litellm
description: Manage LiteLLM proxy deployments including users, teams, API keys, organizations, models, and MCP servers. Use this skill to perform CRUD operations on LiteLLM entities and monitor usage.
---

# LiteLLM Management

LiteLLM is a proxy that allows you to manage multiple LLM providers through a unified interface. This skill provides instructions for managing a live LiteLLM proxy deployment using its REST API.

## Preconditions

- A LiteLLM proxy must be running.
- You must have the `LITELLM_MASTER_KEY` (or an admin key) to authorize requests.
- The default endpoint is `http://0.0.0.0:4000`, but in this environment, it may be configured differently (e.g., `http://pdx-nxst-001.schrodinger.com:8080/litellm`).

## Management Operations

All operations use `curl` with the following header for authentication:
`-H "Authorization: Bearer $LITELLM_MASTER_KEY"`

### Users

- **Add User**: `POST /user/new`
  ```json
  {
    "user_id": "user_id",
    "user_alias": "alias",
    "team_id": "optional_team_id"
  }
  ```
- **Update User**: `POST /user/update`
- **Delete User**: `POST /user/delete`

### Teams

- **Add Team**: `POST /team/new`
  ```json
  {
    "team_alias": "team_name",
    "organization_id": "optional_org_id"
  }
  ```
- **Update Team**: `POST /team/update`
- **Delete Team**: `POST /team/delete`

### API Keys

- **Add Key**: `POST /key/generate`
  ```json
  {
    "user_id": "user_id",
    "team_id": "team_id",
    "duration": "optional_duration"
  }
  ```
- **Update Key**: `POST /key/update`
- **Delete Key**: `POST /key/delete`

### Models

- **Add Model**: `POST /model/new`
  ```json
  {
    "model_name": "alias",
    "litellm_params": {
      "model": "provider/model_name",
      "api_key": "optional_key"
    }
  }
  ```
- **Update Model**: `POST /model/update`
- **Delete Model**: `POST /model/delete`

### MCP Servers

- **Add MCP**: `POST /mcp/new`
- **Update MCP**: `POST /mcp/update`
- **Delete MCP**: `POST /mcp/delete`

### Usage

- **View Usage**: `GET /usage` or `GET /user/info?user_id=...`

## Troubleshooting

- Ensure `LITELLM_MASTER_KEY` is correctly set.
- Check the proxy logs if requests fail with 5xx errors.
- 401/403 errors usually indicate an invalid or missing master key.
