#!/bin/bash
set -e

# Fenix OAuth Login — Browser-based OAuth flow for all platforms
#
# Usage: ./oauth-login.sh [--port PORT]
#
# Opens browser for Fenix OAuth login, captures the token via local callback server.
# Works on macOS, Linux, and WSL.

FENIX_API_URL="${FENIX_API_URL:-https://fenix-api.devshire.app}"
CLIENT_ID="${FENIX_OAUTH_CLIENT_ID:-claude-code}"
CALLBACK_PORT="${1:-9316}"
REDIRECT_URI="http://127.0.0.1:${CALLBACK_PORT}/oauth/callback"

# Generate PKCE code_verifier and code_challenge (S256)
CODE_VERIFIER=$(openssl rand -base64 96 | tr -d '=/+' | head -c 128)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 -e | tr '+/' '-_' | tr -d '=')
STATE=$(openssl rand -hex 16)

# Build authorization URL
AUTH_URL="${FENIX_API_URL}/oauth/authorize"
AUTH_URL="${AUTH_URL}?response_type=code"
AUTH_URL="${AUTH_URL}&client_id=${CLIENT_ID}"
AUTH_URL="${AUTH_URL}&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REDIRECT_URI}'))")"
AUTH_URL="${AUTH_URL}&scope=openid%20profile%20email%20offline_access"
AUTH_URL="${AUTH_URL}&state=${STATE}"
AUTH_URL="${AUTH_URL}&code_challenge=${CODE_CHALLENGE}"
AUTH_URL="${AUTH_URL}&code_challenge_method=S256"

echo "🔐 Fenix OAuth Login"
echo ""
echo "Opening browser for authentication..."
echo ""

# Open browser (cross-platform)
if command -v xdg-open &>/dev/null; then
  xdg-open "$AUTH_URL" 2>/dev/null &
elif command -v open &>/dev/null; then
  open "$AUTH_URL" &
elif command -v wslview &>/dev/null; then
  wslview "$AUTH_URL" &
else
  echo "Could not open browser automatically."
  echo "Please open this URL manually:"
  echo ""
  echo "  $AUTH_URL"
  echo ""
fi

echo "Waiting for authorization callback on port ${CALLBACK_PORT}..."
echo "(Press Ctrl+C to cancel)"
echo ""

# Start a minimal HTTP server to capture the callback
# Uses Python's built-in HTTP server for portability
CALLBACK_SCRIPT=$(cat <<'PYEOF'
import http.server
import urllib.parse
import sys
import json

port = int(sys.argv[1])
expected_state = sys.argv[2]

class CallbackHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if parsed.path != "/oauth/callback":
            self.send_response(404)
            self.end_headers()
            return

        # Check for errors
        if "error" in params:
            error = params["error"][0]
            desc = params.get("error_description", ["Unknown error"])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(f"<h2>Authorization Failed</h2><p>{desc}</p><p>You can close this tab.</p>".encode())
            print(json.dumps({"error": error, "error_description": desc}))
            sys.exit(1)

        # Extract code and state
        code = params.get("code", [None])[0]
        state = params.get("state", [None])[0]

        if not code:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Missing authorization code")
            sys.exit(1)

        if state != expected_state:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"State mismatch — possible CSRF attack")
            sys.exit(1)

        # Success
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(b"<h2>Fenix Connected!</h2><p>You can close this tab and return to your terminal.</p>")

        # Output the code to stdout for the parent script
        print(json.dumps({"code": code, "state": state}))
        sys.exit(0)

    def log_message(self, format, *args):
        pass  # Suppress HTTP logs

server = http.server.HTTPServer(("127.0.0.1", port), CallbackHandler)
server.handle_request()  # Handle exactly one request then exit
PYEOF
)

# Capture the callback
CALLBACK_RESULT=$(python3 -c "$CALLBACK_SCRIPT" "$CALLBACK_PORT" "$STATE" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$CALLBACK_RESULT" ]; then
  echo "❌ Authorization failed or was cancelled."
  exit 1
fi

# Check for error in callback
ERROR=$(echo "$CALLBACK_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)
if [ -n "$ERROR" ]; then
  DESC=$(echo "$CALLBACK_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_description',''))" 2>/dev/null)
  echo "❌ Authorization denied: $DESC"
  exit 1
fi

# Extract authorization code
AUTH_CODE=$(echo "$CALLBACK_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code',''))" 2>/dev/null)

if [ -z "$AUTH_CODE" ]; then
  echo "❌ No authorization code received."
  exit 1
fi

echo "✅ Authorization code received. Exchanging for tokens..."

# Exchange code for tokens
TOKEN_RESPONSE=$(curl -s -X POST "${FENIX_API_URL}/oauth/token" \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"authorization_code\",
    \"code\": \"${AUTH_CODE}\",
    \"client_id\": \"${CLIENT_ID}\",
    \"redirect_uri\": \"${REDIRECT_URI}\",
    \"code_verifier\": \"${CODE_VERIFIER}\"
  }")

# Extract access token
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('refresh_token',''))" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
  ERROR=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_description', d.get('error','Unknown error')))" 2>/dev/null)
  echo "❌ Token exchange failed: $ERROR"
  exit 1
fi

echo ""
echo "✅ Fenix authenticated successfully!"
echo ""

# Output token for the caller to use
# The parent script (fenix-setup) will use this to configure the platform
echo "FENIX_ACCESS_TOKEN=${ACCESS_TOKEN}"
echo "FENIX_REFRESH_TOKEN=${REFRESH_TOKEN}"
