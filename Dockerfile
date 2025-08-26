FROM node:16.13-alpine3.12 AS base

# Build arguments (these will be available during build but not in final image)
ARG INFRACOST_API_KEY
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AZURE_CLIENT_ID
ARG AZURE_CLIENT_SECRET
ARG AZURE_TENANT_ID
ARG GCP_API_KEY

# Only set non-sensitive environment variables that are needed at runtime
ENV POSTGRES_HOST=127.0.0.1
ENV POSTGRES_DB=cloud_pricing
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres
ENV PGPASSWORD=postgres
ENV DISABLE_TELEMETRY=TRUE

# Install dependencies (curl needed for scrapers)
RUN apk add --no-cache postgresql su-exec curl

# Copy application files
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --production && npm install
COPY . .
RUN npm run build

# Create user
RUN addgroup -g 1001 -S infracost && \
    adduser -u 1001 -S infracost -G infracost && \
    chown -R infracost:infracost /usr/src/app

# Setup PostgreSQL
RUN mkdir /run/postgresql && \
    chown postgres:postgres /run/postgresql && \
    su-exec postgres initdb -D /var/lib/postgresql/data

# Stage for downloading from Infracost API
FROM base AS download
# Set sensitive environment variables only for this build stage
ARG INFRACOST_API_KEY
ENV INFRACOST_API_KEY=${INFRACOST_API_KEY}
RUN su-exec postgres pg_ctl start -D /var/lib/postgresql/data && \
    su-exec postgres createdb cloud_pricing && \
    su-exec infracost npm run job:init && \
    rm -f /usr/src/app/data/products/products.csv.gz && \
    su-exec postgres pg_ctl stop -D /var/lib/postgresql/data

# Stage for scraping from cloud providers
FROM base AS scrape
# Set cloud provider credentials only for this build stage
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AZURE_CLIENT_ID
ARG AZURE_CLIENT_SECRET
ARG AZURE_TENANT_ID
ARG GCP_API_KEY
ENV AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
ENV AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
ENV AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
ENV AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
ENV AZURE_TENANT_ID=${AZURE_TENANT_ID}
ENV GCP_API_KEY=${GCP_API_KEY}
RUN su-exec postgres pg_ctl start -D /var/lib/postgresql/data && \
    su-exec postgres createdb cloud_pricing && \
    su-exec infracost npm run db:setup && \
    echo "=====================================" && \
    echo "Scraping pricing data from cloud providers..." && \
    echo "This may take 10-30 minutes depending on API rate limits" && \
    echo "=====================================" && \
    su-exec infracost npm run data:scrape || echo "Warning: Some scrapers may have failed, continuing..." && \
    echo "=====================================" && \
    echo "Scraping complete. Dumping to CSV..." && \
    echo "=====================================" && \
    su-exec infracost npm run data:dump -- --out=/usr/src/app/data/products/products.csv.gz && \
    ls -lah /usr/src/app/data/products/ && \
    rm -f /usr/src/app/data/products/products.csv.gz && \
    su-exec postgres pg_ctl stop -D /var/lib/postgresql/data

# Final stage for download path - inherits from download but clears secrets
FROM download AS final-download

# Clear all sensitive environment variables
ENV INFRACOST_API_KEY=

# Copy entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENV NODE_ENV=production
EXPOSE 4000
ENTRYPOINT ["/docker-entrypoint.sh"]

# Final stage for scrape path - inherits from scrape but clears secrets
FROM scrape AS final-scrape

# Clear all sensitive environment variables
ENV AWS_ACCESS_KEY_ID=
ENV AWS_SECRET_ACCESS_KEY=
ENV AZURE_CLIENT_ID=
ENV AZURE_CLIENT_SECRET=
ENV AZURE_TENANT_ID=
ENV GCP_API_KEY=

# Copy entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENV NODE_ENV=production
EXPOSE 4000
ENTRYPOINT ["/docker-entrypoint.sh"]

# Default final stage (uses scrape path)
FROM final-scrape AS final