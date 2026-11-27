// End to end against the deployed branch: two throwaway phones (and a
// stranger) exercise Managed Auth, the API Function, Postgres, Realtime and
// object storage, then everything they made is deleted.
//
//   npm test            (reads .env.local from `neon env pull`)

import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import pg from "pg";

const AUTH = process.env.NEON_AUTH_BASE_URL!;
const API =
  process.env.AUGUST_API_URL ??
  `https://${process.env.NEON_BRANCH_ID}-api${process.env.NEON_FUNCTION_HOST_SUFFIX}`;
// Native apps send no Origin; Managed Auth wants a trusted one on sign-up.
const ORIGIN = "http://localhost";

let passed = 0;
let pushOn = false;
async function step(name: string, fn: () => Promise<void>) {
  const t = Date.now();
  await fn();
  passed++;
  console.log(`  ✓ ${name} (${Date.now() - t} ms)`);
}

class Phone {
  cookie = "";
  jwt = "";
  id = "";
  readonly email = `e2e-${randomUUID()}@august.test`;
  readonly password = randomBytes(24).toString("base64url");
  readonly name: string;
  constructor(name: string) {
    this.name = name;
  }

  private take(res: Response) {
    for (const c of res.headers.getSetCookie()) {
      const m = /^([^=]*session_token)=([^;]*)/.exec(c);
      if (m) this.cookie = `${m[1]}=${m[2]}`;
    }
  }

  async auth(path: string, body?: unknown): Promise<Response> {
    const res = await fetch(`${AUTH}${path}`, {
      method: body ? "POST" : "GET",
      headers: { origin: ORIGIN, cookie: this.cookie, ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    this.take(res);
    return res;
  }

  async signUp() {
    const res = await this.auth("/sign-up/email", { email: this.email, password: this.password, name: "august" });
    assert.equal(res.status, 200, await res.clone().text());
    this.id = ((await res.json()) as { user: { id: string } }).user.id;
    await this.token();
  }

  async token() {
    const res = await this.auth("/token");
    assert.equal(res.status, 200);
    this.jwt = ((await res.json()) as { token: string }).token;
  }

  async api<T = any>(method: string, path: string, body?: unknown, status = 200): Promise<T> {
    const res = await fetch(`${API}${path}`, {
      method,
      headers: { authorization: `Bearer ${this.jwt}`, ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    assert.equal(res.status, status, `${method} ${path}: ${text}`);
    return JSON.parse(text) as T;
  }
}

const rohan = new Phone("Rohan");
const shruti = new Phone("Shruti");
const stranger = new Phone("Neha");

console.log(`August e2e against ${new URL(API).host}`);
try {
  await step("API is up with Realtime and storage", async () => {
    const res = await fetch(API);
    const health = (await res.json()) as Record<string, unknown>;
    assert.equal(health.ok, true);
    assert.equal(health.realtime, true);
    assert.equal(health.storage, true);
    pushOn = health.push === true;
    console.log(`    push ${pushOn ? "on" : "off (no backend/firebase-sa.json)"}`);
  });

  await step("Auth: sign up three phones and mint JWTs", async () => {
    await Promise.all([rohan.signUp(), shruti.signUp(), stranger.signUp()]);
  });

  await step("Auth: session, sign out, sign back in", async () => {
    const s = (await (await rohan.auth("/get-session")).json()) as { user: { id: string } };
    assert.equal(s.user.id, rohan.id);
    assert.equal((await rohan.auth("/sign-out", {})).status, 200);
    rohan.cookie = "";
    assert.equal(await (await rohan.auth("/get-session")).text(), "null");
    const res = await rohan.auth("/sign-in/email", { email: rohan.email, password: rohan.password });
    assert.equal(res.status, 200);
    await rohan.token();
  });

  await step("API refuses a missing or forged token", async () => {
    assert.equal((await fetch(`${API}/v1/me`)).status, 401);
    const forged = rohan.jwt.slice(0, -4) + (rohan.jwt.endsWith("AAAA") ? "BBBB" : "AAAA");
    assert.equal((await fetch(`${API}/v1/me`, { headers: { authorization: `Bearer ${forged}` } })).status, 401);
  });

  const keyA = randomBytes(32).toString("base64");
  const keyB = randomBytes(32).toString("base64");
  await step("Postgres: name and public key", async () => {
    const me = await rohan.api("PUT", "/v1/me", { name: "Rohan", pubkey: keyA });
    assert.equal(me.name, "Rohan");
    assert.equal(me.partner, null);
    await shruti.api("PUT", "/v1/me", { name: "Shruti", pubkey: keyB });
  });

  await step("Pairing: an invite code, joined from the other phone", async () => {
    const { code } = await rohan.api("POST", "/v1/invites");
    assert.match(code, /^[A-Z2-9]{6}$/);
    await shruti.api("POST", "/v1/join", { code: "ZZZZZZ" }, 404);
    const joined = await shruti.api("POST", "/v1/join", { code: code.toLowerCase() });
    assert.equal(joined.partner.name, "Rohan");
    assert.equal(joined.partner.pubkey, keyA);
    const me = await rohan.api("GET", "/v1/me");
    assert.equal(me.partner.pubkey, keyB);
    assert.equal(me.coupleId, joined.coupleId);
    await stranger.api("POST", "/v1/join", { code }, 404); // used up
  });

  await step("Mail: a stranger can't write to the couple", async () => {
    await stranger.api("POST", "/v1/mail", { id: randomUUID(), kind: "msg", body: "x" }, 409);
  });

  await step("Realtime: mail arrives live over the WebSocket", async () => {
    const ws = new WebSocket(`${API.replace(/^http/, "ws")}/v1/live?token=${encodeURIComponent(rohan.jwt)}`);
    const id = randomUUID();
    const sealed = randomBytes(64).toString("base64");
    const got = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("no live mail in 20 s")), 20_000);
      ws.addEventListener("message", (e) => {
        const m = JSON.parse(String(e.data));
        if (m.type === "mail" && m.id === id) {
          clearTimeout(timer);
          resolve(m);
        }
      });
      ws.addEventListener("error", () => reject(new Error("socket error")));
    });
    await new Promise((r) => ws.addEventListener("open", r));
    // Let the subscription go live before sending.
    await new Promise<void>((resolve) => {
      const t = setTimeout(resolve, 5000);
      ws.addEventListener("message", (e) => {
        if (JSON.parse(String(e.data)).status === "live") {
          clearTimeout(t);
          resolve();
        }
      });
    });
    const sent = await shruti.api("POST", "/v1/mail", { id, kind: "msg", body: sealed });
    assert.equal(sent.kind, "committed");
    assert.equal(sent.pushed, pushOn ? "no-token" : "disabled");
    assert.match(sent.txid, /^\d+$/);
    const m = await got;
    assert.equal(m.sender, shruti.id);
    assert.equal(m.body, sealed);
    ws.close();
    // Sent twice (a retry) is stored once.
    assert.equal((await shruti.api("POST", "/v1/mail", { id, kind: "msg", body: sealed })).kind, "duplicate");
  });

  await step("Push: a token is kept, and a dead one is dropped", async () => {
    await rohan.api("PUT", "/v1/me", { fcm: "not-a-real-token" });
    const [t1, t2] = [randomUUID(), randomUUID()];
    const r = await shruti.api("POST", "/v1/mail", { id: t1, kind: "typing", body: "x" });
    assert.equal(r.pushed, "skipped", "typing never pushes");
    const m = await shruti.api("POST", "/v1/mail", { id: t2, kind: "moment", body: "x" });
    // FCM rejects a made-up token as invalid; the API reports it.
    assert.ok(pushOn ? ["unregistered", "failed"].includes(m.pushed) : m.pushed === "disabled", m.pushed);
    await rohan.api("PUT", "/v1/me", { fcm: "" });
    await rohan.api("POST", "/v1/mail/ack", { ids: [t1, t2] });
  });

  await step("Widget: a wake reaches only a phone with a widget", async () => {
    assert.equal((await shruti.api("POST", "/v1/wake")).pushed, "no-widget");
    await rohan.api("PUT", "/v1/me", { widget: "yes" }, 400);
    await rohan.api("PUT", "/v1/me", { widget: true, fcm: "not-a-real-token" });
    const woke = await shruti.api("POST", "/v1/wake");
    assert.ok(pushOn ? ["unregistered", "failed"].includes(woke.pushed) : woke.pushed === "disabled", woke.pushed);
    await stranger.api("POST", "/v1/wake", undefined, 409);
    await rohan.api("PUT", "/v1/me", { widget: false, fcm: "" });
    assert.equal((await shruti.api("POST", "/v1/wake")).pushed, "no-widget");
  });

  await step("Mail: the background check lists it, the ack deletes it", async () => {
    const box = await rohan.api<{ id: string }[]>("GET", "/v1/mail");
    assert.equal(box.length, 1);
    assert.deepEqual(await shruti.api("POST", "/v1/mail/ack", { ids: [box[0]!.id] }), { deleted: 0 }); // not hers
    assert.deepEqual(await rohan.api("POST", "/v1/mail/ack", { ids: [box[0]!.id] }), { deleted: 1 });
    assert.equal((await rohan.api<unknown[]>("GET", "/v1/mail")).length, 0);
  });

  await step("Object storage: sealed media up, down, then deleted", async () => {
    const blob = randomBytes(200_000);
    const { key, url } = await rohan.api("POST", "/v1/blobs");
    const put = await fetch(url, { method: "PUT", body: blob });
    assert.equal(put.status, 200, await put.text());
    const got = await shruti.api("GET", `/v1/blobs?key=${encodeURIComponent(key)}`);
    const down = await fetch(got.url);
    assert.equal(down.status, 200);
    assert.ok(Buffer.from(await down.arrayBuffer()).equals(blob));
    await stranger.api("GET", `/v1/blobs?key=${encodeURIComponent(key)}`, undefined, 409);
    await shruti.api("DELETE", `/v1/blobs?key=${encodeURIComponent(key)}`);
    assert.equal((await fetch(got.url)).status, 404);
  });

  await step("Re-pair: Rohan's new phone takes the old one's place", async () => {
    const newPhone = new Phone("Rohan 2");
    await newPhone.signUp();
    await newPhone.api("PUT", "/v1/me", { name: "Rohan", pubkey: randomBytes(32).toString("base64") });
    const { code } = await newPhone.api("POST", "/v1/invites");
    const after = await shruti.api("POST", "/v1/join", { code });
    assert.equal(after.partner.id, newPhone.id);
    assert.equal((await rohan.api("GET", "/v1/me")).partner, null);
    await cleanup([newPhone]);
  });

  await step("Unpair removes the couple", async () => {
    await shruti.api("POST", "/v1/unpair");
    assert.equal((await shruti.api("GET", "/v1/me")).partner, null);
  });

  console.log(`\n${passed} steps passed`);
} finally {
  await cleanup([rohan, shruti, stranger]);
}

// Deletes the throwaway accounts and their rows.
async function cleanup(phones: Phone[]) {
  const ids = phones.map((p) => p.id).filter(Boolean);
  if (!ids.length) return;
  const db = new pg.Client({ connectionString: process.env.DATABASE_URL_UNPOOLED });
  await db.connect();
  await db.query(
    "delete from couples where id in (select couple_id from members where user_id = any($1))",
    [ids],
  );
  await db.query("delete from members where user_id = any($1)", [ids]);
  await db.query('delete from neon_auth."user" where id::text = any($1)', [ids]);
  await db.end();
}

// Keep-alive sockets (fetch, Realtime) would hold the process open.
process.exit(passed === 13 ? 0 : 1);
