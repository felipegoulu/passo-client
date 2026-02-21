# Passo Client

The client component that runs on your Linux server and connects to the Passo relay.

## What is Passo?

Passo lets you access your server's browser from anywhere. When your AI agent needs you to handle a login, 2FA, or captcha, you get a secure link on your phone.

## Installation

Get your install command from [getpasso.vercel.app](https://getpasso.vercel.app)

## Files

- `passo-client.js` - WebSocket client that connects to the relay server
- `package.json` - Node.js dependencies
- `SKILL.md` - OpenClaw skill template (placeholders replaced during install)

## How it works

1. The install script sets up an isolated browser (Xvfb + Chromium)
2. x11vnc exposes the display over VNC
3. websockify converts VNC to WebSocket
4. passo-client.js connects to the relay and forwards the traffic
5. You view the browser at your unique URL, protected by Google OAuth

## License

MIT
