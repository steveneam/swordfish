# apps/hello - image bar per CHARTER Bucket 4: multi-stage, minimal base,
# non-root, HEALTHCHECK. Built ONLY in CI (hello-build.yml) -> GHCR; the dev
# laptop never builds images. amd64-only by design (the fleet is x86 Vultr).
FROM golang:1.26-alpine@sha256:ce864e7223ac17b1775e6fd0b4c0db580c2eb50e7953a427916379e4b92a1628 AS build
ARG VERSION=dev
WORKDIR /src
COPY go.mod main.go index.html ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /hello .

# scratch: no shell, no package manager, no CVE surface - just the binary.
# 65534 = nobody; the HEALTHCHECK exec's the binary's -check mode because
# there is no curl/wget in here to probe with.
FROM scratch
COPY --from=build /hello /hello
USER 65534:65534
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/hello", "-check"]
ENTRYPOINT ["/hello"]
