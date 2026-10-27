# Deploying the docs site (Dokploy)

The site is deployed on [Dokploy](https://dokploy.com) as **two applications**,
one per release channel, each building `docs-site/Dockerfile` from its own
branch:

| Application | Branch | Domain | Build arg |
|---|---|---|---|
| `anoshell-docs` | `main` | `anoshell.anorebel.net` | `DOCS_VERSION=main` |
| `anoshell-docs-dev` | `dev` | `dev.anoshell.anorebel.net` | `DOCS_VERSION=dev` |

The `dev` branch has to exist before its application can build (the
repository only has `main` today).

## Application settings (both)

- **Source:** the AnoShell Git repository, the branch above, **auto-deploy on
  push** enabled.
- **Build type:** Dockerfile.
  - Dockerfile path: `docs-site/Dockerfile`
  - Build context / root: the repository root (`.`): the pages are the
    repository's `docs/`, so the image must see both folders.
  - Build argument: `DOCS_VERSION` as in the table. It is read at build time:
    links from a page into the repository point at that branch.
- **Port:** the container listens on `3000`.
- **Domain:** the domain above, HTTPS with Let's Encrypt (Dokploy's
  certificate resolver), container port `3000`.
- **Health check:** `GET /api/health` → `200 {"status":"healthy","version":…}`
  after reading the content index; `503` otherwise. The image has the same
  check as a Docker `HEALTHCHECK`, so Dokploy's rolling deploys wait for it.
- **Environment:** nothing is required. Optional:
  `NUXT_PUBLIC_DOCS_VERSIONS` (JSON) replaces the version switcher's list at
  runtime, e.g. to add a third channel without a rebuild.
- **Secrets:** none, at build or run time.

## Checking a build locally

```sh
docker build -f docs-site/Dockerfile --build-arg DOCS_VERSION=main -t anoshell-docs .
docker run --rm -p 3000:3000 anoshell-docs
curl -f http://localhost:3000/api/health
```

## After the first deploy

```sh
curl -f https://anoshell.anorebel.net/api/health
curl -f https://dev.anoshell.anorebel.net/api/health
```

The header's version switcher moves between the two; it asks the other site
whether the page exists there (`/api/page-exists`) before sending you to it.
