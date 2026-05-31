#!/bin/sh
set -e

# --- CONFIGURATION ---
LOG_FILE="test-results.log"
HTML_FILE="test-api-report.html"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Initialisation du Log Console (Inchangé)
echo "Order Service API Full Suite - $(date)" > "$LOG_FILE"
echo "----------------------------------------------------------------------" >> "$LOG_FILE"
printf "%-10s | %-40s | %s\n" "STATUS" "TEST DESCRIPTION" "RESULT" | tee -a "$LOG_FILE"
echo "----------------------------------------------------------------------" >> "$LOG_FILE"

# 2. Initialisation du Dashboard HTML (Nouveau look)
cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f4f7f9; padding: 20px; }
        .container { max-width: 850px; margin: auto; }
        .header { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; padding: 20px; border-radius: 12px; text-align: center; 
            box-shadow: 0 4px 15px rgba(0,0,0,0.1); margin-bottom: 25px;
            width: 90%; margin-left: auto; margin-right: auto;
        }
        .test-card { background: white; border-radius: 8px; margin-bottom: 10px; display: flex; justify-content: space-between; align-items: center; padding: 15px 25px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); border-left: 6px solid #ccc; }
        .PASS { border-left-color: #4caf50; }
        .FAIL { border-left-color: #f44336; }
        .badge { padding: 6px 12px; margin-left: 10px; border-radius: 4px; font-weight: bold; font-size: 0.8em; color: white; }
        .bg-PASS { background: #4caf50; }
        .bg-FAIL { background: #f44336; }
        .tech-info { font-size: 0.8em; color: #7f8c8d; font-family: monospace; margin-top: 5px; word-break: break-all; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📦 ORDER SERVICE DASHBOARD</h1>
            <p>Order-Service | Port: $SERVICE_PORT</p>
        </div>
EOF

run_test() {
  DESC="$1"
  CMD="$2"
  DISPLAY_CMD="$3"
  [ -z "$DISPLAY_CMD" ] && DISPLAY_CMD="$CMD"

  if eval "$CMD" > /dev/null 2>&1; then
    printf "${GREEN}%-10s${NC} | %-40s | Success\n" "PASS ✅" "$DESC" | tee -a "$LOG_FILE"
    echo "<div class='test-card PASS'><div><strong>$DESC</strong><div class='tech-info'>$DISPLAY_CMD</div></div><span class='badge bg-PASS'>PASS</span></div>" >> "$HTML_FILE"
  else
    printf "${RED}%-10s${NC} | %-40s | Error\n" "FAIL ❌" "$DESC" | tee -a "$LOG_FILE"
    echo "<div class='test-card FAIL'><div><strong>$DESC</strong><div class='tech-info'>$DISPLAY_CMD</div></div><span class='badge bg-FAIL'>FAIL</span></div>" >> "$HTML_FILE"
    echo "</div></body></html>" >> "$HTML_FILE"
    kill $SERVICE_PID 2>/dev/null || true
    exit 1
  fi
}

# --- DÉMARRAGE DU SERVICE ---
echo "Starting service on port ${SERVICE_PORT}..."
echo "MongoDB URI: $MONGO_URI"
node src/server.js > service-output.log 2>&1 &
SERVICE_PID=$!
sleep 2
echo "Service PID: $SERVICE_PID"
cat service-output.log
echo "---"
if ! kill -0 $SERVICE_PID 2>/dev/null; then
  echo "❌ Service failed to start"
  cat service-output.log
  exit 1
fi
timeout 60 sh -c "until curl -s http://localhost:${SERVICE_PORT}/api/orders/health > /dev/null; do sleep 1; done" || {
  echo "❌ Health check timeout. Service logs:"
  cat service-output.log
  kill $SERVICE_PID 2>/dev/null || true
  exit 124
}

# --- 1. DISPONIBILITÉ ET MÉTRIQUES ---
run_test "1. Health Check (Liveness)" "curl -s http://localhost:${SERVICE_PORT}/api/orders/health | jq -e '.status == \"ok\"'"
run_test "2. Ready Check (Readiness)" "curl -f http://localhost:${SERVICE_PORT}/api/orders/ready | jq -e '.status == \"ready\"'"
run_test "3. Metrics (Prometheus)" "curl -s http://localhost:${SERVICE_PORT}/api/orders/metrics | grep -q 'http_requests_total'"
run_test "4. Service Info (Metadata)" "curl -s http://localhost:${SERVICE_PORT}/api/orders/info | jq -e '.service == \"order-service\"'"

# --- 2. TESTS DES ENDPOINTS ---
run_test "5. Get Order (Auth Check)" "CODE=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${SERVICE_PORT}/api/orders/1) && [ \"\$CODE\" = \"401\" ] || [ \"\$CODE\" = \"200\" ]"
run_test "6. Create Order (Endpoint Existence)" "CODE=\$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:${SERVICE_PORT}/api/orders -H 'Content-Type: application/json' -d '{\"items\":[],\"shipping_address\":\"Test\"}') && [ \"\$CODE\" = \"400\" ] || [ \"\$CODE\" = \"401\" ]"
run_test "7. Update Status (Role Check)" "CODE=\$(curl -s -o /dev/null -w '%{http_code}' -X PUT http://localhost:${SERVICE_PORT}/api/orders/1/status -H 'Content-Type: application/json' -d '{\"status\":\"processing\"}') && [ \"\$CODE\" = \"401\" ] || [ \"\$CODE\" = \"403\" ]"

# --- 3. GESTION DES ERREURS ET DB ---
run_test "8. Invalid Status Handling" "CODE=\$(curl -s -o /dev/null -w '%{http_code}' -X PUT http://localhost:${SERVICE_PORT}/api/orders/1/status -H 'Content-Type: application/json' -d '{\"status\":\"invalid_status\"}') && [ \"\$CODE\" != \"500\" ]"
run_test "9. Non-Existent Order (404/401)" "CODE=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${SERVICE_PORT}/api/orders/9999) && [ \"\$CODE\" = \"404\" ] || [ \"\$CODE\" = \"401\" ]"

# Test DB : On cache les credentials dans le HTML
DB_CMD="COUNT=\$(mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} -sN -e 'SELECT COUNT(*) FROM orders') && [ \"\$COUNT\" -gt 0 ]"
run_test "10. Database Consistency" "$DB_CMD" "mysql -h $DB_HOST -u ${DB_USER} -p**** ${DB_NAME} -e 'SELECT COUNT(*) FROM orders'"

# --- FINALISATION ---
echo "----------------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "${GREEN}Succès : Tous les tests sont passés.${NC}" | tee -a "$LOG_FILE"
echo "</div></body></html>" >> "$HTML_FILE"
kill $SERVICE_PID 2>/dev/null || true