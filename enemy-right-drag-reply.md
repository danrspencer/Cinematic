Thanks for the video, that found it! The "Out of range" message was the clue. This was a bug in Cinematic, and it's fixed in v2.0.29.

Our right-click Auto Shot is only meant for hunters on Classic Era, but Cinematic mistook WoW Forever for Classic Era, so it was on for you too. It took over right-click while your mouse was on an enemy, so the game never got the drag and the camera didn't turn.

If you can't update yet, untick "Right click attack also uses Auto-shot" under Quality of life > Hunter, or paste this in chat:

```
/run CinematicDB.hunterRightClickShot=false
```

Thanks for sticking with it!
