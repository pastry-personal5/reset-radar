# Protocol fixtures

Status: Active

Synthetic golden bytes shared by Swift Transport tests and TypeScript relay tests. The checked-in JSON files are the contract; `generate-fixtures.mjs` is a deterministic test utility for approved wire changes and is never loaded by either app or Worker runtime. Run `node Fixtures/Protocol/generate-fixtures.mjs` from the repository root, then review the byte changes and run both suites.

`envelope.json` and `pairing.json` pin cryptographic and canonical bytes. Ten `operation-*.json` files pin methods, paths, authority roles, request and success bodies, and ETags; twelve `error-*.json` files pin status, code, and body. Eight `scenario-*.json` files pin the owner-approved registration retry and collision, refresh-ID replay and collision, and sequence-overflow outcomes. Swift authenticates the sample envelope, while TypeScript validates only its outer metadata and hash. The fixture set contains only synthetic identifiers, tokens, keys, and usage data.

The M7-A fixture revision is `5d69907210abdf502a855136c6cd00900c0dde80314e7995886f40ce901d5c81`. It is SHA-256 over each `.json` filename, a NUL byte, and its exact file bytes, in lexicographic filename order. The relay implementation must review and record any change to these files against both Swift and TypeScript consumers.
