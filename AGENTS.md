# Repository Workflow Rules

These instructions are mandatory for every coding task in this repository.

## Branch Policy

- Never develop features directly on `main`.
- Before making changes, fetch the latest `origin` and create a branch from `main` using the `codex/<short-feature-name>` naming pattern.
- Create a new `codex/*` branch for each feature, fix, or documentation update.
- During development, commit locally only. Do not push the feature branch to GitHub at every milestone.
- Push the feature branch only when the user explicitly says to upload it. That upload request is also the merge approval: in the same step push the branch, merge it into `main`, push `main`, and delete the branch both locally and on the remote.
- Do not merge into `main` until the user explicitly approves the merge.
- Do not create a release tag or publish a release until the user explicitly approves publication.
- After the branch is merged into `main` or its changes are otherwise incorporated, delete the local and remote branch.

## Merge Reminder

- At the end of every work session, report the current branch and whether it is still unmerged.
- When a feature or fix is complete, explicitly remind the user that the branch is ready to merge and wait for approval.
- If the same `codex/*` branch remains unmerged for more than three days, prominently remind the user again.
- Never assume that silence means approval.

## Documentation Requirement

Every functional update must include documentation in the same branch:

- Update `CHANGELOG.md` with a concise description of the user-visible change.
- Update `README.md` or the relevant file under `docs/` when behavior, workflow, setup, or usage changes.
- For every large feature or fix merge, update `docs/releases/unreleased.md` with the user-visible changes, technical changes, compatibility notes, and verification performed.
- Treat `docs/releases/vX.Y.Z.md` as permanent history. Never delete, rename, or overwrite a published version record. Add corrections only in its revision section.
- When preparing a release, copy `docs/releases/unreleased.md` to `docs/releases/vX.Y.Z.md`, complete the release metadata, and add the new file to the release index.
- Keep `README.md` as the project entry document. It must never be replaced with source code.
- Keep `VERSION` and the release tag consistent when preparing a release.
- Include the documentation changes in the same commit or pull request as the functional change.

## Verification Before Merge

Before asking for merge approval:

- Build the project successfully.
- Build or validate the macOS app bundle when app behavior changes.
- Verify the app signature when packaging changes.
- Report the branch name, commit hash, changed files, tests performed, and any remaining risks.
- Confirm that the feature branch is based on the latest `main`.

## Release Policy

After explicit approval only:

1. Push the approved `codex/*` branch to GitHub, then merge it into `main`.
2. Update `VERSION`, `CHANGELOG.md`, `docs/releases/unreleased.md`, and create `docs/releases/vX.Y.Z.md`.
3. Update the release index without deleting any earlier version record.
4. Build and verify the release.
5. Create an annotated version tag.
6. Push `main` and the tag to GitHub.
7. Verify the remote branch and tag with `git ls-remote`.
8. Create or update the GitHub Release for the approved version.
9. Delete the merged feature branch locally and remotely.

## Completion Phrase

- After every completed feature task or successful merge, end the final response with this exact phrase on its own line:

  完成了喵，恭喜主人喵！

- Use this phrase only for completed feature work or a successful merge.
- Do not use it for ordinary questions, status checks, reviews, planning, or incomplete work.
