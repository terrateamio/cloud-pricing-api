#!/usr/bin/env sh

su-exec postgres pg_ctl start -D /var/lib/postgresql/data
exec su-exec infracost env NODE_OPTIONS="--max-old-space-size=512" npm run start
