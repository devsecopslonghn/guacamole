# Apache Guacamole + Keycloak OpenID Connect - Helm Chart Deployment Guide

This guide documents the deployment of Apache Guacamole via Helm with Keycloak integration (OpenID Connect SSO), using PostgreSQL and External Secrets. It also outlines key issues encountered and how they were resolved.

---

## ✨ Objectives

- Deploy Guacamole using Helm with PostgreSQL backend
- Authenticate users using Keycloak via OpenID Connect
- Map Keycloak groups to Guacamole permissions (e.g. `guac-admins`, `guac-users`)
- Load secrets from AWS SSM via External Secrets

---

## ⚙️ Deployment Overview

### Technologies Used:
- Apache Guacamole (`guacamole/guacamole:latest`, `guacamole/guacd:latest`)
- Keycloak (OIDC IdP)
- PostgreSQL (Bitnami chart)
- Kubernetes + Helm
- External Secrets (AWS SSM)

---

## 📊 Helm Values Explanation

### `guacamole.env` (PostgreSQL connection)
```yaml
POSTGRES_HOSTNAME: guacamole-postgresql
POSTGRES_DATABASE: guacamole_db
POSTGRES_USER: guacamole_user
POSTGRES_PASSWORD: guacamole_pass
```

### `guacamole.extraEnv` (OIDC & feature config)
```yaml
OPENID_ENABLED: "true"
POSTGRESQL_AUTO_CREATE_ACCOUNTS: "true"
OPENID_CLIENT_ID_FILE: /secrets/openid-client-id
OPENID_CLIENT_SECRET_FILE: /secrets/openid-client-secret
OPENID_AUTHORIZATION_ENDPOINT: <Keycloak URL>
OPENID_TOKEN_ENDPOINT: <Keycloak URL>
OPENID_JWKS_ENDPOINT: <Keycloak URL>
OPENID_ISSUER: <Keycloak Realm Issuer>
OPENID_REDIRECT_URI: <URL to Guacamole>
OPENID_GROUP_MAPPING: "//guac-admins:ADMIN,//guac-users:READ"  # Legacy feature (not yet used)
```

> Note: The group mapping string in `OPENID_GROUP_MAPPING` is **currently unused by Guacamole** as of latest version. Mapping happens only if group names in token match internal DB groups with defined permissions.

---

## 📁 ConfigMap: `guacamole-config`
```yaml
guacamole.properties:
  extension-priority: openid, postgresql, ban
  postgresql-hostname: {{ .Values.guacamole.env.POSTGRES_HOSTNAME }}
  postgresql-port: 5432
  postgresql-database: {{ .Values.guacamole.env.POSTGRES_DATABASE }}
  postgresql-username: {{ .Values.guacamole.env.POSTGRES_USER }}
  postgresql-password: {{ .Values.guacamole.env.POSTGRES_PASSWORD }}
  auth-provider: net.sourceforge.guacamole.net.auth.openid.OpenIDAuthenticationProvider
  disable-authorization-notification: true
  disable-user-password-authentication: true
  openid-authorization-endpoint: ...
  openid-token-endpoint: ...
  openid-jwks-endpoint: ...
  openid-issuer: ...
  openid-redirect-uri: ...
  openid-username-claim-type: preferred_username
  openid-groups-claim-type: groups
```

### Explanation:
- `extension-priority`: Ensures OpenID is evaluated before other auth backends.
- `disable-user-password-authentication`: Blocks local DB login form.
- `openid-*-endpoint`: Pulled directly from Keycloak realm discovery document
- `openid-*-claim-type`: Maps token claims (e.g. `preferred_username`, `groups`) to Guacamole

---

## 🚫 Issues Encountered & Fixes

### 1. **Token contains `"//guac-admins"` instead of `"guac-admins"`**
- **Root cause**: Keycloak's group mapper had `Full group path = true`
- **Fix**: Set `Full group path = false` in Keycloak Client Mapper

### 2. **User "123" successfully logs in but has no visible permissions**
- **Root cause**: User permissions from OIDC group mapping aren't shown in GUI
- **Fix (under the hood)**: Guacamole still applies permissions via token claim mapping even if not visible in GUI
- **Optional fix**: Add user to group via DB for GUI visibility:
```sql
INSERT INTO guacamole_user_group_member (user_group_id, member_entity_id)
VALUES (<guac-admins-id>, <user-123-entity-id>);
```

### 3. **OIDC token group mapping worked without user being in DB group**
- Guacamole **evaluates group claims from the ID Token** at login time.
- If the claim `groups` contains `guac-admins`, and a matching entity exists in DB **with ADMIN permission**, user will get full admin access.
- This works **even if the user is not in `guacamole_user_group_member`**

### 4. **No logs about group membership despite login success**
- **Cause**: By default, Guacamole doesn’t log group evaluation unless DEBUG is enabled
- **Optional Fix**: Enable DEBUG in logback.xml to trace claims -> permissions

### 5. **`guacamole_system_permission` has no entry for user, but access still granted**
- ✅ Expected behavior: Guacamole applies group-level permissions from OIDC token claims

---

## 🌐 External Secrets (AWS SSM)

### Secrets Used:
- `/guacamole/openid-client-id`
- `/guacamole/openid-client-secret`

### Mapped into container as:
```yaml
- name: guac-openid-secret
  mountPath: /secrets
  readOnly: true
```

And used in env:
```yaml
OPENID_CLIENT_ID_FILE=/secrets/openid-client-id
OPENID_CLIENT_SECRET_FILE=/secrets/openid-client-secret
```

---

## 🚀 Deployment Checklist

- [x] PostgreSQL enabled and reachable
- [x] Guacamole image correctly configured
- [x] OIDC endpoints match Keycloak Realm
- [x] `openid-groups-claim-type` matches claim in token
- [x] Keycloak group claim returns clean group names (`guac-admins`, not `//guac-admins`)
- [x] Group `guac-admins` exists in DB and has `ADMIN` permission:
```sql
INSERT INTO guacamole_system_permission (entity_id, permission)
VALUES (<guac-admins-entity-id>, 'ADMIN');
```

---

## 🎯 Result

- User logs in via Keycloak (OIDC)
- Token contains `groups = ["guac-admins"]`
- Guacamole maps group to DB entity with ADMIN permission
- User has full admin rights without explicit DB user entry

---

## 🚀 Next Steps
- Optional: Build group -> permission matrix (`guac-users`, `guac-readonly`)
- Consider enabling logback DEBUG for OIDC debugging
- Document group mapping logic for future maintainers

---

Feel free to modify this README and commit it to your Helm chart repo or platform documentation.
