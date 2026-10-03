---
name: fireclerk
description: Use FireClerk to inspect, extract data from, and control the user's running Firefox session through the `fireclerk` CLI. Use when a task needs live Firefox tabs, tab URLs/titles, container identity, active-tab HTML or visible text, page content from an already-open browser session, opening/closing Firefox tabs, or troubleshooting the FireClerk native messaging bridge.
---

# FireClerk

FireClerk talks to the user's running Firefox through a WebExtension and native
messaging host. Use it when the user wants information from their current
Firefox session, not when a normal HTTP fetch is sufficient.

## Quick Check

Start with:

```sh
command -v fireclerk
fireclerk ping
```

If `fireclerk` is missing, say the package is not installed on PATH. If `ping`
cannot reach the host, check the error text and guide the user through:

```sh
fireclerk --setup
```

Then ask them to load or reload the extension in Firefox from the manifest path
printed by setup. Firefox must be running and the temporary extension must be
loaded for commands to work.

## List And Select Tabs

Prefer JSON for agent parsing:

```sh
fireclerk tabs --json
```

Use the returned `id` for follow-up commands. Important fields:

- `id`: tab id for `html` or `text`
- `title`, `url`: identify the page
- `active`: whether the tab is active in its window
- `windowId`: Firefox window id
- `container`, `cookieStoreId`: container context

For container inventory:

```sh
fireclerk containers --json
```

## Open And Close Tabs

Open a new tab:

```sh
fireclerk open https://example.com
fireclerk open --background https://example.com
fireclerk open --container firefox-container-2 https://example.com
```

Open Firefox's default new tab page by omitting the URL:

```sh
fireclerk open
```

Close one or more tabs by id:

```sh
fireclerk close <tabId>
fireclerk close <tabId> <tabId>
```

List tabs first if you need the id. Do not close a tab unless the user clearly asked you to.

## Extract Page Content

Use text when the task needs readable page content:

```sh
fireclerk text <tabId>
```

Use HTML when the task needs structure, links, metadata, form fields, or exact
DOM content:

```sh
fireclerk html <tabId> --out /tmp/fireclerk-page.html
```

For the active tab, omit `<tabId>`:

```sh
fireclerk text
fireclerk html --out /tmp/fireclerk-active.html
```

For large HTML, always use `--out` and inspect the file with targeted tools
such as `rg`, `sed`, or a parser. Avoid pasting huge page content into the
conversation.

## Common Failure Modes

- `Cannot reach the FireClerk host`: Firefox is not running, the extension is
  not loaded, or `fireclerk --setup` has not been run for the installed package.
- `contextualIdentities unavailable`: Firefox containers are disabled; `tabs`
  can still work.
- `cannot read tab`: the tab may be privileged (`about:`, add-ons manager,
  `addons.mozilla.org`, view-source) or not fully loaded.
- Timeouts usually mean the extension-host bridge is disconnected; reload the
  extension and retry `fireclerk ping`.

## Response Practices

State which tab/page you inspected when reporting results. Include tab id,
title, and URL when relevant. If content extraction fails because Firefox or the
extension is not ready, report the exact failing command and the shortest setup
step needed to unblock the user.
