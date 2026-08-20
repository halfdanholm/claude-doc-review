---
name: doc-review
description: Review and edit a Markdown/text document with the user, in two modes — a local browser GUI when running on their own machine (select text to comment, click a block to edit inline, autosaves), or CriticMarkup typed straight into the file when running anywhere without a reachable browser (Claude Code web, cloud sessions, CI, SSH). Use when the user wants to review/comment on a doc or draft, mark up text, edit prose, or asks to "set up doc review", "open the reviewer", or "let me comment on this file". Works on any .md/.txt file.
---

# Doc review

Review a Markdown document with a human. Comments live in a sidecar
(`<doc-dir>/.review/<doc>.comments.json`) so the document itself stays clean.

`reviewer.py` and `review.py` sit in this skill's directory — referred to below as
`$SKILL_DIR`. That is `~/.claude/skills/doc-review/` for a user-level install, or
`.claude/skills/doc-review/` when vendored into a repo. Stdlib-only Python, no
installs. State always lives in a `.review/` folder beside the target document,
never beside the scripts, so the scripts are relocatable.

## Which mode am I in?

The question is whether the user's browser can reach a port on the machine this
session is running on.

- **Local session** — Claude Code desktop or CLI on the user's own machine →
  **GUI mode**. Start `reviewer.py`, give them the URL.
- **Remote session** — Claude Code web, a cloud sandbox, CI, a container, an SSH
  host → **CriticMarkup mode**. A server here binds to *this* machine's loopback,
  which the user's browser cannot reach. There is no port forwarding. Do not start
  it, and do not offer to. Say so plainly and use CriticMarkup.

If you cannot tell, ask. One question is cheaper than a server nobody can open.

## GUI mode

```
python3 $SKILL_DIR/reviewer.py --file "<absolute path to doc.md>" [--port 8042]
```

Run it in the background, then tell the user to open `http://localhost:<port>`.
Port taken (`Address already in use`)? Free it with
`lsof -ti tcp:8042 | xargs kill -9`, or pass another `--port`.

The user selects text to comment (no markup to type), and clicks any block to
edit it as raw Markdown in place (re-renders on blur). Edits autosave. A **Copy
for Docs** button puts clean rich text on the clipboard for pasting into Google
Docs — with a selection it copies just those blocks, otherwise the whole
document. The rendered preview pulls a Markdown library from a CDN, so styling
needs internet; offline it falls back to raw text and commenting still works.

## CriticMarkup mode

No server, no browser. The user writes markup directly into the `.md` — in any
editor, GitHub's web editor, or github.dev (press `.` on a GitHub repo) — and
`review.py status` reads it exactly as it reads GUI comments:

| Markup | Meaning |
|---|---|
| `{>>comment<<}` | a comment at that spot |
| `{==text==}{>>comment<<}` | mark specific text, then comment on it |
| `{++added++}` | insert this |
| `{--removed--}` | cut this |
| `{~~old~>new~~}` | replace old with new |

Prose the user simply retyped is caught by the baseline diff, so they never have
to mark a rewrite.

**Tell the user these forms when you hand off to markup review.** They cannot
guess them, and `{>>...<<}` is the only one most people need.

### Getting the file to the user, and their comments back

In a remote session the document has to travel. Git is the simplest channel, and
the sidecar design makes it clean: **comments live in `.review/`, edits live in
the `.md`**. If the user only comments and you only edit, the two sides never
touch the same file and cannot conflict.

Commit `.review/` — it is the review channel, not build output. A repo whose
`.gitignore` lists `.review/` will silently drop every comment.

`scripts/sync.sh` in this repo automates the round trip; see its README section.

## First use on a document

Initialise tracking once, so the baseline diff has something to compare against:

```
python3 $SKILL_DIR/review.py sync --file "<doc>"
```

## The iteration loop

1. The user comments and/or edits — GUI, CriticMarkup, or both.
2. When they say they have done a pass:
   ```
   python3 $SKILL_DIR/review.py status --file "<doc>"
   ```
   Prints, in one place:
   - **GUI comments** — the exact text marked, its line, any prior reply. A
     comment whose marked text no longer exists is flagged "TEXT CHANGED".
   - **Inline comments / proposed edits** — CriticMarkup found in the file.
   - **Direct edits** — prose changed by typing over it, word-diffed against the
     last baseline. Treat as intentional.
3. Address each item. **Make your own edits as suggestions, not silent changes**,
   so the user can judge them: write CriticMarkup into the document —
   `{~~old~>new~~}` to reword, `{++added++}` to insert, `{--removed--}` to cut.
   The GUI renders these as tracked changes (green added, struck red removed)
   live, and the user can accept, reject, or comment on each. Reply and resolve
   with:
   ```
   python3 $SKILL_DIR/review.py reply <id> "<message>" --file "<doc>"
   python3 $SKILL_DIR/review.py resolve <id> [<id>…] --file "<doc>"
   ```
4. Reset the baseline so the next round's diff is clean:
   ```
   python3 $SKILL_DIR/review.py sync --file "<doc>"
   ```
5. Repeat until the user is done.

**Exception — structural rewrites the user has already asked for.** Wrapping a
whole replaced section in `{--…--}`/`{++…++}` is noise, not review value: they
decided already, and the deleted text is what they rejected. Replace outright and
say what you did.

## Answer the comment that was written, not the one you expected

Comments are terse. "Remove the word", "too easy", "no" — a three-word note can
have two readings that imply very different work. Pick the reading a careful
colleague would, do it, and **say which reading you took** in your reply, so one
sentence from the user corrects it. Do not silently guess, and do not stall the
whole pass waiting on one ambiguous note while ten unambiguous ones go unaddressed.

## Concurrent editing — the one real hazard

The user editing in the GUI while you edit with the Edit tool will clobber
someone's work: their autosave lands between your read and your write, your change
reverts theirs, and neither of you notices.

- **Re-read immediately before every edit** once a review session is live.
- A "file modified since read" error means they are typing *right now*. Re-read
  and merge; never retry the same edit blindly.
- **Split by file** when you can: the user comments (touches only `.review/`), you
  edit (touches only the `.md`). Then nothing overlaps. Worth proposing out loud.

## Other commands

```
python3 $SKILL_DIR/review.py clean  --file "<doc>"   # print with all CriticMarkup applied
python3 $SKILL_DIR/review.py accept --file "<doc>"   # apply inline CriticMarkup in place
```
