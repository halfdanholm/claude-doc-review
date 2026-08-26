# claude-doc-review

A tiny, local, dependency-free system for reviewing a Markdown document with [Claude Code](https://claude.com/claude-code) — comment by selecting text, edit prose inline, and see Claude's edits as tracked-change suggestions you can accept, reject, or comment on. Everything stays on your machine.

Two parts:

- **`reviewer.py`** — a local web GUI (Python stdlib only). Select text to comment, double-click any block to edit it inline (autosaves), download the result. Claude's edits show as suggestions: green = added, ~~struck red~~ = removed.
- **`review.py`** — the CLI Claude runs to read your comments and edits, reply, and resolve.

Comments live in a sidecar file (`.review/<doc>.comments.json`) next to the document, so the Markdown itself stays clean. Suggestions live inline as [CriticMarkup](http://criticmarkup.com/) (`{++add++}`, `{--cut--}`, `{~~old~>new~~}`), which both the GUI and `review.py` understand.

## Requirements

- Python 3 (standard library only — no `pip install`).
- A browser. The rendered preview pulls a Markdown library from a CDN, so styling needs internet; offline it falls back to raw text and commenting still works.

## Quick start

```sh
python3 reviewer.py --file path/to/your-doc.md
# open http://localhost:8042   (Ctrl-C to stop)
```

In the browser:

- **Comment** — select any text → a box pops up → type → *Comment* (⌘/Ctrl-Enter). The marked text highlights; the comment appears in the side panel.
- **Edit** — double-click any paragraph/heading/table; it becomes raw Markdown in place; click away (or Esc) and it re-renders. Edits autosave to the file. (A single click never edits, so selecting text for a comment stays easy.)
- **Suggestions** — Claude's edits render as green (added) / struck (removed). Click one to **Accept**, **Reject**, or **Comment**. They appear live without a reload.
- **Copy for Docs** — clean rich text on the clipboard for pasting into Google Docs. With a selection, just those blocks.
- **Paste from Docs** — the reverse: paste rich text copied from Google Docs (or anywhere) and it's converted back to Markdown — headings, bold/italic, links, lists, and tables. With a selection it replaces just those blocks, otherwise the whole document. Handy for editing tables in Docs, where table editing is nicer.
- **Download .md** — saves the current document.

If the port is taken: `lsof -ti tcp:8042 | xargs kill -9`, or pass `--port N`.

## The review loop

1. You comment and/or edit in the GUI.
2. Tell Claude you've done a pass.
3. Claude runs `review.py status` to read every comment (with the marked text), proposed edits, and your direct prose edits since the last baseline.
4. Claude addresses them — editing the doc (as suggestions), replying to comments — then `review.py sync` to reset the baseline.
5. Repeat.

## `review.py` commands

```sh
python3 review.py status  --file DOC     # comments + proposed edits + your direct edits since baseline
python3 review.py sync    --file DOC     # snapshot current text as the new baseline
python3 review.py reply <id> "msg" --file DOC   # reply to a GUI comment (shows in the GUI)
python3 review.py resolve <id> [<id>…]  --file DOC
python3 review.py clean   --file DOC     # print the doc with all CriticMarkup applied (clean export)
python3 review.py accept  --file DOC     # apply all CriticMarkup to the file in place
```

State lives in a `.review/` folder beside the document.

## Install as a Claude Code skill

`SKILL.md` packages this as a skill, so any session can run the loop when you ask it to "set up doc review for `<file>`".

**For every project on this machine** — copy `SKILL.md`, `reviewer.py`, and `review.py` into `~/.claude/skills/doc-review/`.

**For a specific repo, including its cloud sessions** — copy the same three files into `.claude/skills/doc-review/` in that repo and commit them. A user-level skill in `~/.claude/skills/` does not exist as far as a cloud sandbox is concerned; vendoring is what makes it available there.

## Using it from Claude Code web, or any remote session

The GUI binds to `127.0.0.1`. In a cloud sandbox, a container, or over SSH, that loopback belongs to *that* machine — your browser cannot reach it, and there is no port forwarding to arrange. So remote sessions skip the server entirely and you review in plain text instead:

Write CriticMarkup directly into the `.md`, in any editor, GitHub's web editor, or github.dev (press `.` on a GitHub repo):

| Markup | Meaning |
|---|---|
| `{>>comment<<}` | a comment here |
| `{==text==}{>>comment<<}` | mark this text, then comment on it |
| `{++added++}` | insert this |
| `{--removed--}` | cut this |
| `{~~old~>new~~}` | replace old with new |

`review.py status` reads these exactly as it reads GUI comments, and prose you simply retype is picked up by the baseline diff — so you never have to mark a rewrite. `{>>...<<}` is the only form most people need.

`SKILL.md` tells Claude to detect which situation it is in and *not* to offer a localhost URL it knows you cannot open.

### Moving the document back and forth

Git is the simplest channel, and the sidecar design keeps it clean: **comments live in `.review/`, edits live in the `.md`.** If you only comment and Claude only edits, the two sides never touch the same file, so there is nothing to conflict.

Commit `.review/` in your documents repo — it is the review channel, not build output. A `.gitignore` listing `.review/` silently drops every comment you write. (This repo ignores it because this repo holds the tool, not documents.)

`scripts/sync.sh` automates the round trip: commit, `pull --rebase`, push. It commits before rebasing so nothing can be discarded, holds an atomic lock so concurrent runs are harmless, and always exits 0 so it can't wedge a session. On a rebase conflict it stops and tells you rather than guessing.

Wire it up by merging `scripts/hooks.example.json` into `.claude/settings.json` in your documents repo — `SessionStart` pulls, `Stop` commits and pushes. Commit that settings file and cloud sessions inherit the same behaviour, so neither end has to remember.

One gap worth knowing: hooks only fire around Claude's turns. Comment in the GUI and walk away, and that work sits uncommitted until the next session. Close it with a timer (`launchd`, `cron`, `systemd --user`) running `scripts/sync.sh` every couple of minutes.

## Notes

- Nothing is sent anywhere — the server binds to `127.0.0.1` and only reads/writes the file you point it at.
- `reviewer.py` and `review.py` are relocatable: state always lives beside the document, never beside the scripts.
