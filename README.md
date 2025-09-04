# Tactica
## Auto-build raids (invite/gearcheck), post tactics, set loot rules & assign roles - synced!
Tactical addon for raid leading with ease — post ~90 clear boss strategies (or add your own), auto-build raids (LFM creator/poster with auto-invite/auto-gearcheck/auto-assign), assign & sync roles in raid roster, and smooth out loot mode changes, all in one place.

_Access all functionalities and commands via **Minimap Icon**_ (<img width="15" height="15" alt="Tactica-Icon" src="https://github.com/user-attachments/assets/0e7b9ac6-d5c4-4f7e-b944-9fc8f96ec73b" />).


## What it does (TL;DR)
### 1. Announce tactics fast
- Post default or custom strategies to self or raid with one click or `/tt post` commands. Auto-popup on boss (toggleable).
- `/tt post` for settings and frame.
- `/tt auto` toggles the auto-popup on boss (same as the checkbox in **/tt options**).
- `/tt list` for all raid tactics available (default and custom).
- `/tt add` to add your custom tactics ("enter" for line breaks will divide tactic into separate /raid msg's).
- `/tt remove` to remove your custom tactics.
- `/tt <Raid Name>,<Boss Name>,[Tactic Name(optional)]` for macro use of Tactica tactics.
<img width="269" height="227" alt="Tactica-Post" src="https://github.com/user-attachments/assets/9879895e-5b73-4098-88f9-d298b794a349" />
<img width="497" height="370" alt="Tactica-Add" src="https://github.com/user-attachments/assets/95ed350c-f5a6-45ef-bc4f-aa5a8a8beff3" />

### 2. Organize your comp at a glance
- Right-click raid roster to Toggle as Healer / DPS / Tank. Roles sync to everyone running Tactica; latest leader/assist decision wins.
- Clean indicators next to names (H/D/T).
- pfUI (optional): Tactica’s Tank role also flags the vanilla-compliant pfUI addon’s tank role when pfUI is present (requires SuperWoW).
- `/tt roles` to post the assigned and number of tanks, healers and DPS, respectively, to the raid.
- `/tt rolewhisper` toggle the role whisper function on/off (same as the checkbox in **/tt options**).
- `/tt autoinvite` or `/ttai` for standalone auto-invite frame, with auto-assign roles functionality.
<img width="492" height="327" alt="Tactica - Roster" src="https://github.com/user-attachments/assets/991708d0-b30d-402f-9eff-57cb767b9859" />
<img width="322" height="145" alt="image" src="https://github.com/user-attachments/assets/708926de-70be-45ff-a640-c5ae77d6ab8c" />

### 3. Build Raids (LFM poster/creator)
- Select raid, size and setup and Tactica will do the rest. Creating a seamless LFM message, to post in your channels.
- Choose number of SR (Soft Reserves), HR (Hard Reserves), Tanks, Healers, and whether you can Summon.
- Select Yell, LFG or/and World to post in - set optional "Auto-announce".
- Syncs with raid roster, so when you assign a role - the LFM announcement will adjust accordingly.
- Auto-invite/auto-assign/auto-gearcheck, all built-in to ease the pain.
- `/tt build` for the LFM/raid builder UI.
- `/tt lfm` posts once using your current Builder settings and respects a 30s cooldown (shared with the “Announce” button).
<img width="595" height="665" alt="Tactica-Raid Builder" src="https://github.com/user-attachments/assets/3e04ce83-9fb9-4cf2-a017-8fd88e8cdcb3" />

### 4. Loot mode QoL for bosses
- Optional auto Master Looter on boss target (RL only). After a boss is fully looted, get a popup to switch back (e.g., to Group Loot). (same as the checkbox in **/tt options**).
- Works even when ML ≠ RL: the ML’s client pings the RL via addon message when the corpse is emptied.
- “Don’t ask again this raid” (raid-scoped) and global on/off setting.
<img width="287" height="161" alt="Tactica-loot" src="https://github.com/user-attachments/assets/f8fcd04a-8060-4fa1-bb13-7d76810d9800" />

## Quick start
- Use the **minimap icon** — full access and command list
- `/tt` or `/tactica` or `/tt help` — full command list
- `/tt options` — open the Options UI
- Toggle auto behaviors in the option UI (checkboxes), or use the slash commands mentioned in help.
<img width="288" height="174" alt="image" src="https://github.com/user-attachments/assets/d5d322dd-9e92-447d-892c-b896e787ce1d" />

## Installation
1.  Navigate to your World of Warcraft installation folder.
2.  Go into the `Interface` -> `AddOns` directory.
3.  Place the `Tactica` folder directly into the `AddOns` folder.
4.  Restart World of Warcraft completely.

Alternatively just take add this link and add to the launcher (addon tab -> Add new addon) or similarly with GithubAddonsManager: https://github.com/Player-Doite/tactica

## Contact
Addon, logic and default tactics all made by Doite. Contact me in-game, github via "Issues" or via discord if something is wrong.

_Other debug commands are:_

_`/tactica_pfui` — show pfUI & SuperWoW detection status_

_`/tactica_pfuitanks` — list pfUI tank flags or check one player by adding name after_

_`/tactica_loot` — shows the group loot question frame_

_`/ttversion` Prints your local Tactica version (from the TOC)_

_`/ttversionwho` Raid-only. Broadcasts a version “WHO” ping and prints replies (who’s newer/older/equal)._

_`/ttpush` or `/tactica pushroles` (raid leaders) broadcast current role list manually to the raid (should not be needed)_

_`/ttclear` or `/tactica clearroles` clear all roles (local; if raid leader, clears for everyone)_

## Special thanks to:
[jrc13245](https://github.com/jrc13245/) - error catcher

[i2ichardt](https://github.com/i2ichardt) - for code debugging

[Shagu](https://github.com/shagu) - for coding tips
