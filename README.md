# JumpMaster6000

A compact jump tracker for **World of Warcraft: Forever** (interface 16001).

**Work in progress**

JumpMaster6000 is under ~~active~~… some sort of development. The full display currently uses a **Shadow Priest mock-up theme**, which will be redesigned as more class, specialization and other themes are developed. A minimal text-only view is also available.

**Upgrading from v0.3.0 or earlier.** The first login or UI reload after updating clears your saved jump totals across every character once. Your panel position, visibility, and display mode carry over.

- **Character jumps** and **Account jumps** accumulate from the time you enable the addon. The account total combines all characters tracked in the same Forever account's local WoW settings.
- **Session jumps** and **Jumps per hour** start over at login or `/reload`. The hourly figure projects the session's average pace, including idle time.
- **Time without a jump** starts at `00:00` and resets when a jump is counted. It switches to `HH:MM:SS` at one hour.

Hover **Account jumps** for a character breakdown, **Session jumps** for your current character's last 10 completed sessions, or the **Jumps per hour** value for that character's average across recorded sessions. Session history and the character average start accumulating with this update.

## Install

In WowUp CF/Wago, select **WoW Forever**, open **Get Addons → Install from URL**, and paste `https://github.com/MrZebra34/JumpMaster6000`. WowUp uses the repository's releases to check for updates.

For a manual install, download the `-forever.zip` asset from the [latest release](https://github.com/MrZebra34/JumpMaster6000/releases/latest), extract `JumpMaster6000/` into Forever's `Interface/AddOns/`, and restart the game.

## Use

Click **−** next to the close button for the borderless view, or **+** to restore the full panel. Drag the title bar in full mode or the first row in minimal mode to move it.

The full panel expands inward from the minimal view's position. Place it in the bottom right to expand up and left. Minimizing returns it to its compact position.

The full panel uses the Shadow Priest artwork on every character during the pilot. The largest tile shows character jumps. Account and session jumps sit to its right, with pace and the timer along the bottom.

Use the close button to hide the panel and `/jm6k` or `/jumpmaster6000` to bring it back. Tracking continues with the panel hidden. WoW saves your totals, panel position, and display mode on normal logout, exit, or UI reload.

The addon watches the player's jump action and looks for takeoff. Credited takeoffs must be at least 300 ms apart. The rolling budget allows up to two credits in a second and refills at 1.3 credits per second, so occasional quick jumps can still count.

Within 0.7 yards of the first takeoff in a streak, jumps earn credit at most once every 0.8 seconds. After ten credits in that spot, move outside the radius to start a new streak.

A takeoff after less than 50 ms of sampled ground contact can still count once WoW reports 200 ms of continuous airtime. This helps filter brief movement flickers on slopes while allowing quick re-jumps.

Jumps from the water's surface can earn credit when Forever reports a clear airborne exit after a tap or held jump input. Each re-hop needs a fresh water contact and uses the standard jump credit budget.

A transparent Shadow Priest overlay appears after more than 1.5 seconds of uninterrupted airtime. The timer sits between Longest Air Time and Total Air Time. The diamond ornament fills toward your previous airtime record and stays full if you pass it. The final reading holds for up to three seconds after landing. A new takeoff clears it and starts its own timer. Longest and total are saved per character and include dry jumps and falls. Water contact cancels the current airtime attempt. Air Time resumes after returning to dry ground. Flight paths, active flying, and vehicle travel are excluded.

Open WoW's **Edit Mode** to preview and drag **Air Time**. Its position saves when you drop it and is shared across characters.

A fall that starts at nearly the same time as a jump press can be misclassified. The panel uses bundled Shadow Priest artwork and WoW's built-in fonts.
