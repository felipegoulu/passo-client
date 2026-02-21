# Passo - Remote Browser Access

When you need the user to login, complete 2FA, solve a captcha, or do any manual browser action.

## Access URL

{{ACCESS_URL}}

Protected by Google OAuth ({{EMAIL}})

## How to use

1. Send the URL to the user
2. They sign in with Google  
3. They do the action in the browser
4. They say "done"
5. You continue

## Commands

```bash
passo start   # Start the browser tunnel
passo stop    # Stop everything
passo status  # Check if running
```
