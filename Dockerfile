# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.44.8
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH \
    PUB_CACHE=/opt/pub-cache

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates curl git unzip xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
  && tar -xf /tmp/flutter.tar.xz -C /opt \
  && rm /tmp/flutter.tar.xz \
  && git config --global --add safe.directory /opt/flutter \
  && flutter config --no-analytics --no-cli-animations \
  && flutter precache --web

WORKDIR /src

# resolve dependencies first so a source-only change reuses this layer
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
RUN flutter pub get

COPY . .
# symbol maps are debug only, and dart2js never loads the wasm renderers
RUN flutter build web --release --no-web-resources-cdn \
  && find build/web -name '*.symbols' -delete \
  && rm -rf build/web/canvaskit/skwasm* build/web/canvaskit/wimp* \
            build/web/canvaskit/experimental_webparagraph

# COPY only, so buildx can assemble any architecture without emulating a RUN
FROM nginx:1.27-alpine AS serve

COPY docker/nginx.conf docker/security-headers.conf /etc/nginx/
COPY --from=build /src/build/web /srv/web-crypt

# unprivileged, so nginx writes its pid and temp files under /tmp
USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
