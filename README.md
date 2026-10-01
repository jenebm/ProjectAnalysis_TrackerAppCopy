# gacha tracker

Flutter app (Windows + Android) for tracking banners/events. Imports from:

- Genshin / HSR / ZZZ: hoyoverse in-game announcement feed
- Endfield: gryphline bulletin, falls back to [ak-endfield-api-archive](https://github.com/daydreamer-json/ak-endfield-api-archive)
- Limbus: steam news (dates parsed from text, assumed KST)

Character banners auto-import for the HoYo games and Endfield (toggle in settings).

## build

Push to main and the workflow builds the apk + windows installer and puts them in releases.
* Copy version, repo public so debug keystore absent.

Locally:

```
flutter create --platforms=android,windows --org com.gachatracker .
python ci/patch_android.py
flutter pub get
flutter run -d windows
```

Windows needs VS 2022 with the C++ desktop workload (+ ATL if flutter_local_notifications_windows complains) and developer mode on.

## notes

- hoyoverse/gryphline endpoints are unofficial, might break
- backup import merges, doesn't delete
- reminders are android only
