import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [cloudflareTest({
    wrangler: { configPath: "./wrangler.jsonc" },
    // Synthetic test bindings only. Production digests are Worker secrets provisioned outside the repo.
    miniflare: {
      bindings: {
        ADMIN_TOKEN_DIGEST: "9f72ea0cf49536e3c66c787f705186df9a4378083753ae9536d65b3ad7fcddc4",
        WRITE_TOKEN_DIGEST: "02d449a31fbb267c8f352e9968a79e3e5fc95c1bbeaa502fd6454ebde5a4bedc",
      },
    },
  })],
});
