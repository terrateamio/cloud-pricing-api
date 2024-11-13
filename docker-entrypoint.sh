#!/usr/bin/env sh

su-exec postgres pg_ctl start -D /var/lib/postgresql/data
exec su-exec infracost npm run start
