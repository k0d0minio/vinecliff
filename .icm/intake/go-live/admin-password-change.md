# Stub: An admin changes their own password

- feature-slug: admin-password-change
- epic: go-live
- sequence: 5 of 9
- depends-on: none
- complexity: medium
- priority: P1

## Problem

The owner's admin account was created by the migration `drizzle/0001_seed_admin_user.sql` with a password Jamie chose. The password's hash is in git history. The owner has not changed it, and the admin has no way to change it.

## Proposed change

A signed-in admin changes their own password in the admin settings: the current password, then the new one twice.

## Acceptance criteria

- [ ] `/admin/settings` has a "Change your password" form: current password, new password, the new password again.
- [ ] A wrong current password, a new password shorter than 12 characters, or two new passwords that differ, each shows an error under its field. Nothing changes.
- [ ] A valid change stores a new scrypt hash with `lib/auth/password.ts` and ends every other session of that account.
- [ ] The form never logs or returns a password.
- [ ] Unit tests cover the three errors and the valid change.

## Out of scope

- A password reset by email (the offer lists it; breakdown, question 1 for Jamie).
- A second admin account.

## Notes

After the merge reaches production, Jamie asks the owner to change his password at once. The old hash stays in git history, so it is not a secret any more once the owner changes it.
