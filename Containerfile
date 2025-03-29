# IMPORTANT! Before running this build, do the following:
#   # The dockerignore actually ignores plugin sources and other goodies (why?!)
#   find . -name .dockerignore -type f -delete
#   # Remove all the local node_modules to avoid copying all that stuff.
#   find . -name node_modules -type d -exec rm -rf {} +
#
# Run this from the top-level directory (not from a workspace). There's some top-level files
# that are required.
FROM registry.redhat.io/ubi9/nodejs-20:latest@sha256:70fd4c7e67b5e2378e5a12375ec39bf4f847ad1016e671fa3755716917e207d2 AS builder

WORKDIR /plugin-workspace

USER root

# TODO: It looks like some of the top-level files, maybe package.json and yarn.lock, are required
# for making the build work. Consider making this COPY statement a little more selective.
COPY . .

RUN find -name node_modules -type d -exec rm -rf {} +

ENV DIR_PLUGIN_REDHAT_ARGOCD="workspaces/redhat-argocd"
ENV DIR_PLUGIN_QUAY="workspaces/quay"
ENV DIR_PLUGIN_TEKTON="workspaces/tekton"
ENV DIR_PLUGIN_MSSV="workspaces/multi-source-security-viewer"
ENV PLUGINS_REDHAT_ARGOCD="argocd argocd-backend"
ENV PLUGINS_QUAY="quay quay-backend"
ENV PLUGINS_TEKTON="tekton"
ENV PLUGINS_MSSV="multi-source-security-viewer"
ENV PLUGINS_KEYS="REDHAT_ARGOCD QUAY TEKTON MSSV"
ENV PLUGINS_OUTPUT="/plugin-output"
ENV PLUGINS_WORKSPACE="/plugin-workspace"

# The recommended way of using yarn is via corepack. However, corepack is not included in the UBI
# image. Below we install corepack so we can install yarn.
# https://github.com/nodejs/corepack?tab=readme-ov-file#default-installs
# RPMs required for isolated-vm build
# https://github.com/laverdet/isolated-vm?tab=readme-ov-file#requirements
RUN \
    node --version && \
    npm install -g corepack && \
    corepack --version && \
    corepack enable yarn && \
    corepack use 'yarn@4' && \
    yarn --version && \
    mkdir -p $PLUGINS_OUTPUT && \
    dnf -y install python3 make gcc gcc-c++ zlib-devel brotli-devel openssl-devel

RUN set -ex && \
  for key in $PLUGINS_KEYS; do \
    dir_var="DIR_PLUGIN_${key}" && \
    plugins_var="PLUGINS_${key}" && \
    dir="${!dir_var}" && \
    plugins="${!plugins_var}" && \
    \
    echo "Building $dir" && \
    cd "$PLUGINS_WORKSPACE/$dir" && \
    yarn install --immutable && \
    yarn tsc && \
    \
    for plugin in $plugins; do \
      echo "Packaging $plugin" && \
      cd "$PLUGINS_WORKSPACE/$dir/plugins/$plugin" && \
      npx --yes @janus-idp/cli@latest package export-dynamic-plugin; \
    done && \
    \
    cd "$PLUGINS_WORKSPACE/$dir" && \
    echo "Exporting package $dir" && \
    npx --yes @janus-idp/cli@latest package package-dynamic-plugins --export-to "$PLUGINS_OUTPUT"; \
    mv "$PLUGINS_OUTPUT/index.json" "$PLUGINS_OUTPUT/$key-index.json"; \
  done && \
  cd $PLUGINS_OUTPUT && \
  npx --yes node-jq -c -s 'flatten' QUAY-index.json TEKTON-index.json MSSV-index.json REDHAT_ARGOCD-index.json > index.json

FROM scratch
COPY --from=builder /plugin-output /
