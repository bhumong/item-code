FROM golang:1.26.5-alpine AS backend-base
WORKDIR /src/backend
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ ./

FROM backend-base AS development-build
RUN CGO_ENABLED=0 go build -o /app/backend .

FROM alpine:3.20 AS runtime
RUN apk add --no-cache ca-certificates
WORKDIR /app
EXPOSE 8090
ENTRYPOINT ["/app/backend", "serve", "--http=0.0.0.0:8090"]

FROM runtime AS development
COPY --from=development-build /app/backend /app/backend

FROM backend-base AS production-build
COPY frontend/build/web/ ./web/dist/
RUN CGO_ENABLED=0 go build -o /app/backend .

FROM runtime AS production
COPY --from=production-build /app/backend /app/backend

FROM scratch AS binary
COPY --from=production-build /app/backend /ocr-search
