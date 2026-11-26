# Remote admin

Every Portal runs a remote admin page: open `http://<portal-ip>:2324` in a browser on the same
network. The first visit sets an admin password.

- **Dashboard**: a live screenshot, health, **Check for updates**, restart.
- **Phoenix**: Phoenix Home (layout, clock face, tiles and screens, custom tiles, theme,
  wallpaper, glass, cameras, doorbell), the Kids Portal (profile, name, screen time, bedtime,
  PIN, games, reset scores), homework (spelling words, times tables, the last seven days),
  school, photos, and **Install apps on this Portal**.
- **Settings pages** for everything else (screen and audio, screensaver, Home Assistant, voice,
  music, cameras, intercom, alarms, kiosk lockdown, gestures).
- **Logs** and **About** (version, credits and licence).

Several Portals can be managed together with **Fleet**: one leader shares settings and updates
with the others. The remote admin also has a [remote API](https://github.com/rayalavcp/phoenix-portal/blob/main/docs/remote-api.md)
for automations.

The page uses plain http on your home network by default; HTTPS can be turned on in its
settings ([TLS](https://github.com/rayalavcp/phoenix-portal/blob/main/docs/tls.md)).
