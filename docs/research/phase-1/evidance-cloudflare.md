# Evidence

Status: Deferred

This note records the owner-present synthetic Cloudflare relay smoke-test outcome. The relay spike remains deferred without a scheduled date.

## Record

Date: 2026-10-20

Account name: Account-0000

Wrangler: 4.151.2

Remote smoke test: Successful. The owner completed the reviewed `smoke:remote` run against the deployed `workers.dev` origin. The synthetic health and closed-route checks passed, redirects were rejected, and no provider data or credentials were sent.

```
npx --yes wrangler@4.151.2 login
```

