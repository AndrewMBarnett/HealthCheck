# Health Check

![](https://img.shields.io/github/v/release/AndrewMBarnett/HealthCheck)&nbsp;![](https://img.shields.io/github/downloads/AndrewMBarnett/HealthCheck/latest/total)&nbsp;![](https://img.shields.io/badge/macOS-12.0%2B-success)

![GitHub issues](https://img.shields.io/github/issues-raw/AndrewMBarnett/HealthCheck) ![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/AndrewMBarnett/HealthCheck) ![GitHub pull requests](https://img.shields.io/github/issues-pr-raw/AndrewMBarnett/HealthCheck) ![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed-raw/AndrewMBarnett/HealthCheck)

Health Check is a Jamf Pro script that runs inventory, policy check-in, and Jamf Protect check-in with a live progress window powered by [swiftDialog](https://github.com/swiftDialog/swiftDialog).

Macadmins Slack channel: [#healthcheck](https://macadmins.slack.com/archives/C078DHD29K7)

Heavily inspired by Dan Snelson's [Inventory Update Progress](https://snelson.us/2024/02/inventory-update-progress-2/).

---

## Screenshots

<img width="712" alt="HealthCheck-StartUp" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/3bf173c6-f41a-4955-be3e-684615f0b454">
<img width="712" alt="HealthCheck-SubmitInventory" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/4314ab6f-d6c9-41c1-bcd3-4dcf4d18ec34">
<img width="712" alt="HealthCheck-Complete" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/10f137f4-61b9-4097-abbc-c787ad818821">
<img width="712" alt="HealthCheck-HelpMessage" src="https://github.com/AndrewMBarnett/HealthCheck/assets/138056529/a9fc2e06-32d2-44f7-b43d-51f264e87ebb">

---

## Requirements

| Requirement | Details |
|---|---|
| macOS | 12.0 (Monterey) or later |
| [swiftDialog](https://github.com/swiftDialog/swiftDialog) | 2.4.0 or later (auto-installed if missing) |
| Jamf Pro | Any supported version |
| Jamf Protect | Optional — check-in step is skipped if not installed |
| Privileges | Must run as `root` (standard for Jamf policies) |

The script logs to `/var/log/healthCheck.log` on the client.

---

## Features

- **Live progress window** via swiftDialog showing each step as it runs
- **Smart freshness check** — skips inventory if it was updated recently (configurable threshold)
- **Flexible operation modes** — run any combination of inventory, policy, and Protect check-in
- **Silent modes** — run a full Health Check without any dialog window
- **Jamf Protect aware** — automatically skips the Protect step if not installed
- **Webhook notifications** — sends results to Slack and/or Microsoft Teams when complete
- **Custom branding** — uses your Self Service app icon as an overlay, with SF Symbol icons for desktop vs. laptop
- **Self Service compatible** — dedicated mode always runs regardless of freshness state

---

## Script Parameters

Configure these in the Jamf Pro policy that runs the script.

| Parameter | Label | Default | Description |
|---|---|---|---|
| `$4` | Seconds To Wait | `86400` | How stale the inventory delay file must be (in seconds) before a full update runs. `86400` = 1 day. |
| `$5` | Estimated Total Seconds | `120` | Used to calculate the progress bar percentage during recon. Tune to your environment. |
| `$6` | Operation Mode | _(empty)_ | Controls what the script does. See [Operation Modes](#operation-modes) below. |
| `$7` | Webhook Enabled | _(empty)_ | Set to `true` to send a webhook notification on completion. |
| `$8` | Teams Webhook URL | _(empty)_ | Incoming webhook URL for Microsoft Teams. |
| `$9` | Slack Webhook URL | _(empty)_ | Incoming webhook URL for Slack. |
| `$10` | Dialog Progress Text | `false` | Set to `true` to show live log output in the progress text area. `false` shows fixed descriptive text. |
| `$11` | Policy Trigger | _(empty)_ | Jamf policy event trigger to use for the policy check-in step. If blank, runs a general check-in. See [Policy Trigger](#policy-trigger) below. |

---

## Operation Modes

Set via **Parameter 6**. Behavior differs depending on whether the inventory delay file is **fresh** (age < Seconds To Wait) or **stale** (age ≥ Seconds To Wait).

| Operation Mode | Fresh Behavior | Stale Behavior |
|---|---|---|
| _(empty / Default)_ | Shows "update not required" dialog (if enabled) | Runs full Health Check with dialog |
| `Self Service` | Always runs full Health Check with dialog | Always runs full Health Check with dialog |
| `Inventory` | Skips (inventory is fresh) | Runs inventory update with dialog |
| `Inventory Force` | Forces inventory update with dialog | Forces inventory update with dialog |
| `Policy` | Skips (inventory is fresh) | Runs policy check-in + final recon with dialog |
| `Policy Force` | Forces policy check-in + final recon with dialog | Forces policy check-in + final recon with dialog |
| `Protect` | Skips | Runs Jamf Protect check-in silently |
| `Protect Force` | Forces Jamf Protect check-in with dialog | Forces Jamf Protect check-in with dialog |
| `Silent` | Exits cleanly with no action | — |
| `Silent Self Service` | — | Full Health Check, no dialog |
| `Silent Self Service Force` | Full Health Check, no dialog | Full Health Check, no dialog |
| `Uninstall` | Removes client-side delay file | Removes client-side delay file |

> **Tip:** Use `Self Service` as the operation mode when the policy is triggered from Self Service so users always see progress, regardless of freshness.

---

## Policy Trigger

**Parameter 11** lets you scope the policy check-in step to a specific Jamf event trigger instead of running a general check-in.

**Why use a trigger?**
A general `jamf policy` check-in runs every recurring policy scoped to the device, which may include unrelated policies. A targeted trigger ensures Health Check only runs the specific set of policies you intend.

**Setup:**
1. Create a Jamf policy with a custom trigger (e.g., `healthCheckUpdates`)
2. Scope it to the devices that should receive updates during a Health Check
3. Set Parameter 11 to `healthCheckUpdates` in the Health Check policy

The policy check-in always runs with `-forceNoRecon -doNotRestart -noInteraction -skipAppUpdates` to prevent embedded policy actions from interfering with progress detection.

---

## Webhook Notifications

Enable by setting **Parameter 7** to `true` and providing at least one webhook URL (Parameters 8 or 9).

Webhook payloads include:
- Serial number and computer name
- Computer model
- Logged-in user
- Operation mode
- Direct link to the computer record in Jamf Pro

### Slack

1. Create an [Incoming Webhook](https://api.slack.com/messaging/webhooks) in your Slack workspace
2. Set **Parameter 7** to `true`
3. Paste the webhook URL into **Parameter 9**

### Microsoft Teams

1. Add an Incoming Webhook connector to your Teams channel
2. Set **Parameter 7** to `true`
3. Paste the webhook URL into **Parameter 8**

---

## Customization

### Branding

Edit the variables near the top of the script:

```zsh
supportTeamName="Your IT Team Name"
supportTeamPhone="+1 (555) 000-0000"
supportTeamEmail="support@example.com"
supportTeamWebsite="support.example.com"
```

These populate the help message shown when a user clicks the **?** button in the dialog.

### Overlay Icon

The script automatically extracts your organization's Self Service app icon and uses it as the dialog overlay icon. Set `useOverlayIcon="false"` to disable this.

### Desktop vs. Laptop Icon

The main dialog icon automatically switches between a desktop and laptop SF Symbol based on whether the Mac has a battery.

### Progress Text

- `dialogProgressText="false"` (default) — shows a fixed descriptive message at each step
- `dialogProgressText="true"` — streams the live jamf log output into the progress text area

---

## Client-side Log

All activity is logged to `/var/log/healthCheck.log`. Log entries are prefixed with the current step:

| Prefix | Meaning |
|---|---|
| `[PRE-FLIGHT]` | Startup validation checks |
| `[NOTICE]` | Key milestones |
| `[INFO]` | General informational output |
| `[WARNING]` | Non-fatal issues (increments error count) |
| `[ERROR]` | Errors (increments error count) |
| `[FATAL ERROR]` | Unrecoverable errors (script exits immediately) |
| `[QUIT]` | Cleanup and exit steps |

---

