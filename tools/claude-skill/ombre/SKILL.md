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
ombre tabs                          the spaces and their tabs (JSON, see below)
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

`ombre tabs` answers an array of spaces, each
`{"id", "name", "active", "tabs": [{"id", "title", "name", "address", "kind", "active"}]}`
(`kind`: `normal`, `pinned` or `favorite`; `name`: the name the user gave the tab,
or its `title`, the page's title). `read` answers
`{"id", "title", "address", "text", "truncated"}` (the page's visible text, not
its HTML); `js` answers `{"id", "title", "address", "result"}`.

Without a tab id, commands act on the active tab. Tab ids come from `ombre tabs`
or from the reply of `ombre open`; a tab keeps its id until it is closed. For
`fill` and `js`, `-` reads the text or code from standard input.

`read`, `capture`, `click`, `fill`, `back`, `forward` and `reload` wait for the
page to load (10 s at most). `js` does **not** wait: `ombre wait -t <id>` first.
`js` and `read` give up after 15 s; a script that timed out may still have
changed the page. A script's result is capped at 100,000 characters.

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
- **Look before acting**: `ombre read` shows what the page says, `ombre capture`
  how it looks; neither shows its HTML. To find selectors, with page actions
  on: `ombre js 'return [...document.querySelectorAll("input,button,a")].slice(0,50).map(e => e.outerHTML.slice(0,200))'`.
  Without them, try a selector with `ombre wait '<selector>' --timeout 2`
  (it only reads the page).
- Prefer stable selectors (ids, `name`, `aria-label`, `data-*`) over long
  positional ones.
- **Be a guest**: `open`, `show` and `close` change what the user sees. Close
  only the tabs you opened (a pinned or favorite tab stays in the sidebar when
  closed), and don't switch tabs the user is working in without a reason.

## Limits

- **http and https only**: no `file:`, `about:` or other schemes.
- **Never private windows nor Little Ombre**: only the front normal window's
  tabs. If the user only has a private window open, there is nothing to drive.
- **Never passwords**: `fill` refuses password fields, and the keychain and
  Ombre's passwords are out of reach. Never read or set a password field with
  `js` either, and never ask the user for a password to type it yourself: let
  them sign in.
- **Page actions need a setting**: `click`, `fill` and `js` work only with
  Settings › General › *Allow agents to act in pages* on (off by default). Ask
  the user to turn it on if you need them; do not work around it.
- Each app is allowed once per session: the first command shows the user a
  question in Ombre ("… wants to control Ombre"). Tell the user to answer it.
  A session lasts until Ombre quits, the user chooses Stop Agent Control, or an
  hour passes without a command; a refusal lasts as long.
- The very first time, macOS itself asks whether your terminal may control
  Ombre (Automation).
- `js` sees everything the page holds, including what the user typed: run only
  what the task needs, read rather than change, and never send page content
  anywhere.

## Errors and what to do

Errors come back on standard error, in English (exit code 1; 2 for a wrong
use of the command, such as a bad `--timeout`). osascript may add a code such
as `(-10000)` at the end.

- **`Not authorized to send Apple events to Ombre. (-1743)`**: macOS refused
  your terminal. Ask the user to allow it in System Settings › Privacy &
  Security › Automation; don't retry in a loop.

- **`Agent control is off…`**: the user must turn on Settings › General ›
  *Allow agents to control Ombre*. Ask them; then retry.
- **`Page actions are off…`**: `click`, `fill` and `js` need *Allow agents to
  act in pages*. Ask the user, or do the task with `read` and `open` only.
- **`The user denied this app control of Ombre for this session.`**: stop and
  tell the user; do not retry in a loop. A new session asks again.
- **`The user didn't answer in time: try again.`**: tell the user a question is
  waiting in Ombre, then retry once.
- **`No Ombre window is open…`**: ask the user to open a normal Ombre window.
- **`No tab with this id: ask list tabs again.`**: the tab was closed; run
  `ombre tabs` for the current ones.
- **`No tab is active: give a tab id.`**: pass `-t <id>` (or the id).
- **`This tab's page isn't loaded: activate it first.`**: `ombre show <id>`, then
  retry.
- **`Only http and https addresses can be opened.`** / **`Only web pages
  (http, https) can be read, captured or acted on.`**: not a web page; don't
  try other schemes.
- **`The page couldn't be captured: show its tab first.`**: `ombre show <id>`,
  then capture again.
- **`This CSS selector isn't valid.`**: fix its syntax.
- **`Password fields are never filled by agents.`**: by design; let the user
  type it.
- **`The page didn't answer in 15 seconds.`** / **`The script failed: …`**: the
  page is busy or the script threw; read the page before trying again.
- **`Nothing to go back to.`** / **`Nothing to go forward to.`**: the tab's
  history ends there.
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
