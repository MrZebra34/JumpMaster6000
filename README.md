# JumpMaster6000

A compact jump tracker for **World of Warcraft: Forever** (interface 16001).

**Work in progress**

JumpMaster6000 is under ~~active~~… some sort of development. It has a themed full panel and a minimal text-only view.

**Upgrading from v0.3.0 or earlier.** The first login or UI reload after updating clears your saved jump totals across every character once. Your panel position, visibility, and display mode carry over.

- **Character jumps** and **Account jumps** accumulate from the time you enable the addon. The account total combines all characters tracked in the same Forever account's local WoW settings.
- **Session jumps** and **Jumps per hour** start over at login or `/reload`. The hourly figure projects the session's average pace, including idle time.
- **Time without a jump** starts at `00:00` and resets when a jump is counted. It switches to `HH:MM:SS` at one hour.

Hover **Account jumps** for a character breakdown, **Session jumps** for your current character's last 10 completed sessions, or the **Jumps per hour** value for that character's average across recorded sessions. Session history and the character average start accumulating with this update.

## Install

In WowUp CF/Wago, select **WoW Forever**, open **Get Addons → Install from URL**, and paste `https://github.com/MrZebra34/JumpMaster6000`. WowUp uses the repository's releases to check for updates.

For a manual install, download the `-forever.zip` asset from the [latest release](https://github.com/MrZebra34/JumpMaster6000/releases/latest), extract `JumpMaster6000/` into Forever's `Interface/AddOns/`, and /reload or restart the game.

## Use

Click **−** next to the close button for the borderless view, or **+** to restore the full panel. Drag the title bar in full mode or the first row in minimal mode to move it.

The full panel expands inward from the minimal view's position. Place it in the bottom right to expand up and left. Minimizing returns it to its compact position.

The full panel has artwork for all 27 Forever specializations. It follows the talent tree with the most spent points in the active build. A tie or a build with no spent points uses the original Shadow Priest panel. The largest tile shows character jumps. Account and session jumps sit to its right, with pace and the timer along the bottom.

Right-click anywhere on the full or minimal tracker to open the theme selector, or use **`/jm6k themes`**. Pick a class and specialization to apply that theme for the current session, choose **Original Shadow Priest**, or select **Automatic** to follow your talents.

Use the close button to hide the panel and `/jm6k` or `/jumpmaster6000` to bring it back. Tracking continues with the panel hidden. WoW saves your totals, panel position, and display mode on normal logout, exit, or UI reload.

On land, a jump input can earn one credit when WoW reports a new takeoff. A sampled landing allows the next jump to count immediately while moving. Extra presses during the same flight earn no additional credit.

Moving dry jumps earn credit according to the time between observed takeoffs. From a fresh start, jumps spaced 0.20 seconds apart earn 12 credits over 20 jumps and 150 over 300. A run of 100 jumps earns 50 credits at 0.40-second spacing, 75 at 0.50, or 90 at 0.55. At 0.60 seconds or more each jump is eligible for full credit. The limiter carries partial credit between jumps and allows up to 75 credits in any 30 seconds. Changing direction or moving to a new spot carries the same limits forward.

During a lightly used 30-second window, up to three quick takeoffs that cadence would skip can earn credit early. If fast jumping continues, later cadence credits repay the advances. Ordinary jumps spaced at least 0.60 seconds apart are exempt from repayment. The burst and rolling limits still apply.

Within 0.7 yards of the first takeoff in a streak, jumps earn credit at most once every 0.8 seconds. After ten credits in that spot, move outside the radius to start a new streak.

Jumps from the water's surface can earn credit when Forever reports a clear airborne exit after a tap or held jump input. Each re-hop needs a fresh water contact. Surface jumps retain their 0.30-second minimum spacing and a separate reserve of 1.7 credits refilling at 1.3 per second.

A transparent Shadow Priest overlay appears after more than 1.5 seconds of uninterrupted airtime. The timer sits between Longest Air Time and Total Air Time. The diamond ornament fills toward your previous airtime record and stays full if you pass it. The final reading holds for up to three seconds after landing. A new takeoff clears it and starts its own timer. Longest and total are saved per character for completed dry jumps and falls longer than 1.5 seconds. Water contact cancels the current airtime attempt. Air Time resumes after returning to dry ground. Flight paths, active flying, and vehicle travel are excluded.

The minimal view shows Total Air Time and Longest Air Time. In the full view, hover over **Jumps per hour** to see both values. Open WoW's **Edit Mode** to preview and drag **Air Time**. Its position saves when you drop it and is shared across characters.

A fall that starts at nearly the same time as a jump press can be misclassified. The panel uses bundled artwork and WoW's built-in fonts.
