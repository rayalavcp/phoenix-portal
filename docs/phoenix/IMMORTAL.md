# Phoenix Portal and Immortal

Phoenix Portal replaces Immortal (`com.immortal.launcher`, the app on the
`legacy-immortal` branch). This page compares the two apps and lists what to
do before Immortal is uninstalled from a Portal.

## What Phoenix covers

| Immortal feature | In Phoenix |
|---|---|
| Launcher: app grid, clock, weather | Yes: the Today screen, the app drawer (search, recent, most used), the dock |
| **Calls tile** (WhatsApp/Messenger calling through the stock Portal home) | Yes, since 2026.12.10: **Calls** on the Today dock opens the Portal's own calling screen (`portal://launcher/home`), the same way |
| Photo-frame screensaver | Yes: Phoenix Photo Frame and Immich, plus Weather Mood, Celestial and Clock screensavers |
| Presence sensor keeps the frame up while someone is there | Yes (person sensor, Meta's presence service) |
| Self-update | Yes, from this repository's GitHub Releases |
| Provisioning, Gen-1 installer fix, OTA block, verifier | Yes: `install/install-phoenix.ps1`, `provisioning/phoenix-provision.sh` |
| App Store | Yes: free apps, installed through Android's installer |
| Multi-room audio, now playing (Snapcast / Music Assistant) | Yes, in Phoenix's own way: Sendspin / Music Assistant, AirPlay, DLNA |
| Smart home over MQTT | Yes, in a different way: Phoenix shows up in Home Assistant through **ESPHome**, not MQTT |
| Fleet agent (manage over Wi-Fi) | Yes: the remote admin (`http://<portal>:2324`), Fleet Management, self-update |
| RTSP cameras | Yes: Home Assistant cameras on the Today screen, camera views, the doorbell alert |
| Intercom between Portals | Yes |
| Kitchen timers, alarms (with a sunrise light) | Yes |
| Portal TV remote (D-pad) | Partly: keyboard and D-pad navigation exists (`key_nav.dart`) but has not been tried on a Portal TV |
| Kids content | Phoenix's Kids Portal is far larger: more than 50 games, maps, camera games, screen time, bedtime, PIN |

## What Phoenix does not have (yet)

- **Photo sources:** iCloud shared albums, SMB network shares, WebDAV and
  web pages. Phoenix takes Immich or an http folder.
- **Screensaver extras:** Immortal's clock faces (flip, big, bold, minimal),
  the welcome-back greeting and the almanac line.
- **Tools:** reading lamp, bedtime stories read aloud, sticky/voice notes,
  unit and currency converter, ISS pass times, aurora outlook, speed test,
  countdown chips, world clock.
- **Ambient sound:** hourly chime, spoken time, golden-hour tone, quiet hours.
- **Help tour** for first-time users.
- **"Install with Immortal":** opening an APK file from a browser or a file
  manager, and the Downloads APK browser. Phoenix's App Store and self-update
  install through Android's own installer, which works once the Gen-1 fix
  is applied.
- **Boot apps** (other apps started at boot).

None of these is needed for Phoenix to run the Portal. Any of them can be
added if they're missed.

## Is it safe to uninstall Immortal?

Yes, with these checks first:

1. **Phoenix 2026.12.10 or newer is installed** and is the home screen
   (the installer sets this). Try **Calls** on the Today dock and place a
   call before removing Immortal, if the Portal is used for calls.
2. **Home Assistant:** Immortal's MQTT device goes away. Move any automation
   or dashboard that uses it to the Portal's **ESPHome** entities, then
   delete the old MQTT device in Home Assistant.
3. **Photos:** if Immortal's frame showed an iCloud, SMB or WebDAV album,
   point Phoenix at Immich or an http folder instead (or ask for those
   sources to be added first).
4. **Multi-room audio:** re-create speaker groups in Music Assistant with the
   Portal's Sendspin player.

What stays after uninstalling: every app installed from Immortal's store,
Shizuku, and the device-level fixes (Gen-1 installer overlay off, OS updates
blocked, verifier off). Those are settings on Meta's own packages, not part
of Immortal, and Phoenix's installer applies them too.

### How to remove it

- **Do not run Immortal's `--restore`** (`Restore-Portal`). It does more than
  remove Immortal: it turns Meta's OS updates and install verifier back on,
  puts the white-on-white installer dialog back on Gen-1 Portals and sets
  the stock home screen and screensaver, all of which Phoenix needs off.
- Immortal makes itself a **device admin** when provisioned, and Android
  will not uninstall an active device admin. On the Portal: Settings >
  Security > Device admin apps > Immortal > Deactivate (or try
  `adb shell dpm remove-active-admin com.immortal.launcher/.AdminReceiver`,
  which Android often refuses for a non-test admin).
- Then: `adb uninstall com.immortal.launcher`.
- Afterwards, check that `adb shell pm list packages -d` does **not** list
  `com.facebook.alohaservices.presence` (Immortal could turn Meta's presence
  sensor off if `DISABLE_PRESENCE` was chosen at setup; Phoenix uses it).
  If it is listed: `adb shell pm enable com.facebook.alohaservices.presence`.

`install/LOCAL_AGENT.md` has these steps for the local agent, to run only
when the owner says so.
