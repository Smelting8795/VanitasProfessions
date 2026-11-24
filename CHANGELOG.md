# Changelog

## 1.0.3

- Members are now identified by their full name (first and last), so guild members
  who share a first name are told apart. The full name is sent in the message since
  the addon channel only carries the first name. Everyone must update to 1.0.3.

## 1.0.2

- Fixed members showing up twice when their realm suffix arrived inconsistently.
  Characters are now keyed by name only (unique within a guild), so no duplicates.

## 1.0.1

- Fixed recipes from a linked, guild or NPC trade skill being wrongly stored and
  shown under your name.
- Never caches a profession you do not actually have.
- Self-heal on login removes any profession that was stored by mistake.
- Cleaner profession list: one profession per line with skill values aligned in a
  column, instead of one long wrapped line.

## 1.0.0

- First release.
- Shares guild professions and skill levels addon-to-addon.
- Item search: find who can craft a given item.
- Member search and profession filter.
- Recipe tooltips on hover in item search.
- Persistent recipe cache across relogs.
- Combat-safe window (closes without taint, ESC support).
