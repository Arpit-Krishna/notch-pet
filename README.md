# Notch Pet 🟩

> A tiny blocky buddy that lives in your MacBook notch and babysits your Claude Code and Codex sessions.

Pip sits next to the notch. It mines while your agents work, panics when one needs your OK, celebrates when one finishes, and warns you before you hit your plan limits. The notch is named after the guy who made Minecraft, so Pip is a Minecraft fan. Obviously.

![Pip waiting for you](docs/toast-needs-you.png)

**[⬇️ Download Notch Pet 0.2.0 for macOS (.dmg)](https://github.com/Arpit-Krishna/notch-pet/releases/download/v0.2.0/NotchPet-0.2.0.dmg)**

## Install

**Easiest:** download the latest release, open the `.dmg` and drag Notch Pet into Applications.

### [⬇️ Download Notch Pet 0.2.0 (.dmg)](https://github.com/Arpit-Krishna/notch-pet/releases/download/v0.2.0/NotchPet-0.2.0.dmg)

[.zip instead](https://github.com/Arpit-Krishna/notch-pet/releases/download/v0.2.0/NotchPet-0.2.0.zip) · [all releases](https://github.com/Arpit-Krishna/notch-pet/releases)

The first time, right-click Notch Pet → **Open** (it isn't signed with an Apple developer certificate yet). Look at your notch. Hi Pip 👋 Turn on **Login** in the panel to keep Pip around.

**Or build it yourself** (macOS 14+ and Xcode command line tools: `xcode-select --install`):

```sh
git clone https://github.com/Arpit-Krishna/notch-pet.git
cd notch-pet
./build.sh --run
```

Run the tests (log parsers, file tailing, usage resets, hooks and alert settings):

```sh
./test.sh
```

Ship a new version: bump `VERSION`, then

```sh
./release.sh --publish  # builds the .dmg and .zip and publishes a GitHub release
```

Fun extras:

```sh
build/NotchPet.app/Contents/MacOS/NotchPet --export-pets pets.png      # render the roster
build/NotchPet.app/Contents/MacOS/NotchPet --export-biomes biomes.png  # render the biomes
build/NotchPet.app/Contents/MacOS/NotchPet --export-sounds ./sounds    # every pet's alert sounds as WAV
```

## What Pip does

| When… | Pip… |
|---|---|
| 💤 Nothing is running | sleeps |
| ⛏️ An agent is working | swings a diamond pickaxe |
| ❗ An agent needs your OK | flashes, calls you, gold swirls pour off the notch |
| 🏆 A turn finishes | hops, drops XP orbs, "Advancement made!" |
| 💀 Something errors | goes grey and sheds a tear |
| 📉 75% / 90% of a plan limit | "Running low!" / "Almost out!" |

**Hover the notch** to see every session: what it's doing, context used, cost, and your Claude and Codex limits.
**Click a session or popup** to jump straight to its window.

![The panel](docs/panel.png)

## Buttons

| Button | What it does |
|---|---|
| 🔔 Permission alerts | Pip knows the moment an agent asks for permission (adds a tiny hook, click again to remove). Codex runs it only after you trust it with `/hooks` in Codex; the bell stays amber until then. |
| 🔗 Connect Claude usage | Shows your Claude 5h and weekly limits, refreshed every 2 minutes. Uses the login saved by the `claude` terminal app (macOS asks once for Keychain access). If that login expires, run `claude` once to renew it. |
| ⚙️ Alerts | Turn popups and sounds on or off per agent and per alert (finished, needs you, error, plan limit), and set quiet hours when Pip stays silent |
| 🐾 Pet picker | Choose your pet |
| 🔊 Mute | Sounds on/off |
| ⭕ Login | Start Pip at login |

After an update, macOS may ask again for Keychain access: the Claude card shows an **Allow** button, so pick **Always Allow**.

🔔 backs up your Claude and Codex settings before changing them. 🔗 changes no settings. Codex limits need no setup.

## Pets and biomes

19 pets, each living in its own biome when you open the panel.

![All the pets](docs/pets.png)
![Biomes](docs/biomes.png)

## Sounds

Every pet has its own voice. Have a listen:
[villager](docs/sounds/villager-waiting.wav) · [warden](docs/sounds/warden-waiting.wav) · [zombie](docs/sounds/zombie-error.wav) · [wolf](docs/sounds/wolf-done.wav) · [cat](docs/sounds/cat-select.wav) · [chicken](docs/sounds/chicken-done.wav)

Want the real mob sounds? Run `./fetch-mc-sounds.sh`. They're Mojang's, so they stay on your Mac for personal use and never go in this repo.

---

**Privacy:** watching sessions is fully local, since Pip only reads the logs on your Mac. The one thing that goes online is 🔗 Connect Claude usage: it sends your Claude Code login to Anthropic's API (`api.anthropic.com`) to fetch your usage. Nothing goes anywhere else, Pip never stores the login, and there's no telemetry.

Not affiliated with Mojang or Microsoft. 💚
