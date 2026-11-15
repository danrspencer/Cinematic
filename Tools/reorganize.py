"""Moves the addon's Lua files into a folder per area (Tools/growth-plan.md).

    python -I Tools/reorganize.py            # dry run: what would move
    python -I Tools/reorganize.py --apply    # move them, and fix every path

Run it only with no other session working: it refuses while any file it moves
has uncommitted changes. It moves files on disk (no git commands, so the shared
index is left alone: git sees the renames at the next commit) and rewrites the
paths in both TOCs, .pkgmeta and the tools that open addon files by path.
After it: luacheck, Tools/check-toc.py, the offline check, then quit and start
the game (a TOC's file list is only read at startup).

--root <folder>: work on a copy elsewhere (for trying it out), with no git check.
"""
import os
import re
import subprocess
import sys

AREAS = {
    "Camera": [
        "Camera", "Director", "ZoomGuard", "QuestCam", "ShoulderCam", "ShoulderCalibrate", "MultiQuestFix",
        "SkyrideCam", "CameraRows", "TriggerLibrary", "CustomTriggers", "Shots", "CameraTriggerEditor",
        "TriggersPage", "ShotsPage", "CameraScripts", "CameraTests", "CameraWheel", "ChatCam", "ChatCamSubtitles",
        "Triggers", "CameraScriptsPage", "CameraManager",
    ],
    "Atmosphere": [
        "Tint", "Focus", "ScreenEffectsData", "ScreenEffects", "LowHealthThemes", "LowHealth", "VitalsSound",
        "TeleportVision",
    ],
    "Visions": [
        "Cards", "CardsPage", "CombatVision", "CardMoments", "ZoneCard", "Recap", "FlightLine", "CombatSounds",
        "CombatSoundRules", "EmoteVision", "RollWindow", "QuestTalk", "TalkingHeads", "QuestMobs", "QuestGlow",
        "QuestItemButton", "QuestMarkIcons", "HealVisionFrames", "DamageVision", "DamageReport",
    ],
    "Plates": [
        "PlateParts", "PlateIcons", "PlateGuild", "NameRowLook", "PlateRowLook", "PlateThemes", "NameThemes",
    ],
    "Style": [
        "StylePages", "StyleThemes", "GeneralStyle", "StyleOverrides", "InterfaceRecolor", "ThemeShots", "PageShots",
        "MirrorTimerStyle", "LetterboxStyle", "TintStyle", "QuestItemStyle", "RollStyle", "QuestTalkStyle",
        "BubbleStyle", "TooltipStyle", "ActionBarStyle", "MinimapStyle", "QuestTrackerStyle", "SwingTimerStyle",
        "XpBarStyle", "DamageMeterStyle", "PersonalStyle", "PersonalMana", "PersonalManaCost", "PersonalManaText",
        "PlateCastStyle", "PlateHealthStyle", "CombatTextStyle", "UnitStyle", "RaidStyle", "VisionsStyle",
    ],
    "UI": [
        "HideUI", "GridRows", "FrameLinks", "Chat", "ChatCopy", "Bubbles", "Speech", "SpeakerWatch", "Tracking",
        "NodeSweep", "CursorHide", "PersonalResources", "CooldownStacks", "CooldownSituations", "TooltipParts",
        "Why", "WhyPanel",
    ],
    "QoL": [
        "Campfire", "Hunter", "HunterAmmo", "DragEquip", "TalentLink", "TalentCalc", "CenterPanels", "XpLeft",
        "KeyboardMap", "Reload", "MenuWheel", "MarkerWheel", "CustomWheels", "IconBrowser", "WheelsPage",
    ],
    "Profiles": [
        "ProfileModules", "ProfileChoices", "Profiles", "Share", "Backups", "Welcome", "ShowMe", "Layouts",
        "FollowHud",
    ],
    # (Every file only the dev TOC loads: .pkgmeta can then leave out Dev/ whole.)
    "Dev": [
        "MouseTurn", "ShoulderCamTest", "PortalScout", "ScreenEffectScout", "TintLayerTest", "WindGuideStyles",
        "WindGuide", "ModuleEditor", "HeldSettingsPage", "DemoHub", "MinimapTiles", "MinimapCopy", "BarHoverTest",
        "LowManaTest", "ThresholdTest", "FlickerTest", "PlateWidthTest", "NamesTest", "StyleRevampTest",
        "PlateFlickerTest", "StyleSixTest", "KeysBarsTest", "TurnLagTest", "ReadyAnyTimeTest", "IconCropTest",
        "DamageVisionMeterTest", "HealthRedTest", "SpokenTest", "LoreForeverTest", "FollowHudTest",
    ],
}
# Tools that open an addon file by its path ("<name>.lua" in them gets the folder).
TOOLS_WITH_PATHS = [
    "Tools/vitals-demo/build_demo.py", "Tools/vitals-gallery/vitals_gallery.py", "Tools/offline/screen_effects.py",
    "Tools/style-revamp/extract.py",
]


def moves():
    out = {}
    for area, names in AREAS.items():
        for name in names:
            out[name + ".lua"] = area + "/" + name + ".lua"
    return out


def rewrite(path, fn):
    if not os.path.exists(path):
        return False
    with open(path, encoding="utf-8-sig" if path.endswith(".toc") else "utf-8", newline="") as f:
        text = f.read()
    new = fn(text)
    if new != text:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        return True
    return False


def main():
    args = sys.argv[1:]
    apply = "--apply" in args
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if "--root" in args:
        root = os.path.abspath(args[args.index("--root") + 1])
    plan = moves()
    missing = [f for f in plan if not os.path.exists(os.path.join(root, f))]
    for f in missing:
        print("not found (skipped): " + f)
    plan = {a: b for a, b in plan.items() if a not in missing}
    if "--root" not in args:
        status = subprocess.run(["git", "status", "--porcelain"], cwd=root, capture_output=True, text=True).stdout
        busy = [line[3:] for line in status.splitlines() if line[3:] in plan]
        if busy:
            print("These have uncommitted changes (another session's work?): commit them first.")
            for f in busy:
                print("  " + f)
            return 1
    for old, new in sorted(plan.items(), key=lambda x: x[1]):
        print("%-28s -> %s" % (old, new))
    print("%d files" % len(plan))
    if not apply:
        print("(dry run: --apply to move them)")
        return 0
    for old, new in plan.items():
        os.makedirs(os.path.join(root, os.path.dirname(new)), exist_ok=True)
        os.replace(os.path.join(root, old), os.path.join(root, new))

    def toc(text):
        lines = text.split("\n")
        for i, line in enumerate(lines):
            bare = line.rstrip("\r")
            if bare in plan:
                lines[i] = plan[bare].replace("/", "\\") + line[len(bare):]
        return "\n".join(lines)

    def pkgmeta(text):
        dev = set(name + ".lua" for name in AREAS["Dev"])
        out, added = [], False
        for line in text.split("\n"):
            m = re.match(r"(\s*-\s*)(\S+\.lua)(\s*)$", line.rstrip("\r"))
            if m and m.group(2) in dev:
                if not added:
                    out.append(m.group(1) + "Dev" + ("\r" if line.endswith("\r") else ""))
                    added = True
                continue
            if m and m.group(2) in plan:
                line = m.group(1) + plan[m.group(2)] + m.group(3) + ("\r" if line.endswith("\r") else "")
            out.append(line)
        return "\n".join(out)

    def tool(text):
        for old, new in plan.items():
            text = re.sub(r'(?<![/\w])"' + re.escape(old) + '"', '"' + new + '"', text)
            text = text.replace('"..", "..", "' + old + '"', '"..", "..", "' + new + '"')
        return text

    for name in ("Cinematic.toc", "CinematicDev.toc"):
        rewrite(os.path.join(root, name), toc)
    rewrite(os.path.join(root, ".pkgmeta"), pkgmeta)
    for path in TOOLS_WITH_PATHS:
        if rewrite(os.path.join(root, path), tool):
            print("paths fixed in " + path)
    print("moved. Next: luacheck ., python -I Tools/check-toc.py, the offline check; then restart the game.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
