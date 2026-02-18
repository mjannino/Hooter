![CI](https://github.com/mjannino/Hooter/actions/workflows/ci.yml/badge.svg)

# Hooter

Chat trigger auto-response addon for World of Warcraft. Define trigger words prefixed with `!` and Hooter will automatically reply with a random response from your configured list when someone uses one in chat.

## How It Works

Hooter listens to party, raid, guild, whisper, and instance chat for messages containing `!triggers`. When a match is found, it picks a random response from that trigger's list and sends it back to the same channel after a configurable delay. A per-trigger cooldown prevents spam.

- Triggers and responses are stored **account-wide** (shared across characters)
- Scanning can be toggled **per-character**
- Configs are shareable via compressed export/import strings

## Slash Commands

`/hooter` or `/hoot`

| Command | Description |
|---------|-------------|
| `/hooter` | Show help and current status |
| `/hooter enable` | Enable scanning on this character |
| `/hooter disable` | Disable scanning on this character |
| `/hooter add !word response text` | Add a response to a trigger |
| `/hooter remove !word` | Remove an entire trigger |
| `/hooter remove !word 2` | Remove response #2 from a trigger |
| `/hooter list` | List all triggers and their responses |
| `/hooter export !word` | Export a trigger as a shareable string |
| `/hooter import <string>` | Import a trigger from a shared string |
| `/hooter cooldown <seconds>` | Set trigger cooldown (default: 5s) |
| `/hooter delay <min> <max>` | Set response delay range (default: 0.5-3.0s) |

An options panel is also available under **ESC > Options > AddOns > Hooter**.

## Installation

Copy the `Hooter` folder into your WoW addons directory:

```
World of Warcraft/_retail_/Interface/AddOns/Hooter/
```
