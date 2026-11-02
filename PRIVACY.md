# Privacy

OpenListen does not operate a hosted service or collect analytics. There is no central user account, advertising SDK, payment feature, or developer telemetry.

- **On iPhone:** library titles, creator names, source links, playlist membership and playback positions stay in the app's local storage. Audio files stay in an app-managed folder excluded from iCloud backup. The app does not implement cloud sync.
- **Pairing:** the companion address is saved in device preferences. The pairing token is saved in the iOS Keychain with device-only accessibility. HTTP is accepted only for private IPv4, localhost or `.local` addresses; other addresses require HTTPS. Local HTTP is not encrypted, so use only a trusted network.
- **On the companion computer:** imported metadata and state are stored in SQLite, and completed audio remains in the configured data directory until the user removes it. A restart creates a new in-memory pairing token unless the user supplies `OPENLISTEN_TOKEN`.
- **Network requests:** the app contacts the companion address selected by the user. The companion contacts YouTube and its media infrastructure through yt-dlp; those services can see the computer's network address and requests. Opening an original source link invokes the user's browser or YouTube app and its privacy practices.
- **Deletion:** removing a phone download deletes that device's audio copy. Removing a complete item also asks the companion to cancel processing and delete its record and media. Copies in backups or other devices are not remotely erased.

No YouTube password or browser cookies are requested. Keep the pairing token private. The companion is intended for one trusted user on a local/private network, not as an unauthenticated public conversion service.
