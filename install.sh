#!/bin/bash
# Passo - Browser Control
# https://getpasso.app

set -e

PASSO_DIR=~/.passo
RELAY_URL="https://api.getpasso.app"
WEB_URL="https://getpasso.app"

echo ""
echo "  ██████╗  █████╗ ███████╗███████╗ ██████╗ "
echo "  ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔═══██╗"
echo "  ██████╔╝███████║███████╗███████╗██║   ██║"
echo "  ██╔═══╝ ██╔══██║╚════██║╚════██║██║   ██║"
echo "  ██║     ██║  ██║███████║███████║╚██████╔╝"
echo "  ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝ "
echo ""
echo "  Access your browser from anywhere"
echo ""

# Get install code from argument
CODE="$1"

if [ -z "$CODE" ]; then
    # No code provided - start interactive signup flow
    echo "🔐 Creating session..."
    SESSION_RESPONSE=$(curl -sL -X POST "$RELAY_URL/api/cli-session")
    SESSION_ID=$(echo "$SESSION_RESPONSE" | grep -o '"sessionId":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$SESSION_ID" ]; then
        echo "❌ Failed to create session"
        exit 1
    fi
    
    SIGNUP_URL="$WEB_URL/auth?cli_session=$SESSION_ID"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Open this URL in your browser:"
    echo ""
    echo "  $SIGNUP_URL"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "⏳ Waiting for you to sign up and pay..."
    echo "   (This will continue automatically)"
    echo ""
    
    # Poll for session completion
    while true; do
        POLL_RESPONSE=$(curl -sL "$RELAY_URL/api/cli-session/$SESSION_ID")
        STATUS=$(echo "$POLL_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$STATUS" = "complete" ]; then
            TOKEN=$(echo "$POLL_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
            EMAIL=$(echo "$POLL_RESPONSE" | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
            SLUG=$(echo "$POLL_RESPONSE" | grep -o '"slug":"[^"]*"' | cut -d'"' -f4)
            echo ""
            echo "✅ Payment confirmed!"
            break
        elif echo "$POLL_RESPONSE" | grep -q '"error"'; then
            ERROR=$(echo "$POLL_RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
            echo "❌ $ERROR"
            exit 1
        fi
        
        sleep 2
    done
else
    # Code provided - fetch credentials directly
    echo "🔐 Validating code..."
    RESPONSE=$(curl -sL "$RELAY_URL/api/install-code/$CODE")

    # Check for error
    if echo "$RESPONSE" | grep -q '"error"'; then
        ERROR=$(echo "$RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        echo "❌ $ERROR"
        exit 1
    fi

    # Parse response
    TOKEN=$(echo "$RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    EMAIL=$(echo "$RESPONSE" | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
    SLUG=$(echo "$RESPONSE" | grep -o '"slug":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$TOKEN" ] || [ -z "$EMAIL" ] || [ -z "$SLUG" ]; then
    echo "❌ Invalid response from server"
    exit 1
fi

echo "✅ Authenticated as: $EMAIL"
echo "📍 Your handle: $SLUG"
echo ""

# Check OS
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "❌ Linux only for now."
    exit 1
fi

echo "📍 OS: Linux"
echo ""

# Install dependencies
echo "🔍 Installing dependencies..."

sudo apt-get update -qq

if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
echo "✅ Node.js $(node -v)"

if ! command -v jq &> /dev/null; then
    sudo apt-get install -y jq
fi
echo "✅ jq"

DEPS=""
command -v Xvfb &> /dev/null || DEPS="$DEPS xvfb"
command -v chromium-browser &> /dev/null || command -v chromium &> /dev/null || command -v google-chrome &> /dev/null || DEPS="$DEPS chromium-browser"
command -v x11vnc &> /dev/null || DEPS="$DEPS x11vnc"
command -v websockify &> /dev/null || DEPS="$DEPS websockify"

if [ -n "$DEPS" ]; then
    echo "📦 Installing:$DEPS"
    sudo apt-get install -y $DEPS
fi

echo "✅ All dependencies ready"
echo ""

# Setup
mkdir -p "$PASSO_DIR"

ACCESS_URL="$RELAY_URL/b/$SLUG"
cat > "$PASSO_DIR/config.json" << EOF
{
    "email": "$EMAIL",
    "slug": "$SLUG",
    "token": "$TOKEN",
    "accessUrl": "$ACCESS_URL",
    "relayUrl": "$RELAY_URL",
    "installedAt": "$(date -Iseconds)"
}
EOF

# Download client
echo "📦 Installing Passo client..."
curl -sL "https://raw.githubusercontent.com/felipegoulu/passo-client/main/passo-client.js" -o "$PASSO_DIR/passo-client.js"
curl -sL "https://raw.githubusercontent.com/felipegoulu/passo-client/main/package.json" -o "$PASSO_DIR/package.json"
cd "$PASSO_DIR" && npm install --silent
echo "✅ Client installed"
echo ""

# Create scripts
cat > "$PASSO_DIR/start.sh" << 'STARTSCRIPT'
#!/bin/bash
set -e
PASSO_DIR=~/.passo

EMAIL=$(jq -r '.email' "$PASSO_DIR/config.json")
SLUG=$(jq -r '.slug' "$PASSO_DIR/config.json")
TOKEN=$(jq -r '.token' "$PASSO_DIR/config.json")
ACCESS_URL=$(jq -r '.accessUrl' "$PASSO_DIR/config.json")
RELAY_URL=$(jq -r '.relayUrl' "$PASSO_DIR/config.json")

echo "🖥️  Passo - Starting..."

pkill -f "passo-client" 2>/dev/null || true
pkill -f "x11vnc" 2>/dev/null || true
pkill -f "Xvfb.*:99" 2>/dev/null || true
pkill -f "websockify.*6080" 2>/dev/null || true
sleep 1

DISPLAY_NUM=99
while [ -e "/tmp/.X${DISPLAY_NUM}-lock" ]; do DISPLAY_NUM=$((DISPLAY_NUM + 1)); done

Xvfb :$DISPLAY_NUM -screen 0 1280x800x24 &
echo $! > $PASSO_DIR/xvfb.pid
sleep 2
echo "✅ Xvfb on display :$DISPLAY_NUM"

export DISPLAY=:$DISPLAY_NUM
CHROME=$(command -v chromium-browser || command -v chromium || command -v google-chrome)
$CHROME --no-sandbox --disable-gpu --disable-dev-shm-usage --start-maximized "https://google.com" > /dev/null 2>&1 &
echo $! > $PASSO_DIR/chrome.pid
sleep 3
echo "✅ Browser started"

x11vnc -display :$DISPLAY_NUM -forever -shared -nopw -quiet &
echo $! > $PASSO_DIR/x11vnc.pid
sleep 2
echo "✅ VNC server"

websockify 6080 localhost:5900 > /dev/null 2>&1 &
echo $! > $PASSO_DIR/websockify.pid
sleep 1
echo "✅ WebSocket proxy"

cd "$PASSO_DIR"
PASSO_TOKEN="$TOKEN" PASSO_RELAY="${RELAY_URL/https:/wss:}" node passo-client.js -q &
echo $! > $PASSO_DIR/client.pid

sleep 3
echo ""
echo "========================================="
echo "✅ PASSO RUNNING"
echo "🔗 $ACCESS_URL"
echo "🔐 $EMAIL"
echo "Stop: passo stop"
echo "========================================="
STARTSCRIPT
chmod +x "$PASSO_DIR/start.sh"

cat > "$PASSO_DIR/stop.sh" << 'STOPSCRIPT'
#!/bin/bash
echo "🛑 Stopping Passo..."
pkill -f "passo-client" 2>/dev/null || true
pkill -f "x11vnc" 2>/dev/null || true
pkill -f "Xvfb.*:99" 2>/dev/null || true
pkill -f "websockify.*6080" 2>/dev/null || true
rm -f ~/.passo/*.pid
echo "✅ Stopped"
STOPSCRIPT
chmod +x "$PASSO_DIR/stop.sh"

cat > "$PASSO_DIR/status.sh" << 'STATUSSCRIPT'
#!/bin/bash
if pgrep -f "passo-client" > /dev/null; then
    echo "✅ Passo is running"
    jq -r '"🔗 " + .accessUrl + "\n🔐 " + .email' ~/.passo/config.json
else
    echo "⚪ Passo is not running"
    echo "   Start: passo start"
fi
STATUSSCRIPT
chmod +x "$PASSO_DIR/status.sh"

cat > "$PASSO_DIR/passo" << 'CLI'
#!/bin/bash
case "$1" in
    start) exec ~/.passo/start.sh ;;
    stop) exec ~/.passo/stop.sh ;;
    status) exec ~/.passo/status.sh ;;
    *) echo "Usage: passo {start|stop|status}"; exit 1 ;;
esac
CLI
chmod +x "$PASSO_DIR/passo"

sudo ln -sf "$PASSO_DIR/passo" /usr/local/bin/passo 2>/dev/null || true

# Create OpenClaw skill
SKILL_DIR=~/.openclaw/skills/passo
mkdir -p "$SKILL_DIR"

curl -sL "https://raw.githubusercontent.com/felipegoulu/passo-client/main/SKILL.md" | \
    sed "s|{{ACCESS_URL}}|$ACCESS_URL|g" | \
    sed "s|{{EMAIL}}|$EMAIL|g" > "$SKILL_DIR/SKILL.md"

# Update TOOLS.md if it exists
TOOLS_FILE=~/.openclaw/workspace/TOOLS.md
if [ -f "$TOOLS_FILE" ]; then
    # Remove old Passo section if exists
    sed -i.bak '/^## Passo/,/^## [^P]/{ /^## [^P]/!d; }' "$TOOLS_FILE" 2>/dev/null || true
    rm -f "$TOOLS_FILE.bak"
    
    cat >> "$TOOLS_FILE" << TOOLSEOF

## Passo

Remote browser access with Google OAuth protection.

- **URL:** $ACCESS_URL
- **Protected by:** $EMAIL

Send the link when you need the user to handle logins, 2FA, or captchas.
TOOLSEOF
fi

echo "📝 OpenClaw skill created"

echo ""
echo "========================================="
echo "✅ PASSO INSTALLED"
echo ""
echo "   Handle: $SLUG"
echo "   URL:    $ACCESS_URL"
echo ""
echo "   Commands:"
echo "   - passo start"
echo "   - passo stop"
echo "   - passo status"
echo "========================================="
echo ""

read -p "Start Passo now? [Y/n] " START </dev/tty
[[ ! "$START" =~ ^[Nn]$ ]] && exec "$PASSO_DIR/start.sh"
