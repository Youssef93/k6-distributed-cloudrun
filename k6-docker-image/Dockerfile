# Build the k6 binary with the extension
FROM golang:latest

USER root

RUN mkdir /app
WORKDIR /app

RUN go install go.k6.io/xk6/cmd/xk6@latest

COPY . .

# Install extensions
RUN xk6 build \
    --with github.com/grafana/xk6-output-timescaledb \
    --output /k6