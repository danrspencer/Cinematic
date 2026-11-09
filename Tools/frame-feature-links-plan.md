# Frame ↔ feature links — plan (research only, nothing built)

Status: research + mockup, 2026-11-08, revised the same day after the user's direction (section 3): apply a page's settings to a picked frame. No `.lua` changed. Started from the
EllesmereUIChat report (chat never came up for guild/party/say lines) and the
uncommitted `ns.chatPeekPanels` fix in `Chat.lua` / `Support/EllesmereUI.lua`.

Goal: one general way to say "this frame (Blizzard's or another addon's) is
part X of feature Y's thing Z", so it comes up when Y reveals Z and the
player's ticks for part X allow it.

---

## 1. How it works today

### 1.1 Two kinds of reveal

There are already **two separate reveal systems**, and this matters for the
design:

| Kind | What comes up | How a frame joins | Where |
|---|---|---|---|
| **Row-level** (minimap ping/tracking, quest progress, roster, gamepad, buff peek, cooldown, whisper, typing) | every frame in the rows of a Mouseover group that has the event ticked | its fade **group** → row (`ns.HoverRowFor`), or a found frame's **follow** row | `Frames.lua:2281`, `Frames.lua:2290-2310` (`ns.HOVER_TRIGGERS`), `Frames.lua:9562-9630` (`events.*` → `triggered[member]`) |
| **Sub-row** (chat peek, per window; and the minimap header parts picked for a reveal) | one chat window and the parts of it the Chat page ticks | ad-hoc links (below) | `Frames.lua:9432-9448`, `9711-9720`, `9882-9910` |

The row-level system is already general: any frame added with
`ns.AddFoundFrame(frame, group, ...)` (`Frames.lua:10462`) or given a follow
row (`FrameGuess.lua:567`, `followsRow[entry.frame]` at `Frames.lua:9772`) comes
up for whatever its row's Mouseover groups trigger on. **The problem is only
the sub-row case**, which chat is the big example of.

### 1.2 Chat peek, step by step

1. **Message → window.** `ChatPeekFilter` (`Chat.lua:596-643`) runs once per
   chat frame that shows the line, decides if the type is wanted (Chat page
   types, own lines, channels...), then `PeekWindow(chatFrame)`
   (`Chat.lua:366-372`) sets `ns.chatPeekUntil[chatFrame] = now + hold`.
   It needs `chatFrame:IsShown()` (a hidden docked tab doesn't peek).
   `ns.PeekChat(frame, seconds)` (`Chat.lua:376-382`) is the same for our own
   notices (5 callers, all `DEFAULT_CHAT_FRAME`). `ns.HoldScrolledChat`
   (`Chat.lua:386-398`) keeps a scrolled-up window up. Server lines are polled
   (`Chat.lua:650-700`). WIM calls filters with its own table: skipped
   (`Chat.lua:598`).
2. **Per tick, once** (`Frames.lua:9432-9448`): wipe `ns.chatPeekHolders`; for
   each peeking window set `dockPeek` if docked/default, and
   `ns.MarkChatHolders(chatFrame)` (`Chat.lua:351-363`) walks its parents up to
   UIParent marking each as a holder (ElvUI's `LeftChatPanel`), and now also
   follows `ns.chatPeekPanels[chatFrame]` (EllesmereUI's `bg`) and walks *its*
   parents. The open edit box is marked the same way.
3. **Per entry** (`Frames.lua:9711-9720`): `chatShowing` =
   - `ns.chatPeekUntil[entry.frame] > now` — the Blizzard window itself, or
   - `entry.group == "chat" and peekHolders[entry.frame]` — a holder/panel, or
   - typing, or
   - `dockPeek` and (`GeneralDockManager` and `chatPeekTabs`) or
     (a chat button — `NEVER_NESTED` + group chat — and `chatPeekButtons`).
4. **Background** (`Frames.lua:9882-9910`): for `ChatFrame%d+` entries
   (`entry.isChatWindow`, by name pattern) the window's own textures
   (`ns.CHAT_BACKGROUND_TEXTURES`, `Frames.lua:1826`) fade to 0 while the
   window is up *only* for a peek and `chatPeekBackground` is off.
5. **Buttons as their own row parts**: `FRAME_GROUPS.chat` names
   (`Frames.lua:120-124`) except `GeneralDockManager` go in `NEVER_NESTED`
   (`Frames.lua:761-772`) so Classic's in-window buttons don't come up with the
   window; `chatButtonsAlpha` follows them (`Frames.lua:9882-9884`).
6. **Inspect**: `Why.lua:30-40,402` only knows a bool `chatShowing`.

### 1.3 How support files add frames

| File | What | How it ties to chat |
|---|---|---|
| `Support/EllesmereUI.lua:323-366` `FindChat` | per window `_chatCFD(cf)` → `bg`, `sidebar`, `scrollBtn`; then unnamed UIParent children anchored to those or the dock (tab strip, border) | all `AddFoundFrame(..., "chat")`; **new**: `ns.chatPeekPanels[cf] = data.bg` |
| `Support/ElvUI.lua:73-75` | `LeftChatPanel`, `RightChatPanel` + toggle buttons, row `chat` | the Blizzard chat frames are its **children**: parent walk in `MarkChatHolders` |
| `Support/DaylightUI.lua:93` | its `Chat.chat` area → row/group `chat` | named Blizzard frames followed, unnamed found frames in group chat; no window link |
| `FrameGuess.lua:67` | name word `chat` → guess row `chat` | found frames **follow** the chat row: up when the row is hovered/triggered, **never for a message** |
| `FrameGuess.lua:905,924` | the player's added frames → group `extra:<name>` | own row; no feature link at all |

EllesmereUIChat (installed under `_forever_`): its engine makes one
`ScrollingMessageFrame` per window **as a child of `CFD(cf).bg`**, fed by an
AddMessage post-hook on the Blizzard frame, and suppresses Blizzard's text. So
`bg` is both the **lines' parent** and the **background**. Blizzard's
`ChatFrameN` stays shown (that's why `PeekWindow`'s `IsShown` check passes).

### 1.4 Other chat addons (not installed here; from what's publicly known, not verified)

- **Chattynator**: draws its own windows and hides Blizzard's chat frames. Two
  risks: (a) if `ChatFrameN` is hidden, `PeekWindow`'s `IsShown()` gate drops
  every peek; (b) its windows hold all tabs' lines, so "which window" is its
  own idea, not `ChatFrameN`. A support file would need: its window frames
  (lines/background/tabs/buttons), a map from a message to its window (or just
  "window 1"), and a way to peek when Blizzard's frame is hidden. Needs a look
  at the real addon before building.
- **WIM**: whisper windows of its own; runs message filters with its own table
  (we already skip it, `Chat.lua:598`). A support file would add each WIM
  window as its own *window key* and reveal it on its own new-message hook, or
  leave WIM windows alone (they're windows the player opens; `ns.IsWindow`).
- **Prat / Glass-style** skins keep Blizzard's frames: parent walk or
  "same window as ChatFrameN" is enough.

Never copy their code; hook their public frames/callbacks only.

---

## 2. Problems

1. **Three ad-hoc links**: parent walk (ElvUI), the panel map (EllesmereUI),
   names (`GeneralDockManager`, `FRAME_GROUPS.chat` + `NEVER_NESTED`). Each new
   chat skin adds a fourth.
2. **Parts aren't ticks-aware for addon frames.** EllesmereUI's `bg` (and
   ElvUI's `LeftChatPanel`) come up whole for a peek: their background shows
   even with *Background* unticked. EllesmereUI's tab strip and border are
   plain `chat` row frames: they never peek, even with *Tabs* ticked.
3. **Found/added frames can't tie to a peek.** A frame that "follows Chat
   window" only comes up when the row is hovered or triggered, never for a
   message. No way for a player to say "this is part of the chat window".
4. **Per-tick walk.** `MarkChatHolders` walks parents of every peeking window
   every pass (cheap, but it's work that only changes on scans).
5. **Name-pattern detection** (`isChatWindow` by `^ChatFrame%d+$`) for the
   background textures: an addon's window can't say "my background is these
   regions".
6. **Hidden Blizzard frames** (Chattynator-style) break peeks entirely via the
   `IsShown()` gate.
7. **Inspect can't say why**: `chatShowing` is one bool; no "up as EllesmereUI
   chat lines of window 1".

---

## 3. Direction (user, 2026-11-08): apply a page's settings to another frame

The user's take: this isn't "tie a part to a feature", it's **"use this
page's settings for that frame"**. On the Chat page the player picks
EllesmereUI's chat frame, and everything the Chat page does to Blizzard's chat
window (peek on a message, which types, how long, Background/Tabs/Buttons,
whisper hold, typing) now happens to that frame too. The same idea goes to
the Quest tracker page, the Minimap page and others.

So the model is a **stand-in**: a frame that the player (or a support file)
says *is* a page's frame. Today's `ns.FadeWithRows` / DaylightUI "stands in for
the game's frame" already does this, but only for the **row** (when it fades).
The new part is that it also gets the **page** (what that page does to it).

### 3.1 Sorting each page's settings

Every page setting is one of three kinds, and only the first two can carry
over to a picked frame:

| Kind | Example | Carries over to a picked frame? |
|---|---|---|
| **When it comes up** | chat peek and its message types, peek time, whisper hold, typing; quest reveal on accept/progress/scenario + calm; minimap ping, Keep open (tracking, indoors, quests, zones), Hide on flight paths | **Yes, for free.** These only decide *when* the page's frame is up. The picked frame just has to count as that frame. |
| **Which parts come up** | chat Background / Tabs / Buttons; minimap `minimapRevealParts`; quest "only that quest" + collapse | **Only where the frame's parts are known.** Where a part is its own row (the minimap's Zone name, Clock...), picking the frame on that row makes it that part. Otherwise a support file says it ("this is its tab strip"). A frame the player picks on a whole-window row = all of it. |
| **What it does to the game's frame itself** | minimap shrink when faded, indoors zoom, redraw; tracker timer focus; chat copy button, chat history, background textures by name | **No.** These touch Blizzard's frame internals. They stay on Blizzard's frame only. |

The Chat page's "only one window peeks" needs to know which window a message
went to. A picked frame with no window known counts as **every window**: it
comes up whenever any chat window peeks. A support file can map it to one
window (EllesmereUI: `_chatCFD(ChatFrameN).bg` is window N's panel).

### 3.2 API

```lua
-- frame stands in for a page's frame. page: "chat", "quests", "minimap"...
-- part: one of that page's parts ("window", "background", "tabs",
--   "buttons"; "map", "zone", "clock"...; nil = all of it).
-- opts.window: which chat window (a ChatFrameN), nil = every window.
-- opts.regions: fade only the frame's own textures for this part (a
--   backdrop drawn on the same frame as the lines).
ns.UsePageFor(frame, page, part, opts)
```

- Support files call it at scan time (EllesmereUI: panel = `window` of
  ChatFrameN with its backdrop `regions` as `background`, tab strip = `tabs`,
  sidebar = `buttons`).
- The player's picks are saved by **row**: `db.rowFrames[rowKey][frameName] = true`
  (unnamed frames by the `@<addon>` key Advanced Frames already uses). The
  row says the page and the part (`chat` → Chat page, whole window;
  `minimapzone` → Minimap page, Zone name part), so the player never picks a
  part. `db.rowFrames[rowKey]["-game"] = true` = the game's own frame taken
  off the row.
- Blizzard's own frames register the same way at load, so the fade pass has
  one path: `ChatFrameN` = `window` of itself, `GeneralDockManager` = `tabs`,
  the chat buttons = `buttons`, `Minimap` = `map`, `ObjectiveTrackerFrame` =
  `tracker`.
- A stand-in **joins the page's row** (Chat window, Minimap, Quest tracker), so
  hovering, Mouseover groups, the Show in table, combat lists and row-level
  reveals all work with no extra code. It leaves its Custom frames row.

### 3.3 Fade pass

Once per pass, per page with stand-ins: what's up and which parts are on.
For chat: `up[window] = true` for each peeking window, `up.any` if any,
`up.dock` if a docked one; `partOn.background/tabs/buttons` from the ticks.
Per entry: `local as = entry.as` (set once when added, cleared on rescan),
then `as and up[as.window or "any"] and partOn[as.part]`. One lookup, as the
first idea had; no parent walk; no name pattern. The "does to the game's frame"
checks (`entry.frame == Minimap`, `== ObjectiveTrackerFrame`, `isChatWindow`)
stay on Blizzard's frames and don't look at `entry.as`.

Holders (ElvUI's `LeftChatPanel`, which *contains* Blizzard's chat) are worked
out at scan time as `window` parts of the chat frames inside them.

**Lua local cap**: no new main-chunk locals in `Frames.lua`; state in `ns.*`
or `tickTables.*`.

### 3.4 Per page

| Page | Stand-in parts | Carries over | Stays Blizzard-only |
|---|---|---|---|
| **Chat** | window, background, tabs, buttons | peek + types + time, own lines, channels, whisper hold, typing, Show in | copy button, history, bubble-speech, `CHAT_BACKGROUND_TEXTURES` |
| **Quest tracker** | tracker (whole) | reveal on accept/progress/scenario + calm, durability/timer keep-up rows | "only that quest" + collapse (needs its quest blocks: support file, e.g. HorizonSuite blocks), tracker timer focus |
| **Minimap** | map, zone, clock, tracking, calendar, coords, addon buttons | ping, Keep open (tracking, indoors, quests, zones, prey), Hide on flight paths, Reveal parts (by part) | shrink when faded, indoors zoom, redraw, node marks / quest-giver pins |
| Later | Buffs (BuffFrame stand-ins: "only new buffs" stays Blizzard-only), Cooldown Manager, Gamepad | | |

Per the "hide unclickable" rule: a page setting that can't reach any of the
picked frames stays (it still works on Blizzard's), but the frame picker
says which of the page's settings don't apply to that frame.

### 3.5 Player-facing: a master row + one row per part, one frame each (user, 2026-11-08)

No new section. The page's own **Show in** table changes:

- **One frame per row.** Each row has a **Frame** cell holding one frame, or
  nothing = *Blizzard (default)*. Picking an addon's frame **replaces**
  Blizzard's for that part: the page lets go of Blizzard's frame
  (`ns.LeaveAlone`-style) and works only on the picked one. The rule never
  runs on two frames for one part, so there's no extra work in the fade pass.
  (If the addon doesn't hide Blizzard's frame itself, it stays visible: the
  player's choice.)
- **A master row + part rows.** Many Blizzard "frames" are several parts (the
  minimap: map, zone name, clock, tracking, calendar, coordinates; chat:
  window, tabs, buttons, input box; quests: tracker, quest timer). The master
  row ("Minimap") has only ticks, no frame. Each part row under it has its
  frame cell and **follows the master's ticks** (shown dashed) until the
  player clicks one of its ticks: then it keeps its **own** ticks, with
  "↺ Same as Minimap" to follow again. Like the Unit Frames page's
  "same as Target" (`unitPartsToTSame`, `Options.lua:7010`).
- **Picker.** Clicking a frame cell opens the Find frames search under the
  table (`Options.lua:14166-14200`, lifted into a shared function): first
  match is always *Blizzard (default)*; typing lists other addons' frames
  (unfaded, or on a custom row: "on a custom row now", moves it). Hovering a
  match marks it on screen. A frame already used by another part says
  "used by Zone name" and moves if picked.
- Parts come from the rows, so there is no "As" choice. Support files fill a
  part's frame (EllesmereUI: Window = its chat panels, one per window; Tabs =
  its tab strip), shown as "found by Cinematic".
- A part row only shows where this client has that part (rule: hide what can
  never be used), as the Minimap page's `PartsHere()` already does for Reveal
  parts (`Options.lua:11056`).

Saved: `db.rowFrames[partKey] = frameName` (nil = Blizzard), and
`db.rowOwn[partKey] = true` when a part row has its own ticks (its ticks stay
in today's per-row Show in tables; without `rowOwn` it reads the master's).

Fade pass: unchanged in cost. A part row is a row like any other (`entry.row`
= part key, `minimapzone` etc. already are rows); "follows master" is resolved
when settings change (copy the master's ticks into the part's lookup), not per
tick.

---
### 3.6 Which HUD pages (user, 2026-11-08)

Only pages whose frame other addons commonly replace. Order = build order.

| # | Page | Master row → part rows (Game Frames keys) | Notes |
|---|---|---|---|
| 1 | **Chat** | `chat` → new `chatwindow`, `chattabs`, `chatbuttons`, `chatinput` | today one row (`Frames.lua:2139`, all of `FRAME_GROUPS.chat`); the parts are new rows following `chat` |
| 2 | **Minimap** | `minimap` → `minimapheader`, `minimapzone`, `minimapclock`, `minimaptracking`, `minimapcalendar`, `minimapdial`, `minimapaddons`, `minimapcompartment`, `minimapcoords` | rows **already exist** and already follow `minimap` (`ROW_FALLBACK`) |
| 3 | **Quest Tracker** | `quests` → `questtimer`, `topcenter` | `topcenter` already follows `quests` |
| 4 | **Buffs/Debuffs** | `buffs` → new `buffsown`, `debuffs`, `enchants` | today one row over three frames (`Frames.lua:2062`); "only new buffs" stays Blizzard-only |
| 5 | **Cooldown Manager** | `cooldowns` → `cooldownsutility`, `cooldownsbuffs`, `cooldownsbars` | rows and following **already exist** |
| 6 | **Unit Frames** | `player` → `petframe`; `target`, `tot`; `focus` → `focustot` | one frame per unit row; the page's parts (name, portrait, level) stay Blizzard-only |
| 7 | **Resource Display** | `prd` → `prdpower`, `prdmana` | `prdpower` already follows `prd`; these are our stand-ins, an addon's bars replace the stand-in |
| 8 | **Swing Timer** | `swing` → new `swingmh`, `swingoh`, `swingranged` | in (user, 2026-11-08); WeakAuras/Quartz swing bars as the replacements |
| – | Tooltips | – | not needed: tooltip addons reuse `GameTooltip` |

### 3.7 Where it goes

**Finding: the master + part rows already exist.** The **Game Frames** page
(id `Standard Frames`, `Options.lua:6726-6930`) has a tab per area (Unit
frames, Action bars, Trackers, Info and menus, Minimap, Party, Raid...), its
rows from `ns.COMBAT_SHOW` (`Frames.lua:1921`), each with a link to its HUD
page (`morePage`). And `ROW_FALLBACK` (`Frames.lua`, above `ns.ROW_FALLBACK`)
already makes a part row take its master's tick in each column until given
its own (the minimap's header parts follow `minimap`, the cooldown bars
follow `cooldowns`); ticking a follower first copies the master's ticks
(`GridRows.lua:1140-1160`). Raid-style party has a whole-tab "Same as raid
frames" box. So the mockup's master + parts + "own" is today's Game Frames
grid. What's new is only **the frame each row is**.

Options:

- **A. Game Frames page, on each row (recommended).** The row's name becomes
  clickable (or a small frame icon at the row's end): it opens the picker
  under the row. A row using an addon's frame shows the frame under its name
  in small grey ("EllesmereUI chat panels"); *Blizzard (default)* shows
  nothing. Pros: rows, tabs, following and Show in ticks are all there
  already; one place for "what is this row's frame" and "when does it show";
  no new column in a grid that's already wide (4 + place columns). Cons: the
  player looking at the Chat page has to go to Game Frames.
- **B. Each HUD page, a "Frames" list.** At the top of the page, its rows
  with just the frame cell (no ticks, those stay on Game Frames, linked).
  Pros: next to the page's settings. Cons: the same rows on two pages; a new
  layout on 7 pages.
- **C. A + a line on each HUD page.** A on Game Frames, and on the HUD page
  one line under Enable Page: "Frames: Blizzard (default) · EllesmereUI chat
  (Window, Tabs) — Change »" opening Game Frames on that tab. Pros: findable
  from both; only one picker. Cons: one extra line per page.
- **D. Addon Frames page.** Found frames already "follow" a row there
  (`FrameGuess.lua:567`). A second choice "Is the frame of: <row>" would be
  the same link from the other side. Useful for frames found by Smart Find;
  not a replacement for A (players think from the page, not the frame).

- **E. The row's CQL panel (user's idea).** The rule editor (`GridRows.lua`
  `ns.OpenRuleEditor`, ~`:636`) opens per row from every Show in grid
  (`ruleText` / `edit` buttons, ~`:944-981`), on Game Frames and the HUD
  pages alike, and already holds one "what this row is tied to" choice: its
  `follow` leader ("Follows %s: shows when it does"). A **Frame** line at its
  top ("Frame: Blizzard (default) · Change") with the search opening in
  place fits there. Pros: per row already; every grid gets it with no layout
  work; room in the panel; no new column. Cons: players open it for rules, so
  a frame choice is hidden unless the row shows it (grey frame name under the
  row's label, click opens the panel on Frame); the heading needs to read
  "Row: You: Portrait" (or Rule | Frame tabs), not just CQL. Only rows that
  can have a frame show the line.

- **F. Game Frames grid with a Ticks | Frames switch (after user feedback, 2026-11-08,
  mockup revision 6).** E was dropped: one panel per row means nine panels to
  move the minimap to an addon. Instead a switch above the Game Frames grid
  swaps the tick columns for one **Frame** column, same rows and tabs.
  - **Master row = addon choice.** Its Frame cell lists *Blizzard (default)*
    and each addon whose parts a support file knows ("EllesmereUI — fills 5
    of 9 parts"). Picking one fills every part that addon has; parts it has
    none for stay Blizzard (default), marked "EllesmereUI has none".
  - **Part rows = one frame each**, changed on their own with the Find frames
    search ("picked" in gold). A hand pick, Blizzard included, is kept when
    the master's addon changes.
  - **Ticks view** is today's grid with `ROW_FALLBACK` following, plus
    "own" / "↺ Same as <master>" on a part row with its own ticks.
  - Saved: `db.rowAddon[masterKey] = addon`, `db.rowFrames[partKey] = frame
    name | false` (false = Blizzard picked by hand); unset = from the addon or
    Blizzard. The fade pass reads the resolved frame per part, once, when
    settings change.

- **G. One table: part sub rows with ticks + Frame (user's pick, 2026-11-08,
  mockup revision 7).** The user preferred revision 4's layout (parts as sub
  rows, ticks and frame side by side, no switch) over F's switch. G = that
  layout + F's master-row addon fill:
  - Master row: ticks + a Frame cell that picks an addon ("EllesmereUI —
    fills 5 of 8 parts") and fills every part it has.
  - Part sub rows: ticks following the master until their own ("↺ Same as"),
    and one frame each (Blizzard (default), "from <addon>", "picked", or
    "<addon> has none"). Hand picks are kept when the master's addon changes.
  - Collapsible master (▸). Same saved data as F.
  - Width: the Frame column makes the grid ~760px; fine on a HUD page's own
    table, tight on Game Frames with all its place columns (open question:
    where it lives).

- **H. A "Game frames" tab on Addon Frames (user's idea, 2026-11-08, mockup
  revision 8).** Addon Frames (id `Advanced Frames`, tabs Loaded / Find
  frames / Not running, `Options.lua:13536`) gets one more tab. It lists each
  HUD master (Chat window, Minimap, Quest tracker, Buffs and debuffs,
  Essential Cooldowns, Unit frames), collapsible, with G's master + part rows
  but **only the Frame column**: the master picks an addon that fills its
  parts, each part picks one frame with the Find frames search. Ticks stay on
  Game Frames and the HUD pages (no width problem, no new Game Frames tabs:
  G there would need 4-6 new ones: Chat, Quest tracker, Buffs, Cooldowns,
  maybe Resource Display and Swing Timer).
  - Loaded tab: each addon says "Replaces game frames: Chat, Minimap (5 of 8)",
    linking to that spot on the new tab.
  - Game Frames: a row using an addon's frame shows its name in grey under
    its label; clicking it opens the new tab at that row.
  - HUD pages: the pointer line ("Frames: EllesmereUI (5 of 8 parts) ·
    Change in Addon Frames »").

- **I. A "Frames" band at the bottom of each HUD page (user's pick,
  2026-11-08, mockup revision 9).** H's rows (master picks the addon, one
  frame per part, Frame column only) but on the page they belong to, since
  players wouldn't look for "the minimap's zone name" on Addon Frames.
  - Last band on Chat, Minimap, Quest Tracker, Buffs/Debuffs, Cooldown
    Manager, Unit Frames, Resource Display (Swing Timer: open question).
  - Collapsed when every part is Blizzard's; open, "found by Cinematic", when
    a support file filled it. Header shows "EllesmereUI: 5 of 8 parts".
  - Game Frames rows using an addon's frame show its name in grey; clicking
    opens the page scrolled to that part. Addon Frames' Loaded tab: "Replaces
    game frames: Chat, Minimap (5 of 8)…", each opening that page's band.
  - No new tabs anywhere; no pointer line needed.
  - Unit Frames: its per-unit part sections stay above; the band's part rows
    are the units (Player, Pet, Target, Target of target, Focus).
  - **Decided (user, 2026-11-08):** the band is called **Addon Frame Links**.
    It is collapsed while every part is Blizzard (default) and open once any
    part has an addon's frame. Changing the master's addon changes only the
    parts the player hasn't changed; a changed part shows "↺ Same as
    <master>" to follow the master again (no change-all). **Swing Timer** gets
    the band too (Main hand, Off hand, Ranged).


Recommendation: **I** (the user's pick): an Addon Frame Links band at the bottom of each HUD page, linked from Game Frames rows and the Addon Frames Loaded tab. D later, sharing the
same saved value (`db.rowFrames[rowKey]`), so a pick from either side shows
in both.

### 3.8 Support files and clashes (user, 2026-11-08)

- **One support file per addon, tailored to it.** Each says, per master,
  which of its frames is which part, and for a backdrop drawn on the same
  frame as other parts, which regions are the background (`opts.regions`).
  An addon's backdrop **follows the Chat page's Background tick** (unticked:
  just its lines). EllesmereUI first (`Support/EllesmereUI.lua`: chat, then
  minimap, quest tracker, unit frames, cooldowns); Chattynator and WIM later.
- **Support files fill the band themselves** ("found by Cinematic"), but only
  where they don't clash.
- **Clash rule (revised 2026-11-09: per part, settled by the player).** For
  each **part**, collect the support files that claim it on this login.
  - One addon claims it: applied on its own ("found by Cinematic").
  - Two or more: a **clash**. That part stays **Blizzard (default)** until
    the player picks one (user: Blizzard default for now). Other parts of the
    same group are unaffected: EllesmereUI's quest tracker with Questie's quest
    item buttons is the target case (user wants EllesmereUI for most things,
    Questie for the item button). This needs support files to claim parts
    finely: Questie's file today ties `Questie_BaseFrame` and
    `Questie_ItemButton1-n` both to the Quest tracker row; they become the
    Tracker and Quest item buttons parts.
  - **Where it's settled:** a new **Support files** tab on Addon Frames (beside
    Loaded / Find frames / Not running; mockup revision 10). A Clashes block at
    its top lists each clashed part ("Quest tracker › Tracker") with one
    button per addon plus Blizzard; below, one block per loaded supported addon
    with the groups it replaces ("Minimap: 5 of 8 parts", "1 waiting on a
    pick"), each linking to that page's band. The tab shows a count badge
    while clashes are unsettled. The page's Addon Frame Links band shows the
    same parts ("EllesmereUI or Questie: pick one") and links to the tab. Both
    write the same saved pick (`db.rowFrames[partKey]`).
  - **Priority in the background (later):** each support file may carry a
    priority, used only to suggest a pick (listed first, "suggested"), never
    applied on its own for now.
  - Supersedes the earlier "two addons on one group → none applied" rule.
  - Worked out once per login after the scans (`ns.AddScanner` order), and
    again when a support file's addon loads late (`ns.WhenAddonLoads`).
  - A support file whose addon has its own module switched off (EllesmereUI
    without EllesmereUIChat, ElvUI with its chat disabled) claims nothing:
    each file checks that before claiming.
  - `/cine selftest` and Inspect (`/cine why`) name a clash when there is one.



## 4. Mapping existing code

| Today | After |
|---|---|
| `ns.chatPeekPanels` (uncommitted) | `ns.UsePageFor(data.bg, "chat", "window", { window = cf, regions = ... })` |
| `ns.MarkChatHolders` per tick (ElvUI) | holders at scan: `UsePageFor(LeftChatPanel, "chat", "window", { window = cf })` |
| `GeneralDockManager` / `FRAME_GROUPS.chat` + `NEVER_NESTED` checks for peeks | Blizzard registrations, parts `tabs` / `buttons` (`NEVER_NESTED` stays, it's about nesting) |
| `isChatWindow` background fade | stays for Blizzard's; addon backdrops via `opts.regions` |
| `ns.FadeWithRows` / DaylightUI `AREAS` (row only) | can pass a page too where the addon replaces that page's frame (DaylightUI `Chat.chat`, `Quests.tracker`, `InfoPanel.panel`) |
| FlareUI / HorizonSuite quest blocks in group `quests` | `UsePageFor(block, "quests", "tracker")`; later per-quest blocks |
| FlareUI minimap header (`minimapheader`) | `UsePageFor(header, "minimap", "zone")` etc. |
| Custom frames "follows" row | a picked frame on a page = that page's row + page |
| `Why.lua` `chatShowing` | "up as EllesmereUI chat's window (Chat page: a message)" |

---

## 5. Migration, small steps (each its own commit, each tested in game)

1. **Registry only**: `ns.UsePageFor`, `ns.pageFrames`, `/cine debug pageframes`
   prints every stand-in (page, part, window, managed or not). No behavior change.
2. **Blizzard chat registers**; fade pass computes the new answer beside
   `chatShowing` and prints mismatches under the debug command (shadow mode).
3. **EllesmereUI chat** through the API; drop `ns.chatPeekPanels`. Visible
   change: its backdrop follows *Background*, its tab strip follows *Tabs*.
4. **Switch the chat pass**; drop the per-tick parent walk and name checks.
5. **Frames cell on the Chat page's Show in row**: first lift the Find frames
   search into a shared function (Advanced Frames unchanged), then the cell +
   picker, saved in `db.rowFrames.chat`; Profile sharing carries it (unknown
   keys skipped).
6. **Why.lua** lines.
7. **Quest tracker page**, then **Minimap page**, same steps 2-6 each.
8. Optional: Chattynator / WIM support files after a look at the real addons.

---

## 6. Tests per client

Each: one action, yes/no (simple-test-steps memory). CineMode on, nothing
hovered.

**Forever (main)**
- [ ] Guild line, Blizzard chat: window lines up; background up only with *Background* ticked.
- [ ] Same with *Tabs* ticked: dock tabs up; unticked: not.
- [ ] *Buttons* ticked: chat menu / channel buttons up.
- [ ] Docked tab not selected gets a line: nothing peeks.
- [ ] Undocked window (drag a tab out) gets a line: only that window.
- [ ] Our update notice (`ns.PeekChat`): window up 6-15 s.
- [ ] Scrolled up: window stays up; back at bottom: fades after peek time.
- [ ] Enter (typing): whole chat at once (unchanged).
- [ ] Whisper tab unread: whole chat stays (unchanged).
- [ ] **EllesmereUIChat**: say/party/guild line → its panel's lines up; background follows *Background*; tab strip follows *Tabs*.
- [ ] **ElvUI**: line → LeftChatPanel up; backdrop per open q. 1.
- [ ] `/cine why` on a peeking window names the part.
- [ ] Profiler: fade pass ms with chat peeking vs before (compare ms, cpu-profiling memory).

**Retail**
- [ ] Same Blizzard set (dock, QuickJoinToastButton, voice buttons, FriendsMicroButton).
- [ ] A line with secret text in a fight still peeks (filter path, no text read).
- [ ] EllesmereUIChat if installed there.

**Classic Era**
- [ ] Buttons inside the chat window (Classic layout): window peek doesn't bring them unless *Buttons* ticked.
- [ ] `CHAT_FRAME_TEXTURES` missing → fallback list fades the background.
- [ ] No QuickJoin/voice buttons: registering missing names is a no-op.

---


**Picked frames (new)**
- [ ] Chat page: Window row's Frame cell, type "Ellesmere", pick its chat panels → a guild line brings them up, Blizzard's chat stays as the game leaves it.
- [ ] Minimap page: Clock row ticks its own column → only the clock follows it; "↺ Same as Minimap" puts it back.
- [ ] Master row tick changes → every part row without its own ticks follows at once.
- [ ] Hover a match in the picker → it's marked on screen.
- [ ] A frame already on a custom row shows in the search; adding it → it's gone from Advanced Frames.
- [ ] Pick "Blizzard (default)" → the addon frame goes back to fading on its own (Custom frames).
- [ ] A picked frame with no window known: a line in any window brings it up.
- [ ] Quest tracker page: pick an addon's tracker → accepting a quest brings it up.
- [ ] Minimap page: pick an addon's minimap → a party ping brings it up; on a flight path it stays down.
- [ ] /reload: picks kept. Profile export/import carries them.

---

## 7. Open questions for the user

Settled (user, 2026-11-08):
- Where: an **Addon Frame Links** band at the bottom of each HUD page (3.7 I),
  Swing Timer included; collapsed while every part is Blizzard (default).
- Rows: master row picks an addon; one frame per part row; empty = Blizzard
  (default); no "As" choice. Ticks stay on Game Frames, whose rows show an
  addon frame's name in grey and link to the band.
- Changing the master's addon changes only parts the player hasn't changed;
  "↺ Same as <master>" per row to follow again; no change-all.
- An addon's backdrop follows the Chat page's *Background* tick; support
  files tailored per addon (3.8).
- Support files fill the band ("found by Cinematic"); a part two addons claim is a clash, Blizzard (default) till the player picks it on the new Support files tab or the band (3.8, revised 2026-11-09).
- EllesmereUI first; Chattynator / WIM later.

Still open:
1. A part filled by a support file ("found by Cinematic"): does it change
   with the master's addon like any untouched part (as mocked), or count as
   a pick of its own?
2. A clash: only the tab badge and band note say so (as mocked), or also one chat line at login
   ("Cinematic: EllesmereUI and ElvUI both replace your chat; pick one on the
   Chat page")?
3. Chat's "A message shows" ticks (Background, Tabs, Buttons): keep them as
   they are, or later make them settings of the Tabs / Buttons part rows?
4. Build order after Chat: Minimap, Quest Tracker, then Buffs/Debuffs,
   Cooldown Manager, Unit Frames, Resource Display, Swing Timer (3.6)?
