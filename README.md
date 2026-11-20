# JumpMaster6000

A compact jump tracker for **World of Warcraft: Forever** (interface 16001).

**Upgrading from v0.3.0 or earlier.** The first login or UI reload after updating clears your saved jump totals across every character once. Your panel position, visibility, and display mode carry over.

- **Character jumps** and **Account jumps** accumulate from the time you enable the addon. The account total combines all characters tracked in the same Forever account's local WoW settings.
- **Session jumps** and **Jumps per hour** start over at login or `/reload`. The hourly figure projects the session's average pace, including idle time.
- **Time without a jump** starts at `00:00` and resets when a jump is counted. It switches to `HH:MM:SS` at one hour.

## Install

In WowUp CF, select **WoW Forever**, open **Get Addons → Install from URL**, and paste `https://github.com/MrZebra34/JumpMaster6000`. WowUp uses the repository's releases to check for updates.

For a manual install, download the `-forever.zip` asset from the [latest release](https://github.com/MrZebra34/JumpMaster6000/releases/latest), extract `JumpMaster6000/` into Forever's `Interface/AddOns/`, and restart the game.

## Use

Click **−** next to the close button for the borderless view, or **+** to restore the full panel. Drag the title bar in full mode or the first row in minimal mode to move it.

The full panel expands inward from the minimal view's position. Place it in the bottom right to expand up and left. Minimizing returns it to its compact position.

The full panel uses the Shadow Priest artwork on every character during the pilot. The largest tile shows character jumps. Account and session jumps sit to its right, with pace and the timer along the bottom.

Use the close button to hide the panel and `/jm6k` or `/jumpmaster6000` to bring it back. Tracking continues with the panel hidden. WoW saves your totals, panel position, and display mode on normal logout, exit, or UI reload.

The addon watches the player's jump action and looks for takeoff. There are six jump credits available, which refill at 1.5 per second. If the budget runs out, excess takeoffs are skipped. Counting resumes as credit refills.

A takeoff after less than 50 ms of sampled ground contact can still count once WoW reports 200 ms of continuous airtime. This helps filter brief movement flickers on slopes while allowing quick re-jumps.

Use `/jm6k dev` to bypass the credit budget and short-contact check for testing. It starts off each time the addon loads.

A fall that starts at nearly the same time as a jump press can be misclassified. The panel uses bundled Shadow Priest artwork and WoW's built-in fonts.
