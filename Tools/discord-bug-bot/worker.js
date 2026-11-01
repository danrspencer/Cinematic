// Cinematic bug bot: a Discord /bug command that files a GitHub issue.
// Runs as a Cloudflare Worker (Discord "interactions endpoint"), no server.
// Paste this whole file into the Worker's editor. Setup: README.md.
//
// Secrets (Worker > Settings > Variables and Secrets):
//   DISCORD_PUBLIC_KEY  Discord app's public key (General Information)
//   DISCORD_APP_ID      Discord app's application ID
//   GITHUB_TOKEN        fine-grained token: sapowowdev/Cinematic, Issues read/write only
// Optional plain variables:
//   GITHUB_REPO         default "sapowowdev/Cinematic"
//   SHOW_REPORTER       "1" puts the reporter's Discord name in the issue (public!)

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
  const repo = env.GITHUB_REPO || "sapowowdev/Cinematic"
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
    const res = await fetch(`https://api.github.com/repos/${repo}/issues`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "cinematic-bug-bot",
        "X-GitHub-Api-Version": "2022-11-28",
      },
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
