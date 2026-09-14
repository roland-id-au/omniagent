# Omnigent on Render

Deploy Omnigent to Render in one click. Render provisions the app and a
managed Postgres database, assigns an HTTPS URL on `*.onrender.com`, and
handles SSL automatically. No local tooling required.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/omnigent-ai/omnigent)

> **Note:** The button points at the public repo `github.com/omnigent-ai/omnigent`.
> It goes live once that repo **and** the `ghcr.io/omnigent-ai/omnigent-server`
> package are public; until then it only works if you connect Render to the
> (private) repo in the dashboard first.

## What gets provisioned

The `render.yaml` blueprint at the repo root defines:

- **omnigent** (Starter web service) — pulls the pre-built image
  `ghcr.io/omnigent-ai/omnigent-server:latest` (CI-built; ships the web UI
  bundle), served on `https://omniroute.drksci.com`. The combined image pulls
  the OmniAgent server image and installs the pinned OmniRoute runtime.
- **omnigent-db** (`basic-256mb` managed Postgres) — `DATABASE_URL` is injected
  into the service automatically
- **artifact-data** (10 GB persistent disk) — mounted at `/data` so server
  config, the auto-minted cookie secret, and agent artifacts survive redeploys.
  Artifacts live under `/data/artifacts`. (Account rows and password hashes
  live in the managed Postgres, not on the disk.)
- **ds-oa-omni-7k4m2q9v** (Starter web service) — one combined image running
  OmniAgent on internal port 8000 and OmniRoute `3.8.51` on internal port
  20128. Nginx exposes one HTTPS listener and publishes OmniRoute under
  `/router/`.

Public paths are `https://omniroute.drksci.com/` for OmniAgent and
`https://omniroute.drksci.com/router/` for OmniRoute. The application and
router ports are loopback-only inside the container; only Nginx's public port
is exposed.

## Quickstart (built-in accounts — the default)

The blueprint defaults to the built-in `accounts` auth provider: multi-user
out of the box, no external IdP, and **no env vars to fill in** — the server
mints its own cookie secret and auto-detects its public URL from Render.

1. Click the Deploy to Render button above → **Apply**. Wait ~3–5 min for the
   image pull + health check.
2. **Create the first admin.** No credentials are auto-generated. Open your
   `https://<service>.onrender.com` URL — a fresh instance shows a
   Create-admin form where you pick your own username + password. (First-boot
   **Logs** also print a "No admin yet" line with that URL.)
3. Log in as the admin you just created, and invite teammates from **Members**
   in the web UI.

> To create the admin directly instead of claiming it through the web form
> (e.g. a headless deploy), add `OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD` in the
> dashboard before first boot.

> **Security note for public deployments:** `POST /auth/setup` is
> unauthenticated while no password-bearing account exists, so an instance
> exposed before you reach the Create-admin form can be claimed by the first
> visitor. Pre-seed `OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD`, or complete setup
> promptly after the deploy goes live.

## Use your own IdP instead (OIDC)

Prefer to delegate login to GitHub / Google / Okta instead of built-in
accounts? Switch the provider after the initial deploy. HTTPS is provided
automatically by Render.

### GitHub OAuth (simplest to register)

1. Go to `github.com/settings/developers` → **New OAuth App**.
   - Homepage URL: `https://omniroute.drksci.com`
   - Authorization callback URL:
     `https://omniroute.drksci.com/auth/callback`
   - Click **Register application**, then **Generate a new client secret**.

2. In the Render dashboard, open the **omnigent** service → **Environment**
   and add / update these variables:

   | Variable | Value |
   |---|---|
   | `OMNIGENT_AUTH_PROVIDER` | `oidc` |
   | `OMNIGENT_OIDC_ISSUER` | `https://github.com` |
   | `OMNIGENT_OIDC_CLIENT_ID` | your GitHub OAuth client ID |
   | `OMNIGENT_OIDC_CLIENT_SECRET` | your GitHub OAuth client secret |
   | `OMNIGENT_OIDC_REDIRECT_URI` | `https://omniroute.drksci.com/auth/callback` |

   Also add `OMNIGENT_OIDC_COOKIE_SECRET` = a 64-hex-char value from
   `openssl rand -hex 32` — OIDC mode requires it and validates it as hex.

3. Click **Save Changes**. Render redeploys automatically. Visit the URL —
   you'll be redirected to GitHub to log in.

### Google Workspace

| Variable | Value |
|---|---|
| `OMNIGENT_AUTH_PROVIDER` | `oidc` |
| `OMNIGENT_OIDC_ISSUER` | `https://accounts.google.com` |
| `OMNIGENT_OIDC_CLIENT_ID` | `…apps.googleusercontent.com` |
| `OMNIGENT_OIDC_CLIENT_SECRET` | your client secret |
| `OMNIGENT_OIDC_REDIRECT_URI` | `https://omniroute.drksci.com/auth/callback` |
| `OMNIGENT_OIDC_ALLOWED_DOMAINS` | `example.com` (critical — see note below) |

> **Important:** Without `OMNIGENT_OIDC_ALLOWED_DOMAINS`, any Google account
> can log in when the OAuth consent screen is "External." Always restrict to
> your domain.

### Generic OIDC (Okta, Auth0, Keycloak, Entra ID)

Set `OMNIGENT_OIDC_ISSUER` to your IdP's base URL (the one that publishes
`/.well-known/openid-configuration`). The rest of the variables are the same
as above.

## Custom domain

In the Render dashboard, open the **omnigent** service → **Settings** →
**Custom Domains** → **Add Custom Domain**. Point your DNS CNAME at the
Render-assigned address. Render provisions a Let's Encrypt cert automatically.

Update `OMNIGENT_OIDC_REDIRECT_URI` to use the custom domain after DNS
propagates.

## OmniRoute and CheapInference

The blueprint keeps the upstream provider credential separate from the key
that the combined host uses to call OmniRoute:

1. Set `CHEAPERINFERENCE_API_KEY` on `ds-oa-omni-7k4m2q9v` to the `api_key`
   value from `cheaper-inference-default.json`. It is a Render secret and is
   never committed to Git.
2. Set `JWT_SECRET`, `API_KEY_SECRET`, and `INITIAL_PASSWORD` on that service
   to freshly generated secrets. After first boot, open its dashboard and
   create an OmniRoute inference key under **Endpoints**.
3. Put that generated inference key in the service's `OMNIROUTE_API_KEY`
   secret. The combined host config references the environment variable, so the key
   is not written into the repository.

Add the provider once OmniRoute is running, from its service shell:

```sh
omniroute providers add cheaperinference \
  --name cheap-default \
  --credential-env CHEAPERINFERENCE_API_KEY \
  --yes
```

Then verify it with `omniroute providers list`. Starter is the lowest-cost
bootstrap; move the combined service to a larger Render plan if long coding-agent
Responses calls cause restarts.

## Tiered model routing

The combined service enables periodic pricing and model-capability sync. Use
OmniRoute's `auto` channels when the caller wants a tier rather than one exact
provider:

| Request model | Behavior |
|---|---|
| `auto/coding:cheap` | Cheapest healthy coding-capable candidate |
| `auto/reasoning:pro` | A premium reasoning-capable candidate, selected by fit and health |
| `auto/chat:cheap` | Cheapest healthy chat-capable candidate |
| `auto/vision:cheap` | Cheapest healthy vision-capable candidate |

The `cheap` tier uses cost as its strongest routing signal, but still filters
for capability and excludes unhealthy or unavailable connections. The pricing
catalog is refreshed every six hours. Native models remain addressable by
their actual provider-qualified IDs, such as `deepseek/deepseek-chat` or
`openai/gpt-5.6`; the dashboard advertises both short and canonical prefixes.

For a semantic alias such as `astra`, define an explicit combo or model→combo
mapping after the live provider catalogs are available. OmniRoute cannot safely
assume that a similarly named model is an equivalent, and the equivalent may
change by capability or context window. For example, a deliberately authored
`astra-cheap` combo can target the approved DeepSeek model plus fallbacks and
use the `cost-optimized` or `auto` strategy. This preserves exact native model
names while making the equivalence policy auditable.

### Coding phases

Coding traffic should use a phase as well as a tier. The client or harness can
apply this policy with the model channel and optional request header:

| Phase | Model channel | Mode | Intent |
|---|---|---|---|
| Plan | `auto/reasoning:pro` | `quality` | Strong reasoning and architecture before edits |
| Work | `auto/coding:cheap` | `cheap` | Cheapest healthy coding-capable equivalent |
| Review | `auto/coding:pro` | `quality` | Higher-quality coding/review candidate |
| Quick fix | `auto/coding:fast` | `fast` | Low-latency implementation loop |

The mode is sent as `X-OmniRoute-Mode`. For example, an implementation call
uses `model: auto/coding:cheap` and `X-OmniRoute-Mode: cheap`; a planning call
uses `model: auto/reasoning:pro` and `X-OmniRoute-Mode: quality`. The channel
filters the candidate pool, while the mode controls the selection bias within
that pool. This gives “cheapest applicable model for this phase,” rather than
selecting the globally cheapest model regardless of capability.

The Render host also installs `omni-phase`, which applies the phase model at
launch time:

```sh
omni-phase plan codex       # heavy reasoning for architecture/planning
omni-phase work codex       # light, cheap coding model
omni-phase review claude    # quality-biased review model
omni-phase quick-fix agy    # fast implementation loop
```

The phase defaults can be overridden with `OMNIROUTE_PLAN_MODEL`,
`OMNIROUTE_WORK_MODEL`, `OMNIROUTE_REVIEW_MODEL`, and
`OMNIROUTE_QUICK_FIX_MODEL`. An explicit native `provider/model` supplied to
the regular `omnigent` command is never rewritten by this helper.

## Upgrading

Render redeploys automatically when a new commit lands on the connected branch
(if auto-deploy is enabled), or manually:

1. In the Render dashboard, open the **omnigent** service.
2. Click **Manual Deploy** → **Deploy latest commit**.

## Cost

Render: ~$7/month for the Starter web service + ~$6/month for the `basic-256mb`
managed Postgres. Total ~$13/month for a lightly loaded instance. Bump the
Postgres plan (`basic-1gb`, …) for more storage.

> **Note:** the web service needs a paid (Starter+) instance because of the
> persistent artifact disk, and Render's free Postgres plans expire — so a paid
> DB tier (`basic-256mb`) is the persistent default here.

> **Memory:** the Starter web service (512 MB) clears the server's ~512 MB–1 GB
> working set. Don't drop below it.

## Cheaper: SQLite on the disk (lite tier)

For a single-instance deploy you can skip the managed Postgres entirely and run
on **SQLite on the persistent disk** — it survives redeploys (the disk does) and
saves the ~$6/month DB cost. SQLite is a first-class backend; the tradeoff is
single-instance only (no horizontal scaling) and no managed backups, so keep
Postgres for production / multi-instance.

To use it, drop the `databases:` block from `render.yaml` and replace the
`DATABASE_URL` env var with a path on the disk:

```yaml
      - key: DATABASE_URL
        value: sqlite:////data/artifacts/chat.db
```

> **Or an external Neon Postgres.** You can point `DATABASE_URL` at a Neon
> database ([pg.new](https://pg.new)) instead of the managed Render one — e.g.
> to use Neon's free *persistent* tier rather than Render's paid DB. Tradeoff:
> you lose the integrated auto-provisioning (a separate signup + connection
> string) and add some cross-provider latency, so the managed Render Postgres
> stays the simpler default.
