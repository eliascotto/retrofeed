# Email Confirmation Token Generation Failure

## Issue Summary

Users can successfully sign up but end up without email confirmation tokens, resulting in no confirmation emails being sent. The signup process completes from the user's perspective, but the account is left in an inconsistent state.

## Affected Code Path

### Registration Flow
**File:** `app/controllers/registrations_controller.rb`  
**Method:** `update` (lines 43-89)

1. User is created with `user.save` (line 76)
2. `user.generate_confirmation_token` is called (line 80)
3. `SendConfirmationEmailJob.perform_later(user.id)` is enqueued (line 81)
4. User is redirected to `resend_confirmation_path` (line 84)

### Token Generation
**File:** `app/models/user.rb`  
**Method:** `generate_confirmation_token` (lines 143-148)

```ruby
def generate_confirmation_token
  self.email_confirmation_token = SecureRandom.urlsafe_base64(32)
  self.email_confirmation_sent_at = Time.current
  save!
  email_confirmation_token
end
```

### Email Job Validation
**File:** `app/jobs/send_confirmation_email_job.rb`  
**Method:** `perform` (lines 4-19)

The job checks `user.confirmation_token_valid?` (line 8), which requires:
- `email_confirmation_token.present?` (from `user.rb` line 167)
- Token not expired

If the token is `NULL`, the job returns early without sending the email (line 8).

## Root Cause

The `generate_confirmation_token` method uses `save!` which raises an exception if the save fails. However, in `registrations_controller.rb`, there is **no error handling** around the call to `generate_confirmation_token` (line 80).

### Failure Scenarios

1. **If `save!` raises an exception:**
   - The exception propagates up the call stack
   - The user record already exists in the database (from line 76)
   - The redirect on line 84 may or may not execute depending on exception handling
   - The user is left with `email_confirmation_token = NULL` and `email_confirmation_sent_at = NULL`

2. **If exception is caught by Rails error handling:**
   - The user sees an error page, but the user record already exists
   - The token fields remain `NULL`
   - The job is still enqueued (line 81 executes before the exception)

3. **Job execution with NULL token:**
   - `SendConfirmationEmailJob` runs asynchronously
   - Line 8: `return unless user.confirmation_token_valid?` evaluates to false (token is NULL)
   - Job returns early without sending email
   - No error is logged or reported

## Observed Symptoms

- Users are successfully created in the database
- `email_confirmation_token` is `NULL`
- `email_confirmation_sent_at` is `NULL`
- `email_confirmed_at` is `NULL`
- No confirmation emails are sent
- No error messages are displayed to the user (if exception is caught)
- No errors are logged by the job (silent failure)

## Impact

- Users cannot confirm their email addresses
- Users cannot access their accounts (if email confirmation is required for login)
- Silent failure makes debugging difficult
- No user-facing error message indicates the problem
- Users may attempt to sign up multiple times, creating duplicate accounts

## Code Locations

- `app/controllers/registrations_controller.rb:80` - Unhandled call to `generate_confirmation_token`
- `app/models/user.rb:143-148` - `generate_confirmation_token` method with `save!`
- `app/jobs/send_confirmation_email_job.rb:8` - Silent return when token is invalid

## Related Issues

- The `confirmations_controller.rb#new` action (line 24-25) is empty, but this is not the root cause - it's just a view action that renders the resend confirmation page.
