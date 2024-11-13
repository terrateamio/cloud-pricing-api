FROM node:16.13-alpine3.12
ARG INFRACOST_API_KEY

ENV POSTGRES_HOST=127.0.0.1
ENV POSTGRES_DB=cloud_pricing
ENV POSTGRES_USER=postgres
ENV DISABLE_TELEMETRY=TRUE

RUN apk add git postgresql su-exec jq curl openssh

COPY ./ /usr/src/app
WORKDIR /usr/src/app

RUN npm install --production \
  && npm install
RUN npm run build

RUN addgroup -g 1001 -S infracost && \
  adduser -u 1001 -S infracost -G infracost && \
  chown -R infracost:infracost /usr/src/app

RUN mkdir /run/postgresql
RUN chown postgres:postgres /run/postgresql
RUN su-exec postgres initdb -D /var/lib/postgresql/data
RUN su-exec postgres pg_ctl start -D /var/lib/postgresql/data && \
    su-exec postgres createdb cloud_pricing && \
    su-exec infracost npm run job:init && \
    rm -f /usr/src/app/data/products/products.csv.gz && \
    su-exec postgres pg_ctl stop -D /var/lib/postgresql/data

COPY docker-entrypoint.sh /docker-entrypoint.sh
ENV NODE_ENV=production
EXPOSE 4000
ENTRYPOINT ["/docker-entrypoint.sh"]
