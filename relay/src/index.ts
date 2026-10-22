import { DurableObject } from "cloudflare:workers";

/** The single authoritative-state object; the relay protocol is implemented later. */
export class RelayObject extends DurableObject {
  override async fetch(): Promise<Response> {
    return new Response("not implemented", { status: 501 });
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const stub = env.RELAY.get(env.RELAY.idFromName("relay"));
    return stub.fetch(request);
  },
} satisfies ExportedHandler<Env>;
