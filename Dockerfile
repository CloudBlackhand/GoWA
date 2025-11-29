############################
# STEP 1 build executable binary
############################
FROM golang:1.24-alpine3.20 AS builder
RUN apk update && apk add --no-cache gcc musl-dev gcompat
WORKDIR /whatsapp
# Copy go mod files first for better caching
COPY ./src/go.mod ./src/go.sum ./
# Fetch dependencies.
RUN go mod download
# Copy source code
COPY ./src .

# Build the binary with optimizations
RUN go build -a -ldflags="-w -s" -o /app/whatsapp

#############################
## STEP 2 build a smaller image
#############################
FROM alpine:3.20
RUN apk add --no-cache ffmpeg tzdata
ENV TZ=UTC
WORKDIR /app
# Copy compiled from builder.
COPY --from=builder /app/whatsapp /app/whatsapp
# Create necessary directories
RUN mkdir -p /app/storages /app/statics/media /app/statics/qrcode /app/statics/senditems
# Run the binary.
ENTRYPOINT ["/app/whatsapp"]

CMD [ "rest" ]

