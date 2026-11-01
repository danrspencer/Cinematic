# Cinematic bug bot

A `/bug` command in the Discord server. A player picks their client, fills a
short form, and the bot opens a GitHub issue on `sapowowdev/Cinematic` and
replies (only to them) with the link.

It runs as a Cloudflare Worker on the free plan: no server, nothing on your PC.
It is not part of the addon (Tools/ is left out of the CurseForge package).

## One-time setup

### 1. Discord application
1. Go to https://discord.com/developers/applications > **New Application**, name it (e.g. "Cinematic Bugs").
2. On **General Information**, copy the **Application ID** and **Public Key**.
3. On **Bot**, press **Reset Token** and copy the token. It is only used to register the command (step 4). Don't save it anywhere else.
4. On **Installation**, under Guild Install, add the scope `applications.commands`. Copy the install link, open it, and add the app to your server.

### 2. GitHub token
1. Go to https://github.com/settings/personal-access-tokens/new (fine-grained).
2. Resource owner: `sapowowdev`. Repository access: **Only select repositories**, `Cinematic`.
3. Permissions > Repository > **Issues: Read and write**. Leave everything else off.
4. Set an expiry date (you'll need a new token when it runs out), then generate and copy it.

### 3. Cloudflare Worker
1. Sign up at https://dash.cloudflare.com (free plan).
2. **Workers & Pages > Create > Create Worker** (the "Hello World" one), name it `cinematic-bug-bot`, then **Deploy**.
3. **Edit code**: replace everything with `worker.js` from this folder, then **Deploy**.
4. **Settings > Variables and Secrets**, add these as type **Secret**:
   - `DISCORD_PUBLIC_KEY`: from step 1.2
   - `DISCORD_APP_ID`: from step 1.2
   - `GITHUB_TOKEN`: from step 2
5. Copy the Worker's URL (`https://cinematic-bug-bot.<you>.workers.dev`).

### 4. Connect them
1. Discord app > **General Information > Interactions Endpoint URL**: paste the Worker URL and save. Discord tests it right then. If it won't save, check the public key secret.
2. Register `/bug` from the repo folder. It asks for the bot token and hides it as you paste:

   ```bash
   python Tools/discord-bug-bot/register_commands.py
   ```

   It should print `Registered: /bug`. (The application ID is in the script; for another app, set `DISCORD_APP_ID`.)

Then type `/bug` in the server.

### 5. Make it private
So no one else can add the app to their server: **Installation > Install Link** = None (save), then **Bot > Public Bot** off (save). Servers that already have it keep it. To add it to another server of yours later, turn both back on for a moment.

## Changing it
- **The form or the issue text**: edit `worker.js`, paste it into the Worker editor again, Deploy.
- **The command or its client choices**: edit `register_commands.py` and run it again. Keep the `CLIENTS` list in `worker.js` matching.
- **Who can use it**: Server Settings > Integrations > the app > `/bug` lets you limit it to some roles or channels.

## Notes
- Issues get the labels `bug` and `from-discord` (GitHub creates `from-discord` the first time).
- The reporter's Discord name is not put in the issue unless you add a plain variable `SHOW_REPORTER` = `1`.
- One report per player per 5 minutes (best effort).
- If something fails: Worker > **Logs** shows GitHub's reply.
