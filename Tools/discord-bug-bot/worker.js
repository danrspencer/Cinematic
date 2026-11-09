// Cinematic bug bot: a Discord /bug command that files a GitHub issue.
// Runs as a Cloudflare Worker (Discord "interactions endpoint"), no server.
// Paste this whole file into the Worker's editor. Setup: README.md.
//
// Secrets (Worker > Settings > Variables and Secrets):
//   DISCORD_PUBLIC_KEY  Discord app's public key (General Information)
//   DISCORD_APP_ID      Discord app's application ID
//   GITHUB_APP_ID       the org's GitHub App ID (issues show as opened by the app's bot)
//   GITHUB_APP_KEY      that app's private key: the whole .pem file, pasted as is
//   (or GITHUB_TOKEN    a personal token instead: issues then show that person's account)
// Optional plain variables:
//   GITHUB_REPO         default "sapo-wow-dev/Cinematic"
//   SHOW_REPORTER       "1" puts the reporter's Discord name in the issue (public!)
// Forum "Open" tags (optional, README step 6):
//   DISCORD_BOT_TOKEN   secret: the Discord bot's token
//   BUG_FORUM_ID        plain: the bug forum channel's ID (closed tag: Fixed)
//   REQUEST_FORUM_ID    plain: the request forum channel's ID (closed tag: Done)

const COOLDOWN_SECONDS = 300 // one report per player per 5 minutes
const LABELS = ["bug", "from-discord"]

const CLIENTS = {
  retail: "Retail",
  classic_era: "Classic Era",
  forever: "WoW Forever",
  other: "Other / not sure",
}

// Best effort: lives as long as the Worker instance, so a spammer can
// sometimes slip past it; GitHub's own limits are the backstop.
const lastReport = new Map()

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") return new Response("Cinematic bug bot is running.")

    const body = await request.text()
    if (!(await verify(request, body, env.DISCORD_PUBLIC_KEY))) {
      return new Response("Bad signature", { status: 401 })
    }
    const interaction = JSON.parse(body)

    // 1: Discord checking the endpoint is ours
    if (interaction.type === 1) return json({ type: 1 })

    // 2: someone typed /bug -> open the form
    if (interaction.type === 2 && interaction.data.name === "bug") {
      const client = interaction.data.options?.find((o) => o.name === "client")?.value || "other"
      return json({ type: 9, data: bugForm(client) })
    }

    // 5: the form was sent -> answer "working on it" now, file the issue after
    if (interaction.type === 5 && interaction.data.custom_id.startsWith("bug:")) {
      const user = interaction.member?.user || interaction.user
      const wait = cooldownLeft(user.id)
      if (wait > 0) {
        return reply(`Thanks! You can send another report in ${Math.ceil(wait / 60)} min.`)
      }
      lastReport.set(user.id, Date.now())
      ctx.waitUntil(fileIssue(interaction, user, env))
      return json({ type: 5, data: { flags: 64 } }) // "thinking...", only they see it
    }

    return reply("Sorry, I don't know that one.")
  },

  // Cron trigger (Worker > Settings > Triggers): tag new bug forum posts.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(tagNewBugPosts(env))
  },
}

// ---- Forums: every new post gets the "Open" tag ----
// A Worker can't hear "new post" events live (that needs an always-on bot),
// so the cron looks every few minutes. A post is left alone once it has Open
// or one of its forum's closed tags, so swapping Open for Fixed/Done sticks.
// Posts older than NEW_POST_HOURS are never touched, so old posts are not
// tagged in bulk.
const OPEN_TAG = "Open"
const FORUMS = [
  // idVar: the Worker variable holding the forum's channel ID
  // closed: tags that mean "finished" (add more, e.g. "Won't fix", if the forum gets them)
  { idVar: "BUG_FORUM_ID", closed: ["Fixed"] },
  { idVar: "REQUEST_FORUM_ID", closed: ["Done"] },
]
const NEW_POST_HOURS = 24

async function tagNewBugPosts(env) {
  if (!env.DISCORD_BOT_TOKEN) return
  const activeByGuild = new Map() // one active-threads fetch per server
  for (const { idVar, closed } of FORUMS) {
    const forumId = env[idVar]
    if (!forumId) continue
    try {
      const forum = await discord(env, "GET", `/channels/${forumId}`)
      const byName = (name) => (forum.available_tags || []).find((t) => t.name.toLowerCase() === name.toLowerCase())
      const open = byName(OPEN_TAG)
      if (!open) {
        console.log(`Forum ${forum.name} has no "${OPEN_TAG}" tag`)
        continue
      }
      const skip = [open, ...closed.map(byName)].filter(Boolean).map((t) => t.id)

      if (!activeByGuild.has(forum.guild_id)) {
        activeByGuild.set(forum.guild_id, (await discord(env, "GET", `/guilds/${forum.guild_id}/threads/active`)).threads)
      }
      const since = Date.now() - NEW_POST_HOURS * 3600 * 1000
      let seen = 0, tagged = 0
      for (const post of activeByGuild.get(forum.guild_id)) {
        if (post.parent_id !== forumId || snowflakeTime(post.id) < since) continue
        seen++
        const applied = post.applied_tags || []
        if (applied.some((id) => skip.includes(id)) || applied.length >= 5) continue // 5 = Discord's max
        try {
          await discord(env, "PATCH", `/channels/${post.id}`, { applied_tags: [...applied, open.id] })
          tagged++
        } catch (err) {
          console.log(`Couldn't tag post ${post.id}:`, err.message)
        }
      }
      console.log(`${forum.name}: ${seen} post(s) from the last ${NEW_POST_HOURS}h, tagged ${tagged}`)
    } catch (err) {
      console.log(`Tagging ${idVar} failed:`, err.message)
    }
  }
}

async function discord(env, method, path, body) {
  const res = await fetch(`https://discord.com/api/v10${path}`, {
    method,
    headers: {
      Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`,
      "Content-Type": "application/json",
      "X-Audit-Log-Reason": "New bug post: Open tag",
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${await res.text()}`)
  return res.json()
}

// Discord IDs carry their creation time (ms since 2015).
function snowflakeTime(id) {
  return Number(BigInt(id) >> 22n) + 1420070400000
}

function bugForm(client) {
  const field = (id, label, style, max, required, placeholder) => ({
    type: 1,
    components: [{ type: 4, custom_id: id, label, style, max_length: max, required, placeholder }],
  })
  return {
    custom_id: `bug:${client}`,
    title: `Bug report (${CLIENTS[client] || "Other"})`,
    components: [
      field("title", "Short summary", 1, 100, true, "e.g. Minimap stays hidden after a flight"),
      field("version", "Cinematic version", 1, 30, false, "Shown at the top of /cine"),
      field("what", "What happened? (posted publicly on GitHub)", 2, 2000, true, "What you saw, and what you expected"),
      field("steps", "How can we make it happen again?", 2, 1500, false, "1. ...\n2. ..."),
      field("errors", "Lua error text, if any", 2, 1500, false, "Paste from BugSack or the error window"),
    ],
  }
}

async function fileIssue(interaction, user, env) {
  const repo = env.GITHUB_REPO || "sapo-wow-dev/Cinematic"
  const client = interaction.data.custom_id.slice(4)
  const v = {}
  for (const row of interaction.data.components) {
    for (const c of row.components) v[c.custom_id] = (c.value || "").trim()
  }

  const lines = [`**Client:** ${CLIENTS[client] || client}`]
  if (v.version) lines.push(`**Cinematic version:** ${clean(v.version)}`)
  lines.push("", "### What happened", clean(v.what))
  if (v.steps) lines.push("", "### Steps", clean(v.steps))
  if (v.errors) lines.push("", "### Lua error", "```", v.errors.replace(/```/g, "'''"), "```")
  lines.push("", "---")
  lines.push(env.SHOW_REPORTER === "1"
    ? `_Sent from Discord by ${clean(user.global_name || user.username)}_`
    : "_Sent from Discord with /bug_")

  let message
  try {
    const token = await githubToken(env, repo)
    const res = await fetch(`https://api.github.com/repos/${repo}/issues`, {
      method: "POST",
      headers: ghHeaders(token),
      body: JSON.stringify({ title: clean(v.title), body: lines.join("\n"), labels: LABELS }),
    })
    if (res.ok) {
      const issue = await res.json()
      message = `Thanks! Your report is issue #${issue.number}: <${issue.html_url}>\nYou can follow it there.`
    } else {
      console.log("GitHub said", res.status, await res.text())
      message = "Sorry, I couldn't file that. Please post it in the bug channel instead."
      lastReport.delete(user.id)
    }
  } catch (err) {
    console.log("GitHub request failed", err)
    message = "Sorry, I couldn't reach GitHub. Please try again in a bit."
    lastReport.delete(user.id)
  }

  await fetch(`https://discord.com/api/v10/webhooks/${env.DISCORD_APP_ID}/${interaction.token}/messages/@original`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content: message, allowed_mentions: { parse: [] } }),
  })
}

function ghHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "User-Agent": "cinematic-bug-bot",
    "X-GitHub-Api-Version": "2022-11-28",
  }
}

// GitHub App: sign a short JWT with the app's key, find the app's install on
// the repo, and trade the JWT for an hour-long install token (kept till near expiry).
let appToken = null
async function githubToken(env, repo) {
  if (!env.GITHUB_APP_ID || !env.GITHUB_APP_KEY) return env.GITHUB_TOKEN
  if (appToken && appToken.expires - Date.now() > 5 * 60 * 1000) return appToken.token
  const jwt = await appJwt(env.GITHUB_APP_ID, env.GITHUB_APP_KEY)
  const inst = await fetch(`https://api.github.com/repos/${repo}/installation`, { headers: ghHeaders(jwt) })
  if (!inst.ok) throw new Error(`installation lookup ${inst.status}: ${await inst.text()}`)
  const { id } = await inst.json()
  const res = await fetch(`https://api.github.com/app/installations/${id}/access_tokens`, {
    method: "POST",
    headers: ghHeaders(jwt),
  })
  if (!res.ok) throw new Error(`install token ${res.status}: ${await res.text()}`)
  const data = await res.json()
  appToken = { token: data.token, expires: Date.parse(data.expires_at) }
  return appToken.token
}

async function appJwt(appId, pem) {
  const now = Math.floor(Date.now() / 1000)
  const b64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_")
  const enc = (obj) => b64url(new TextEncoder().encode(JSON.stringify(obj)))
  const data = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({ iat: now - 60, exp: now + 540, iss: String(appId) })}`
  const key = await crypto.subtle.importKey("pkcs8", pkcs8(pem), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"])
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(data)))
  return `${data}.${b64url(sig)}`
}

// GitHub hands out "BEGIN RSA PRIVATE KEY" (PKCS#1); WebCrypto wants PKCS#8,
// so wrap it: SEQUENCE { 0, rsaEncryption, OCTET STRING { key } }.
function pkcs8(pem) {
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0))
  if (!pem.includes("BEGIN RSA PRIVATE KEY")) return der
  const len = (n) => (n < 128 ? [n] : n < 256 ? [0x81, n] : n < 65536 ? [0x82, n >> 8, n & 255] : [0x83, n >> 16, (n >> 8) & 255, n & 255])
  const tlv = (tag, bytes) => [tag, ...len(bytes.length), ...bytes]
  const algo = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
  return new Uint8Array(tlv(0x30, [0x02, 0x01, 0x00, ...algo, ...tlv(0x04, [...der])]))
}

// Stop "@name" in a report from pinging that GitHub user.
function clean(text) {
  return text.replace(/@(?=\w)/g, "@\u200b")
}

function cooldownLeft(userId) {
  const last = lastReport.get(userId)
  if (!last) return 0
  return COOLDOWN_SECONDS - (Date.now() - last) / 1000
}

function reply(content) {
  return json({ type: 4, data: { content, flags: 64, allowed_mentions: { parse: [] } } })
}

function json(obj) {
  return new Response(JSON.stringify(obj), { headers: { "Content-Type": "application/json" } })
}

// Discord signs every request; anything unsigned must be refused.
async function verify(request, body, publicKey) {
  const signature = request.headers.get("X-Signature-Ed25519")
  const timestamp = request.headers.get("X-Signature-Timestamp")
  if (!signature || !timestamp || !publicKey) return false
  try {
    const key = await crypto.subtle.importKey("raw", hex(publicKey), { name: "Ed25519" }, false, ["verify"])
    return await crypto.subtle.verify("Ed25519", key, hex(signature), new TextEncoder().encode(timestamp + body))
  } catch {
    return false
  }
}

function hex(str) {
  return new Uint8Array(str.match(/.{2}/g).map((b) => parseInt(b, 16)))
}
