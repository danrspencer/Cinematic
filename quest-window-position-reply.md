Thanks, glad you're enjoying it, and you're right, this one comes from Cinematic!

The likely cause is a setting called "Opposite clicked". It puts the quest window on the other half of the screen from where you clicked the NPC, so it jumps around depending on where they're standing. It used to be the default, and it stays saved for anyone who installed back then.

To set it back to Default, paste these into chat, one at a time:

```
/run CinematicDB.questTalkPlace="fixed"
```

```
/reload
```

You can also change it in the settings: on the Quest Vision page, set Bubble position to Default.

The next update will switch this back for everyone, so you won't need to do it again.

If the window still moves after that, click Put windows back on the Quality of life page, in case a spot got saved from dragging it. If it still moves, open a quest window while it's in the wrong spot, run this and send me what it prints:

```
/cine debug panels
```

That will also show whether EllesmereUI is moving it.
