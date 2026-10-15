# The AnoShell documentation site.
#
# Built from the repository root, because the pages are the repository's docs/:
#
#   docker build -f docs-site/Dockerfile --build-arg DOCS_VERSION=main .
#
# One image per version: DOCS_VERSION=main (Stable) or dev (Development) names
# the branch the image was built from, which is also the branch its links into
# the repository point at. No secrets are needed, at build or at run time.

FROM node:24.22.0-bookworm-slim AS build

# Bun installs; Node runs the build, because the content layer indexes the
# pages with node:sqlite.
COPY --from=oven/bun:1.4.3-debian /usr/local/bin/bun /usr/local/bin/bun

WORKDIR /src/docs-site
COPY docs-site/package.json docs-site/bun.lock ./
# --ignore-scripts: postinstall (nuxt prepare) needs the sources; the build prepares anyway.
RUN bun install --frozen-lockfile --ignore-scripts

# Named paths, not docs-site/ whole: the legacy builder ignores
# Dockerfile.dockerignore and would copy a local node_modules over the install.
COPY docs/ /src/docs/
COPY docs-site/nuxt.config.ts docs-site/content.config.ts docs-site/tsconfig.json ./
COPY docs-site/app/ app/
COPY docs-site/lib/ lib/
COPY docs-site/server/ server/

ARG DOCS_VERSION=main
ENV DOCS_VERSION=$DOCS_VERSION
RUN bun run build

FROM node:24.22.0-bookworm-slim

WORKDIR /app
# The server writes its content index under .data on first start.
RUN chown node:node /app
USER node

COPY --from=build --chown=node:node /src/docs-site/.output ./.output

ARG DOCS_VERSION=main
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    DOCS_VERSION=$DOCS_VERSION

EXPOSE 3000
CMD ["node", ".output/server/index.mjs"]
