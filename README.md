<p align="center"><img src="icon-1024.png" width="128" alt="Jena Web icon"></p>

# Jena Web

**English** | [한국어](README.ko.md)

A simple macOS browser built with a Swift/AppKit UI on the system WebKit engine. It focuses on the basics — viewing pages, playing video, staying signed in with cookies — and deliberately leaves out complex security policy features.

- [Program structure](docs/program-structure.md) (Korean)
- [Development log](docs/devlog) (Korean)

## Download

Get `JenaWeb-<version>-macos.zip` from [Releases](https://github.com/jenalab-com/jena-web/releases), unzip it, and move `JenaWeb.app` to your Applications folder. Requires macOS 13 or later.

The app is ad-hoc signed and not notarized by Apple, so macOS blocks it the first time. Either choose **Open Anyway** in **System Settings → Privacy & Security**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/JenaWeb.app
```

## Build and run

```sh
cmake -S . -B build/product-webkit -G Xcode
cmake --build build/product-webkit --config Debug --target JenaWeb
```

- App: `build/product-webkit/Debug/JenaWeb.app`. Xcode project: `build/product-webkit/JenaWeb.xcodeproj`.
- No engine download or engine build. Video codecs (H.264, AAC, HEVC) come from macOS.
- http/https addresses passed as launch arguments open as tabs. With no arguments the app starts with a blank tab.
- Builds use an ad-hoc signature for local development. Distribution signing, notarization and auto-update are not implemented.

## Features

- Address and search field, search engine choice (Google, Bing, Naver), web and image search.
- Tabs: open, switch, close, back, forward, reload, stop. Closing the last tab leaves a blank one.
- Link mode (current tab or new tab). ⌘-click, ⇧-click and middle-click always open a new tab.
- Popups: a popup opened by a click becomes a tab created by the engine, so `window.opener` and the sign-in context survive. Popups without a click are blocked by the engine. Google sign-in on Pinterest was verified through this path.
- Bookmarks (⌘D to add, ⌘⇧B for the list), history (⌘Y), privacy management, settings for the current site (⌘,).
- Downloads: pick where to save a file link, then reveal it in Finder when done. Overwriting existing files, resuming, and a download list are not supported yet.
- Tab icons are fetched by the app. Icons that a public page points at a local or private address are skipped; a page on such an address still gets its own icon.

## Where data lives

- App database (settings, bookmarks, history): `~/Library/Application Support/local.jena.web/AppData/app.sqlite`.
- Web sign-ins, cookies and site storage: the default WebKit store (`~/Library/WebKit/local.jena.web` and related folders), separate from the app database.
- Site settings: app preferences (UserDefaults, `siteSettings.*`).
- If the database fails to open or read, the original file is never deleted. Retry with **Reload Settings** in the app menu, or **Refresh** in the bookmark list.

## History and privacy

- Records successful HTTP/HTTPS main-document loads and in-page address changes (SPA navigation), and shows the latest 500. Repeated notifications for the same address are not stored twice.
- Privacy management deletes, after confirmation: history (by period), cookies and stored data for a given site, and the HTTP cache for all sites.
- Site data removal covers the whole registrable domain of the site you enter, including subdomains. Reload open tabs afterwards.

## Site settings

- Camera and microphone: both the site permission and the macOS permission are required. Requests without permission are held with a notice; requests from iframes are refused.
- Popups: default and allow both open clicked popups only. Block stops every popup from that site, including sign-in windows.
- Per-site location, notification and cookie settings are not supported by the WebKit engine and are shown as unsupported.

## Not there yet

External app links (mailto and the like), leave-page confirmation, web notifications, passkey sign-in.

## The earlier CEF engine

The engine was switched from CEF to WebKit on 2026-11-13. Official CEF builds ship without H.264/AAC, so mp4 video did not play, and a source build with codecs was never completed. The story is in `docs/devlog/2026-11-13-*.md`.

The CEF adapter (`Sources/browser/cef`, `Sources/browser/bridge`) and its build notes ([BuildSupport/README.md](BuildSupport/README.md)) are still in the tree and can be built with `-DJENA_ENGINE=CEF -DCEF_ROOT=...` after downloading a CEF distribution yourself. Sign-ins from the CEF profile (`WebProfiles`) do not carry over to WebKit.

## License

[MIT](LICENSE)
