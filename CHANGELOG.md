# Changelog

## 1.0.1

- Fixed recipes from a linked, guild or NPC trade skill being wrongly stored and
  shown under your name.
- Never caches a profession you do not actually have.
- Self-heal on login removes any profession that was stored by mistake.

## 1.0.0

- First release.
- Shares guild professions and skill levels addon-to-addon.
- Item search: find who can craft a given item.
- Member search and profession filter.
- Recipe tooltips on hover in item search.
- Persistent recipe cache across relogs.
- Combat-safe window (closes without taint, ESC support).
