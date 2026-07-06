# stswiftapp

iOS client for [SillyTavern](https://github.com/SillyTavern/SillyTavern) — chat with AI characters on your iPhone.

## Features

- **Character chat** — browse characters, start conversations, swipe for alternate responses
- **Group chats** — multi-character conversations
- **Streaming** — real-time token-by-token response rendering
- **Markdown rendering** — bold, italic, strikethrough, code blocks, blockquotes, links, emoji shortcodes
- **Macro support** — `{{user}}`, `{{char}}`, `{{time}}`, `{{date}}`, `{{weekday}}`
- **Quoted text coloring** — configurable color for quoted dialogue
- **Message actions** — copy, edit, delete, regenerate, impersonate
- **Personas & World Info** — browse and manage from the app
- **Conversation management** — rename, delete, switch between chat histories
- **Configurable API** — model, temperature, top-p, top-k, frequency/presence penalty, stop sequences, custom endpoints, reverse proxy

## Requirements

- iOS 18+
- A running [SillyTavern](https://github.com/SillyTavern/SillyTavern) server (or compatible backend)

## Installation

### Sideload (unsigned IPA)

Download the latest `stswiftapp.ipa` from [Releases](https://github.com/stupidorphan/stswiftapp/releases) and sideload with [AltStore](https://altstore.io/), [Sideloadly](https://sideloadly.io/), or similar.

### Build from source

```bash
git clone https://github.com/stupidorphan/stswiftapp.git
cd stswiftapp
open stswiftapp.xcodeproj
```

Select your device or simulator, then **Product → Run** (⌘R).

#### Build unsigned IPA

```bash
xcodebuild -project stswiftapp.xcodeproj -scheme stswiftapp \
  -sdk iphoneos -configuration Release build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -derivedDataPath /tmp/stswiftapp-build

APP=/tmp/stswiftapp-build/Build/Products/Release-iphoneos/stswiftapp.app
mkdir Payload && cp -R "$APP" Payload/ && zip -r stswiftapp.ipa Payload
```

## Setup

1. Launch the app — you'll see the server connection screen
2. Enter your SillyTavern server URL (e.g. `http://192.168.1.100:8000`)
3. Choose your auth mode (API Key, OAuth, JWT, or None)
4. Tap **Connect**
5. Once connected, browse characters and start chatting

API settings (model, temperature, etc.) can be configured under the **Settings** tab.

## License

MIT
