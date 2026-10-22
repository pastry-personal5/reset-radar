import { SELF } from "cloudflare:test";
import { expect, it } from "vitest";
import fixture from "../../Fixtures/Protocol/scaffold.json";

it("returns not implemented until the protocol lands", async () => {
  const response = await SELF.fetch("https://relay.invalid/");
  expect(response.status).toBe(501);
});

it("reads the shared protocol fixture", () => {
  expect(fixture.marker).toBe("reset-radar-scaffold");
});
