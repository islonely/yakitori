# AGENTS.md

## Purpose

This file contains general operating instructions for coding agents working in this repository.

These rules describe **how the agent should work**. They are not a replacement for the project's product specification, roadmap, or technical documentation.

Read this file before making changes.

---

## 1. Protect Existing Work

- Treat the existing repository as valuable user work.
- Do not assume the repository is in the state you expect.
- Inspect the current implementation before changing it.
- Do not rewrite, remove, or reorganize working code without a concrete reason.
- Do not make unrelated changes while completing a task.
- Preserve existing behavior unless the requested change intentionally changes it.
- If you discover unrelated problems, report them rather than fixing them opportunistically.
- Never use destructive changes as a shortcut.

---

## 2. Git Status Comes First

Before making changes:

1. Run `git status`.
2. Inspect the current branch.
3. Check for uncommitted changes.
4. Understand what work is already in progress.
5. Do not overwrite, discard, reset, or revert existing uncommitted work.

If there are existing uncommitted changes:

- Work around them when possible.
- Do not assume they belong to you.
- Do not `git reset --hard`.
- Do not use `git checkout --`, `git restore`, or equivalent destructive commands against existing work unless explicitly instructed.
- If the requested task conflicts with existing uncommitted work, stop and explain the conflict before destroying or replacing anything.

---

## 3. Back Up Before Database Changes

**Never make a potentially destructive database change without first creating a current backup.**

This includes:

- Schema migrations
- Dropping tables or columns
- Changing data types when migration behavior could be destructive
- Bulk updates
- Bulk deletes
- Data transformations
- Deduplication
- Imports that may overwrite existing records
- Scripts that modify many records
- Rebuilding or regenerating persistent data
- Any operation whose failure could corrupt or irreversibly alter existing data

Before such an operation:

1. Identify which database and environment are being modified.
2. Confirm that the database is the intended one.
3. Create a usable backup.
4. Verify that the backup was actually created successfully.
5. Only then perform the change.

A migration file is **not** a backup.

### Database safety rules

- Never delete production or development records merely to make code work.
- Never empty a table as a troubleshooting shortcut.
- Never drop and recreate a database to fix an application problem unless explicitly instructed.
- Never modify existing user data simply to make tests pass.
- Prefer migrations that preserve existing records.
- Test migrations against a copy or isolated test database before applying them to the working database when practical.
- If a migration could cause data loss, explain the risk before proceeding.
- If the backup fails, **do not proceed with the destructive operation**.

### Test databases

Tests that modify persistent data must use:

- An isolated test database,
- Temporary fixtures,
- Or another explicitly non-production data store.

Never point destructive tests at the user's real database.

---

## 4. Never Delete Data to Fix a Problem

Deleting data is not a substitute for fixing code.

Do not:

- Delete rows because the application cannot currently parse them.
- Delete records because a new schema does not match them.
- Delete duplicate-looking records without a defined rule and backup.
- Delete old records simply because they are inconvenient.
- Reset the database because a test is failing.
- Remove user-created content to get the application into a clean state.

If existing data exposes a bug:

> Fix the code or write a proper migration.

If data genuinely needs to be removed as part of the requested feature, make the operation explicit, backed up beforehand, tested, and reversible where practical.

---

## 5. Do Not Guess About the Existing Code

Before changing a system:

- Read the relevant files.
- Trace the relevant code path.
- Identify the source of truth.
- Inspect related models, services, repositories, and tests.
- Check how the existing implementation is actually used.
- Search the repository for references before renaming or removing symbols.

Do not infer that a function, model, database table, setting, or API works a certain way merely because its name suggests it does.

---

## 6. Make the Smallest Reasonable Change

Prefer a focused change over a broad rewrite.

A good implementation:

- Changes only what is necessary.
- Reuses existing abstractions when appropriate.
- Preserves existing interfaces when practical.
- Avoids unnecessary dependencies.
- Avoids premature generalization.
- Does not refactor unrelated code just because it could be cleaner.

Do not turn a small feature request into a repository-wide refactor.

If a larger refactor is genuinely necessary, explain why and establish a safe rollback point first.

---

## 7. Inspect Before Refactoring

Before a significant refactor:

1. Establish what the current code does.
2. Identify the behavior that must remain unchanged.
3. Inspect existing tests.
4. Add missing tests where appropriate.
5. Make the refactor in small steps.
6. Run relevant tests after each meaningful stage.
7. Review the final diff.

Do not perform a large rewrite and hope that tests catch everything afterward.

---

## 8. Test Your Changes

Do not claim that a change works without testing it when testing is reasonably possible.

After making changes, run the appropriate:

- Unit tests
- Integration tests
- Build
- Type checking
- Linting
- Migration checks
- UI tests
- Manual verification

Use the repository's existing test/build commands when available.

If tests cannot be run, say so explicitly.

If a test fails:

- Investigate the failure.
- Do not delete data to make it pass.
- Do not weaken or remove the test merely because the implementation fails it.
- Do not hide errors.
- Fix the underlying problem or clearly report the blocker.

---

## 9. Review the Diff Before Committing

Before every commit:

1. Run `git status`.
2. Review `git diff`.
3. Review staged changes.
4. Confirm only intended files changed.
5. Check for accidental generated files.
6. Check for secrets or credentials.
7. Check for debugging code.
8. Check for accidental data changes.
9. Run relevant tests.
10. Confirm the commit represents one logical change.

Never blindly commit everything in the working tree.

---

## 10. Commit Frequently and Logically

Use small, meaningful commits.

Prefer commits such as:

```text
feat: add session persistence
fix: handle application termination
test: add migration coverage
refactor: separate tracking service from UI
docs: update setup instructions

---

## 11. Transient Keystroke Buffer Policy

This project permits one narrow exception to the "never handle typed content"
rule, so that word counts remain useful in writing applications that do not
expose a native word count.

**Permitted:** a session-scoped, in-memory buffer of typed characters used only
to estimate `wordsAdded`, `wordsRemoved` and `netWordChange`, including deletion
operations (backspace, option+delete, cmd+delete, forward delete).

**Strict constraints — do not relax these:**

1. The buffer lives **only in memory**. Never write it to the database, logs,
   exports, diagnostics, telemetry, crash reports, or any file.
2. It is created when a session starts and destroyed when the session ends,
   when tracking stops, or when the application terminates.
3. It is never populated while Secure Input is active (e.g. password fields)
   and must be cleared if Secure Input becomes active.
4. It is used only when the active application's adapter does not provide a
   native word count. Native counts always take precedence.
5. Derived counts are clearly labelled as estimates in the data model and UI.
   Never present an estimate as exact.
6. The feature is disclosed to the user and can be disabled.

The prohibition on reading the clipboard, taking screenshots, requiring Full
Disk Access, and logging manuscript content is unchanged. When in doubt, prefer
privacy over precision.
