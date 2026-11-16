---
name: support
description: The user typed /support, or said "support" and pasted a player's comment, GitHub issue, Discord message, screenshot (of a comment or of the game) or /cine log output, or asked what's going on with a player's problem. Investigates the player's problem against the code they actually run (their version, client, other addons), and drafts a short reply with exact /cine find commands and the version a fix is in; fixes only after the user's OK.
argument-hint: "[pasted player message, issue, or /cine log; or just images]"
---

A player has a problem. The goal is the same quality of answer for every
player: **investigate, never assume**. The code changes every day, and so do
other addons, so memories and past replies are leads to check, not answers.

Two phases with a hard stop between them, as in /addon-support: **phase 1
investigates and drafts; nothing is fixed, committed, posted or closed until
the user says so.**

## Phase 1: investigate

### 1. Intake

- The input may be text, one or more images, or both. Read every image: a
  comment's text, or the game's screen (which frames, which client's look).
  Several images are one case.
- **Cut off?** ("Read more", "...", a screenshot's edge, a sentence that
  stops.) Say so first and ask the user for the rest; if going on anyway, mark
  which parts rest on a guess.
- Pull out what's given: **client** (WoW Forever, retail, Classic Era),
  **Cinematic version**, **other addons** (and their versions), what they did,
  what they expected, what they saw. A pasted `/cine log` has all of it: its
  first lines are the setup summary (version, game build, client, changed
  settings, other addons, errors this session).
- What's missing and could change the answer: ask. Either one short question
  to the user, or a line in the draft reply asking the player (almost always
  "type /cine log and paste what it shows", one command in one block). With
  no `/cine log` in the case, the reply asks for it (step 5). From a
  screenshot alone the client can often be told from the UI: say it's a guess.
- **Name the session** once the problem is read (before step 2), so the
  sidebar says what this case is. This matters most when the input is only
  images: the app's own title is then empty or generic ("Support", "image").
  Call `mcp__ccd_session_mgmt__set_session_title` with `session_id: "self"`
  (load it with ToolSearch `select:mcp__ccd_session_mgmt__set_session_title`
  if it's deferred). The title:
  - starts with `Support:`, then the problem in a few plain words, then
    the area or other addon if known, e.g. `Support: target frame stays
    hidden (ElvUI)`, `Support: Shoulder Cam jitters on mount`,
    `Support: Lua error in Plates/Style`
  - under about 50 characters, no player names or handles, no version
  - the client in brackets only when it decides the case (`[retail]`)
  If the text is cut off or the images don't say what's wrong, name it from
  what is visible (`Support: unknown frame overlap, Forever UI`) and rename
  once the cause is clear. If the app asks the user to approve (they set
  the title themselves), that's fine; if it declines, go on without it.

### 2. Check the code they actually run

- Latest release and what's changed since the player's version:

  ```
  python -I .claude/skills/support/fixed_in.py --since <their version> [area files...] [--grep word]
  ```

  Each commit is listed with the release it's in. This is where "already
  fixed" shows up. With no version from the player, compare with the latest
  release and say the version is unknown.
- Read the code **at their tag** when it differs from main:
  `git show v2.1.3:Path/File.lua` (or `git diff v2.1.3..HEAD -- <file>`).
  Never `git checkout`/`stash` in the repo (parallel sessions).
- The repo layout: area folders (Camera/, Plates/, Style/, UI/, Atmosphere/,
  QoL/, Support/ for other addons, Profiles/...); Core.lua has ns.DEFAULTS,
  Migrations.lua changes settings on update, Frames.lua has the HUD rows
  (ns.COMBAT_SHOW), Conflicts.lua the Addon Conflicts rows.
- Client gates: `ns.isRetail` / per-client hidden options. A Forever player
  must never be sent to a retail-only setting, or the reverse.
- Another addon involved: scan the installed copy
  (`python -I .claude/skills/addon-support/scan_addon.py <Addon>`) and read
  `Support/<Addon>.lua`. Note the installed addon's version: it may not be
  the player's. If it isn't installed, say so (ask the user to install it;
  never download it).
- Memories (hubs: Forever quirks, retail quirks, addon support, WoW API
  pitfalls): use them to know where to look, then check the code still says so.

### 3. Find the cause

Put it in one of these, and say which:

- **(a) A setting does it**: point to it (step 4).
- **(b) Already fixed** in a newer release than theirs: they update (step 3b).
- **(c) A bug** still in main: file:line and the cause; offer the fix (phase 2).
- **(d) Another addon**: a clash or missing support; hand off to
  /addon-support, or an Addon Conflicts row.
- **(e) A game limit** (secret values in fights, protected frames, forbidden
  plates...): say plainly what the game doesn't let addons do, and any
  workaround.
- **(f) Can't tell yet**: first see whether we can test it ourselves (step
  4b); only when we can't, the one diagnostic for the player (step 5).

### 4b. Can we test it locally first?

Before asking the player for anything, check whether the user can reproduce
it here. The user has WoW Forever (main test client), retail and a gamepad,
and many addons are installed. A test the user runs settles it in one go,
and the player gets a fix instead of homework.

- **Client**: is the player's client one the user has? (Forever and retail
  yes; Classic Era only if `_classic_era_` is installed.)
- **Other addons**: is the addon installed for that client? Check
  `Interface/AddOns/<Addon>` under the client's folder (the scan_addon.py
  output says where and which version). If it isn't, say so (never download
  it).
- **Setup**: can the player's state be made here (class, zone, combat,
  settings from their `/cine log` or what they said)?

If it can be tested: plan **one recorder run** (in-game testing hub rules):
one command, under 255 characters, that logs everything that could decide it
(and takes screenshots for something visual). The user does the steps and
says "check log", and I read the log myself. If the recorder needs new debug
code, say what it would log and ask before writing it. In the report, offer
the local test as the next step, ahead of any player diagnostic. A draft
reply asking the player for something is only for when we can't test it, or
as a fallback the user picks.

**Not reproduced here proves nothing about the player.** Our test only covers
the setup we made. Their other addons, settings, profile, class or a path we
didn't hit can still make it our bug. So never write or imply "something in
your setup must be different", "it works here", or that it's on them or on
the other addon, in the findings or the reply. Say what was tried and that it
didn't happen here *yet*, and keep it open as possibly ours (category f).
Then ask for their setup (step 5).

### 3b. Which version has the fix

Every reply about a fix names the version. Find the fixing commit (read its
diff: it must really fix what the player describes), then:

```
python -I .claude/skills/support/fixed_in.py <commit> --player <their version>
```

- **Player older than the fix**: "this was fixed in v2.1.2, updating should
  sort it out".
- **Player already has it**: it's not that bug: keep looking.
- **Not released yet** (no tag contains it, or the tag isn't on origin yet):
  "fixed in the next update (v2.1.5)". The number is a forecast (latest tag +
  1 on the last number): flag it to the user.
- **Client gates** in the diff: check the fix reaches the player's client.

### 4. Exact commands

```
python -I .claude/skills/support/find_ids.py <words> [--client forever|retail] [--version <theirs>] [--hidden]
```

It builds the settings offline (Tools/offline/ids.lua: the same ids as
`/cine debug ids`, player copy) and prints `/cine find <id>` lines with the
page, label and clients, and with `--version`, whether their release has the
id ("NO" = new since: "in the next update").

- Give **ids only**, never bare label words (labels overlap: "health bar"
  matches five pages). A Show in row is `row:<key>`.
- Check the id's page and label really are the control meant (read the code
  if unsure), and that it's on the player's client.
- A setting with no id of its own: often another control sets it (a slider
  that also turns it off, a grid cell): point to that control. Only a truly
  hidden one gets `/run CinematicDB.<key>=<value>` then `/reload`, the key and
  value type from ns.DEFAULTS.
- Game settings (Key Bindings, game menus) keep their game path.
- Every command under 255 characters, one per line, one paste each.

### 5. Diagnostics to ask for

**Always `/cine log` first** when we don't have it yet (no pasted log in the
case): it's the only way to see their other addons, changed settings and
errors, and any of those could be the cause. Then add the one specific
diagnostic from the table that settles this problem, if it isn't `/cine log`
itself. So a reply asks for at most two commands: `/cine log`, plus one more.
A plain question about a setting we need to test it locally (the other
addon's option, say) can go with them.

| Problem | Ask for |
|---|---|
| Anything, setup unknown | `/cine log` (version, client, changed settings, addons, errors) |
| A frame shows or stays hidden wrongly | `/cine why`, click the frame, Copy report |
| Lua errors | `/cine log` (errors with stacks) |
| Another addon fighting | `/cine conflicts` |
| Lag or low fps | `/cine profiler`, record while it lags, Copy report |
| Client oddities | `/cine selftest` then `/cine log` |
| Game settings changed | `/cine debug cvars` |
| Something specific | the area's `/cine debug <x>` (`/cine debug help` lists them; check it's in the player copy, not dev-only) |

Beyond `/cine log`, ask for the one that settles it, not a list.

## Report to the user (end of phase 1)

Short, in chat:

1. **Questions first**, if any (cut-off text, missing version or client).
2. **Findings**: category (a-f), the cause with file:line, the fix commit and
   the version it's in, what's checked vs still a guess, what needs an in-game
   test and on which client, and whether we can test it locally (step 4b:
   client and addon installed here or not).
3. **The draft reply**: one plain ```text block, nothing nested, commands on
   their own lines. Also saved as `<short-slug>-reply.md` in the repo root.
   The reply's voice:
   - short and simple: a few plain sentences, no step lists unless needed
   - say what changed or what to set, and the version it's in
   - not fixed or not found yet: say what we tried and that we couldn't make
     it happen here yet; never suggest it's their setup or their other addon
     (step 4b)
   - no colons in the text; American spelling
   - `/cine find <id>` to take them to the setting
   - end with something like "Hope that helps, please let me know if it doesn't."
4. **Stop.** Offer the next step (a local test run first when step 4b says
   we can, then the fix, /addon-support, nothing).

## Phase 2: on the user's OK

- A fix: make it here (luacheck, the offline checks, the whats-new skill
  before any commit), then update the reply to "fixed in the next update
  (vX.Y.Z)".
- Other addon support: /addon-support.
- Never post the reply, never close a GitHub issue, never write
  "Fixes #N" in a commit: the user replies to the player first.
