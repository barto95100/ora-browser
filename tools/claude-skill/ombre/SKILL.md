---
name: ombre
description: Drive the Ombre browser (macOS) from the terminal with the `ombre` command — list, open, show, read, capture and close tabs, go back/forward/reload, wait for a page, and (when the user allowed it) click, fill in fields and run JavaScript in a page. Use it when the user asks to look at, check or act on a web page in Ombre, their own browser with their own sign-ins; not for scraping or bulk requests.
---

# Ombre

`ombre` drives the user's Ombre browser through Apple Events. It works in the
user's real browser, with their sessions and cookies: act as a careful guest.

## When to use it

- The user asks you to open, read, check, capture or act on a page **in Ombre**
  (their signed-in sites, an intranet, a page they have open).
- You need what a real browser shows (JavaScript-rendered pages, a signed-in
  view), not just an HTTP response.

Prefer `curl` or a fetch tool for public pages that need no sign-in and no
JavaScript. Never use Ombre for bulk crawling.

## Commands

```
ombre tabs                          spaces and their tabs (JSON: id, title, address, kind, active)
ombre open <address>                opens an http(s) address in a new tab; prints the tab
ombre show <tab id>                 shows a tab (and its space)
ombre close <tab id>                closes a tab
ombre read [<tab id>]               title, address and text of a page (JSON; "truncated" if long)
ombre capture [<tab id>] [-o file]  a PNG of the page as shown; prints the file's path
ombre back|forward|reload [-t id]   navigates, then waits for the load
ombre wait [<selector>] [-t id] [--timeout s]
                                    waits for the load, then for an element (10 s, at most 60)
ombre click <selector> [-t id]      clicks the first element matching the CSS selector
ombre fill <selector> <text> [-t id]
                                    types into a field (never a password field)
ombre js <code> [-t id]             runs JavaScript (an async function's body; `return` gives JSON)
```

Without a tab id, commands act on the active tab. Tab ids come from `ombre tabs`
or from the reply of `ombre open`. For `fill` and `js`, `-` reads the text or
code from standard input.

## Reliable sequences

- **Open, then read**: `ombre open https://example.com` → take the `id` from the
  reply → `ombre read <id>`. `read` waits for the load (10 s at most).
- **Click, then wait**: after `ombre click 'a.next'`, run `ombre wait -t <id>`:
  it waits for a load started by the click (within a second), then
  `ombre read <id>`.
- **Slow page**: `ombre wait '<selector of what you need>' -t <id> --timeout 30`
  before reading, rather than retrying `read`.
- **Fill a form**: `ombre fill '#email' 'name@example.com'`, then
  `ombre click 'button[type=submit]'`, then `ombre wait -t <id>`.
- **Look before acting**: `ombre read` (or `ombre capture`) first, so the
  selectors you use match the page as it is.
- Prefer stable selectors (ids, `name`, `aria-label`, `data-*`) over long
  positional ones.

## Limits

- **http and https only**: no `file:`, `about:` or other schemes.
- **Never private windows nor Little Ombre**: only the front normal window's
  tabs. If the user only has a private window open, there is nothing to drive.
- **Never passwords**: password fields are never filled, and the keychain and
  Ombre's passwords are out of reach. Never ask the user for a password to type
  it yourself; let them sign in.
- **Page actions need a setting**: `click`, `fill` and `js` work only with
  Settings › General › *Allow agents to act in pages* on (off by default). Ask
  the user to turn it on if you need them; do not work around it.
- Each app is allowed once per session: the first command shows the user a
  question in Ombre ("… wants to control Ombre"). Tell the user to answer it.
- `js` sees everything the page holds, including what the user typed: run only
  what the task needs, read rather than change, and never send page content
  anywhere.

## Errors and what to do

Errors come back on standard error (exit code 1), in English.

- **`Agent control is off…`**: the user must turn on Settings › General ›
  *Allow agents to control Ombre*. Ask them; then retry.
- **`Page actions are off…`**: `click`, `fill` and `js` need *Allow agents to
  act in pages*. Ask the user, or do the task with `read` and `open` only.
- **`The user denied this app control of Ombre for this session.`**: stop and
  tell the user; do not retry in a loop. A new session asks again.
- **`The user didn't answer in time: try again.`**: tell the user a question is
  waiting in Ombre, then retry once.
- **`No Ombre window is open…`**: ask the user to open a normal Ombre window.
- **`No tab with this id: ask list tabs again.`**: run `ombre tabs` and use a
  current id (tabs close, ids change).
- **`This tab's page isn't loaded: activate it first.`**: `ombre show <id>`, then
  retry.
- **`No element matches this selector.`**: `ombre read` the page, fix the
  selector, or `ombre wait '<selector>'` if it appears later.
- **`Nothing matched in …` / `The page was still loading after …`**: the page is
  slow or different from what you expect; read it, then wait longer or change
  the selector.
- **A reply or error with `loadError`** (or "The page's last load failed: …",
  or "Load error: …" after `capture`): the page shown is an error page (offline,
  wrong address, certificate). Tell the user what it says; do not act on it.
- **`This page is the answer to a form sent with POST…`**: it wasn't reloaded on
  purpose; open the page's address again instead if that's what you need.

## Debug app

`OMBRE_APP_ID=com.barto95100.ora.dev ombre tabs` drives *Ombre Dev* (the Xcode
build) instead of the installed Ombre.
