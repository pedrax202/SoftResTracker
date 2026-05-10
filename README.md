# SoftRes Tracker
Repaired version of SoftResTracker addon for WOTLK 3.3.5a WoW Servers.

Original credit to "HeadGrumble" on Curseforge

A World of Warcraft **3.3.5a** addon for raid leaders and loot masters to collect and manage soft reservations via in-game whispers — no external website required.

Fully compatible with **RollFor** via a one-click export.

---

## Features

- Whisper-based SR collection — raiders whisper you directly in-game
- 1SR or 2SR mode — enforce per-player reservation limits
- Multi-item whispers — a player can reserve multiple items in a single whisper
- Duplicate protection — prevents the same player reserving the same item twice
- Scrollable SR board with item icons, player names coloured by class, and per-item clear buttons
- Missing SR tab — shows which raiders haven't used all their reservations
- Announce Missing button — broadcasts missing SR players to raid warning
- Loot button — announces all current reservations to raid chat
- How to SR button — sends whisper command instructions to raid chat
- Lock / Unlock — prevent new reservations being submitted once the raid begins
- CSV import — bulk-load reservations from a spreadsheet
- RollFor export — generate a base64 string ready to paste directly into RollFor's `/sr` import window
- Addon sync — reserve/remove/reset events broadcast to other SoftResTracker users in the raid
- Automatic roster pruning — players who leave the raid have their reserves removed automatically
- Whisper rate limiting — prevents spam (2 second cooldown per player)
- Minimap button — quick access to show/hide the board
- Persistent data — all reservations survive reloads and logouts
- Movable, lockable UI frame — drag to anywhere on screen

---

## Installation

1. Download or clone this repository
2. Place the `SoftResTracker` folder into:
   ```
   World of Warcraft\Interface\AddOns\
   ```
3. Ensure the folder is named exactly `SoftResTracker` and contains `SoftResTracker.toc`
4. Restart or reload the game (`/reload`)
5. The addon will appear in your AddOns list on the character select screen

---

## The SR Board

Open the board by clicking the minimap button or typing `/srt toggle`.

<img width="433" height="552" alt="image" src="https://github.com/user-attachments/assets/cc691ef5-90a1-4e1b-84ab-5b80e4c2caca" />

### Reserves Tab
Lists every item that has at least one reservation. Each row shows the item icon, item name, reservation count, and all players who reserved it with their names coloured by class. The **[✕]** button on each row clears all reservations for that item.

Use the search box to filter by item name or player name in real time.

### Missing SR Tab
Lists every player currently in the raid (or party) who has not used all their available SRs. Shows how many SRs each player still has remaining. Switches the footer to show the **Announce Missing** button.

---

## Footer Buttons

| Button | Action |
|---|---|
| **Loot** | Announces all current reservations to raid chat, formatted as `Item Name (Player1, Player2)` |
| **How to SR** | Sends two raid chat messages explaining the whisper commands to players |
| **Reset** | Clears all reservations after a confirmation prompt. Also broadcasts the reset to other SoftResTracker users |
| **Announce Missing** | *(Missing SR tab only)* Sends a raid warning listing all players who haven't fully reserved |

---

## Whisper Commands

Raiders whisper the **loot master** directly. No website or external tool needed.

### `-sr [item link]`
Reserve an item. The player types the command "-SR" then shift-clicks the item from Atlasloot.

```
-sr [Shadowmourne]
```

A player can reserve multiple items in a single whisper (in 2SR mode):

```
-sr [Shadowmourne] [Trauma]
```

The addon replies confirming what was reserved, or explains why a reservation was rejected (locked, limit reached, already reserved).

### `-mysr`
Check current reservations. The addon whispers back a list of all reserved items as clickable links, plus how many SR slots remain.

### `-[item link]`
Look up how many players have reserved a specific item, and who they are. Useful for raiders wanting to gauge competition.

```
-[Shadowmourne]
```

> **Note:** All whisper commands use a `-` prefix. WoW's 3.3.5a chat system blocks `?` and `/` as whisper command prefixes.

---

## Header Controls

### 1SR / 2SR
Sets the reservation limit per player. Displayed in the top-right of the board header. Can also be set with `/srt 1sr` or `/srt 2sr`.

### Lock / Unlock
Locks the SR list. Locked means no new whisper reservations will be accepted — players attempting to whisper `-sr` will receive a locked message. The button turns red when locked. Use this once the raid begins.

### Import
Opens the CSV import window. See [CSV Import](#csv-import) below.

---

## Slash Commands

All commands use the `/srt` prefix to avoid conflicts with RollFor's `/sr`.

| Command | Description |
|---|---|
| `/srt` | Show the help list |
| `/srt toggle` | Show or hide the SR board |
| `/srt 1sr` | Set 1 SR per player |
| `/srt 2sr` | Set 2 SRs per player |
| `/srt reset` | Clear all reservations |
| `/srt import` | Open the CSV import window |
| `/srt export` | Open the RollFor export window |
| `/srt clearplayer <name>` | Remove all reservations for a specific player |
| `/srt clearplayer <name> <itemID>` | Remove a specific item reservation for a player |

---

## CSV Import

Type `/srt import` or click the **Import** button to open the import window.

Paste a CSV where each row contains a player name and one or more item IDs. The addon is flexible about column order — it detects which column contains numeric item IDs automatically.

**Accepted formats:**

```
Playerone,49623
Playertwo,50818,49623
Playerthree,50818
```

Or with headers (headers are ignored automatically):

```
Name,ItemID
Playerone,49623
Playertwo,50818
```

Click **Import** to load the data. The addon reports how many reserves were added and how many rows were skipped. Existing reservations are not cleared — imported rows are merged in.

---

## RollFor Export

Type `/srt export` to open the export window. This generates a base64-encoded JSON string in the exact format RollFor expects.

**Workflow:**

1. Collect SRs as normal via whispers or CSV import
2. Type `/srt export`
3. The export string is automatically selected — press `Ctrl+C` to copy
4. Open RollFor with `/sr`
5. Paste the string into RollFor's import window and click Import

The exported data includes every player's reserved items grouped correctly, with real item quality values so RollFor's colour coding works accurately.

---

## Addon Sync

If multiple raid members have SoftResTracker installed, reserve additions, removals, and resets are broadcast automatically over the raid addon channel. All copies of the addon stay in sync in real time without any manual action.

---

## Automatic Roster Pruning

When a player leaves the raid, their reservations are automatically removed from the board and a message is printed to your chat. This keeps the SR list clean if someone drops from the raid before it starts.

---

## Persistence

All reservation data is saved to `SoftResTrackerDB` in your SavedVariables file. Your SR list survives `/reload`, disconnects, and logouts. Data is per-character.

---

## Compatibility

| | |
|---|---|
| **Game version** | World of Warcraft 3.3.5a (WotLK private servers) |
| **RollFor** | Export compatible with RollFor 1.0.1.4+ (3.3.5a port) |
| **Other addons** | No dependencies — fully standalone |

---

## Known Limitations

- Item names in whisper replies rely on the client's item cache. If an item has never been seen by the loot master's client, `GetItemInfo` may return `nil` and the addon will fall back to `Item <ID>`. Hovering over the item in game will cache it.
- The RollFor export uses `quality: 0` for any item not yet in the local cache. This does not affect RollFor's SR tracking, only the colour indicator.
- Whisper commands require the loot master to be online and logged in. The addon does not process whispers received while offline.

---

## License

MIT — free to use, modify, and redistribute.# SoftResTracker
